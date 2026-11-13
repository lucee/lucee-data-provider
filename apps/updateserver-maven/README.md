# Maven-only REST update and extension provider (Cloud Run)

This is a **completely separate** app from [`apps/updateserver`](../updateserver),
which stays the Pixl8 deployment (`update.lucee.org` / `extension.lucee.org`
via `endpoint.pixl8.cloud`). Do not change `apps/updateserver`,
`devops/Dockerfile.update`, or the `deploy-to-update` job in
`.github/workflows/ci.yml` for this service.

This app serves the same REST endpoints (`/rest/extension/provider/*`,
`/rest/update/provider/*` including `info`, `list`, download redirects,
`update-for`, and `/healthcheck/`) but talks **only** to the Maven
repositories (Maven Central, Sonatype snapshots, and
`https://maven.lucee-services.com/`). There is no S3 code path, the
image does not install the S3 extension, and the service needs no
secrets (no S3 credentials, no Sentry).

Expected differences versus Pixl8 (`https://update.lucee.org` /
`https://extension.lucee.org`):

- `/rest/update/provider/list` has the versions of the Maven layout (no
  4.x, fewer old snapshots, but the newest releases)
- core and extension downloads redirect to `maven.lucee-services.com` or
  Maven Central instead of `cdn.lucee.org` / `ext.lucee.org`
- endpoints that only exist against S3 answer **501**: `expressTemplates`,
  `forgebox/{version}`, `list-missing` and `buildLatest`

## Health check

`GET /healthcheck/` returns `OK` (200) immediately. It is a **separate
Lucee application** (`this.name=lucee-provider-maven-healthcheck`), so
the Cloud Run startup probe does not wait for Maven metadata to load.
`/healthcheck` without the trailing slash 302s to `/healthcheck/`.

The first health-check request also fires a background warmup of the
main app (`/warmup/`). Service loading runs in a background thread.
Once `CACHE_DIR` holds a warm listing cache, list/info endpoints are
served from those JSON files while services finish starting.

## Listing cache

List and info responses are stored as JSON files under
`CACHE_DIR/listings/` (on Cloud Run, `/storage/listings/`):

- `/rest/update/provider/list` (short and extended)
- `/rest/update/provider/info/{version}`
- `/rest/extension/provider/info`

`LISTING_CACHE_SECONDS` (default **300**, five minutes) is the TTL.
While an entry is fresh it is served as-is. When it is stale, the stale
copy is still served and a background thread refreshes it. A miss (or
`?flush=true`) is refreshed on the request. Writes are atomic (temp
file + rename) so a shared Cloud Storage FUSE mount is not left with a
half-written file.

Other on-disk caches also live under `CACHE_DIR`: `maven-index/`,
`maven-detail/`, `maven-artifacts/`, `extensions/`, `jira/`.

## Missing artifacts

Whenever a requested artifact cannot be provided (a core version, an
extension, a jar/lex, or any other 404/not-found download path), the
app writes **one WARN line** to the console, prefixed with
`ARTIFACT_NOT_FOUND`, so it can be filtered in Cloud Logging:

```text
ARTIFACT_NOT_FOUND type=core path=/rest/update/provider/download/9.9.9.9 version=9.9.9.9 qualifier=lco id= ip=1.2.3.4 ua="Lucee (CFML Engine)"
```

Fields (space-separated `key=value`; `ua` is quoted):

| Field | Meaning |
|-------|---------|
| `type` | `core`, `extension` or `bundle` |
| `path` | request path and query string |
| `id` | extension id or bundle name (empty for core) |
| `version` | requested version |
| `qualifier` | file kind (`lco`, `jar`, `lex`, `war`, …) |
| `ip` | `X-Forwarded-For` (first hop) or `REMOTE_ADDR` |
| `ua` | `User-Agent` |

Cloud Logging filter:

```text
ARTIFACT_NOT_FOUND
```

## Local

From this directory:

```sh
docker compose up --build
# http://localhost:8080/healthcheck/  (should be "OK" right away)
# http://localhost:8080/rest/extension/provider/info
# http://localhost:8080/rest/update/provider/list
```

From the repository root:

```sh
docker build -f apps/updateserver-maven/Dockerfile -t lucee-update-maven .
docker run --rm -p 8080:8080 \
  -e CACHE_DIR=/storage \
  -e LUCEE_LOGGING_FORCE_APPENDER=console \
  lucee-update-maven
```

## Cloud Run (project `fine-way-396107`, region `europe-west1`)

`download.lucee.org` already runs in this project and region. Create or
update the sibling service `lucee-update` with this image. Do not deploy
or map domains from CI.

### 1. Secrets

None. Do not set `S3_EXTENSION_ACCESS_KEY_ID`, `S3_EXTENSION_SECRET_KEY`
or `SENTRY_DSN`. The image does not install the S3 or Sentry extensions.

### 2. Cloud Build trigger (optional to switch)

The existing trigger
[`b40e43f4-fd52-45bf-800e-31657819f623`](https://console.cloud.google.com/cloud-build/triggers;region=global/edit/b40e43f4-fd52-45bf-800e-31657819f623?project=fine-way-396107)
builds `apps/updateserver/Dockerfile`. That file now produces the same
image as `apps/updateserver-maven/Dockerfile` (it copies
`apps/updateserver-maven` into the image), so **switching the trigger is
optional**. Pixl8 does not use `apps/updateserver/Dockerfile`; it builds
`devops/Dockerfile.update`. If you do want the trigger path to match the
app directory, change it to `-f apps/updateserver-maven/Dockerfile` (or
to `--config apps/updateserver-maven/cloudbuild.yaml`). This repository
does not change the trigger or add a deploy job.

Manual build from the repo root, after this PR is on `main`:

```sh
PROJECT=fine-way-396107
REGION=europe-west1
REPO=cloud-run-source-deploy
SERVICE=lucee-update
IMG="${REGION}-docker.pkg.dev/${PROJECT}/${REPO}/${SERVICE}:$(git rev-parse --short HEAD)"

gcloud builds submit --project "$PROJECT" --region "$REGION" \
  --config apps/updateserver-maven/cloudbuild.yaml \
  --substitutions=_IMAGE="$IMG" \
  .
```

### 3. Create or update the service

`/healthcheck/` answers immediately, so the startup probe can stay
short. The first request that needs Maven metadata can still take a
couple of minutes when `CACHE_DIR` is empty; later revisions are fast
because listings and Maven indexes live on the bucket. `--min-instances 0`
is fine while testing; once the domains point here, `--min-instances 1`
avoids a cold start on a Lucee "check for updates".

```sh
gcloud run deploy "$SERVICE" \
  --project "$PROJECT" \
  --region "$REGION" \
  --image "$IMG" \
  --port 8080 \
  --allow-unauthenticated \
  --cpu 2 \
  --memory 2Gi \
  --timeout 300 \
  --cpu-boost \
  --min-instances 0 \
  --max-instances 4 \
  --startup-probe=httpGetPath=/healthcheck/,periodSeconds=5,timeoutSeconds=5,failureThreshold=12,initialDelaySeconds=10 \
  --set-env-vars=CACHE_DIR=/storage,ALLOW_RELOAD=false,LUCEE_LOGGING_FORCE_APPENDER=console,LISTING_CACHE_SECONDS=300
```

Mount a Cloud Storage bucket at `/storage` (volume type Cloud Storage
FUSE, bucket `lucee_data_provider`, mount path `/storage`) so the
listing JSON, Maven indexes and extension meta survive restarts and are
shared between instances. `cloudbuild.yaml` only builds the image; the
volume and the environment variables are set on the service.

Recommended probe settings (also in the snippet above):

| Setting | Value | Why |
|---------|-------|-----|
| Path | `/healthcheck/` | separate app, returns `OK` immediately |
| Initial delay | 10s | Tomcat start |
| Period | 5s | |
| Timeout | 5s | health check does not load the main app |
| Failure threshold | 12 | about one minute for Tomcat, not Maven |

### 4. Test the `run.app` URL

```sh
URL=$(gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" --format='value(status.url)')
curl -fsS "$URL/healthcheck/"
curl -fsS -o /dev/null -w '%{http_code}\n' "$URL/rest/extension/provider/info"
curl -fsS "$URL/rest/update/provider/list" | head
curl -fsS "$URL/rest/update/provider/info/7.0.0.395" | head
```

Compare those answers with `https://extension.lucee.org` and
`https://update.lucee.org` before touching DNS. See the expected
differences at the top of this file.

## Environment variables

No secrets. All of these are optional (the image already sets the Cloud
Run defaults):

| Name | Default |
|------|---------|
| `CACHE_DIR` | `/storage` in the image. Listing JSON, Maven caches, extension meta and Jira issues go under this folder. |
| `LOCAL_CACHE_DIR` | fallback alias for `CACHE_DIR` when `CACHE_DIR` is not set |
| `LISTING_CACHE_SECONDS` | `300` (five minutes). TTL for list/info JSON under `CACHE_DIR/listings/`. |
| `LUCEE_LOGGING_FORCE_APPENDER` | `console` in the image (needed so `ARTIFACT_NOT_FOUND` lines show up in Cloud Logging) |
| `ALLOW_RELOAD` | unset/false (`?fwreinit` only works when this is true) |
| `PORT` | Cloud Run sets this to `8080` |
| `EXTENSIONS_MAVEN_REPOS_RELEASES` / `LUCEE_MVN_REPO_RELEASES` | Maven Central |
| `EXTENSIONS_MAVEN_REPOS_SNAPSHOTS` / `LUCEE_MVN_REPO_SNAPSHOTS` | Sonatype snapshots |
| `EXTENSIONS_MAVEN_REPOS_MIXED` / `LUCEE_MVN_REPO_MIXED` | `https://maven.lucee-services.com/` |
| `EXTENSIONS_MAVEN_TIMEOUT` | `20` |
| `EXTENSIONS_MAVEN_DOWNLOAD_TIMEOUT` | `120` |
| `EXTENSIONS_MAVEN_THREADS` | `10` |
| `EXTENSIONS_MAVEN_FETCH_THREADS` | `5` |
| `EXTENSIONS_MAVEN_ONLY_MIN_CORE` | empty |
| `EXTENSIONS_PACKAGING_BACKFILL_MAX` | `200` |
| `UPDATES_VERSION_FILTER` | `major` |
| `UPDATES_MAVEN_CACHE_SECONDS` | `300` |

Jira changelogs are read from the public Jira Cloud API and cached under
`CACHE_DIR/jira/`; no Jira token is required.
