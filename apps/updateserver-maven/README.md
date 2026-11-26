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
`https://maven.lucee-services.com/`). The image is Lucee 8 (same tag as
download8). Core versions come from `LuceeVersionsList()` /
`LuceeVersionsDetail()`; extensions are listed from the group-level
`maven-metadata.xml` of `org.lucee` and `io.forgebox` (artifactIds ending
in `-extension`), with versions and detail from `LuceeExtension()`. There is no S3 code path, the
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
Lucee application** (`this.name=lucee-provider-maven-healthcheck`) and is
the liveness probe. `/healthcheck` without the trailing slash 302s to
`/healthcheck/`.

## Readiness

`GET /ready/` is the startup probe. It is also a separate application
(`this.name=lucee-provider-maven-ready`) and answers immediately:
`503 STARTING` until the provider services are loaded, then `200 READY`.
With it as the startup probe, a new revision only gets traffic once it
can serve it, and the previous revision keeps serving until then.

While the services are not loaded, every `/rest/` request is answered
with `503` and `Retry-After: 30` (`NOT_READY_RETRY_AFTER_SECONDS`) right
away instead of waiting for the load.

The first health-check request also fires a background warmup of the
main app (`/warmup/`). Service loading runs in a background thread.
Once `CACHE_DIR` (default `/download/provider`) holds a warm listing cache, list/info endpoints are
served from those JSON files while services finish starting.

## Shared cache with download8

This service and `download.lucee.org` (`apps/download8`) share the same
on-disk cache for core versions and extensions. Both write one JSON file
per key (`luceeVersionsList.json`, `extArtifacts_<groupId>.json`,
`extver_<groupId>_<artifactId>.json`, `extdata_<groupId>_<artifactId>_<version>.json`,
`luceeVerDetail_<version>.json`) into the folder named by
`CACHE_DIRECTORY`, using the same value shapes, stale-while-revalidate
windows, and never-cache-empty rules as download8's `Util.cfc`
(`dlCacheGet` / `dlCachePut`).

Both Cloud Run services must mount the same bucket at the same path and
set `CACHE_DIRECTORY` to that folder:

- bucket: `lucee_downloads`
- mount path: `/download`
- `CACHE_DIRECTORY=/download`

Whichever service is warm first fills the cache for the other. Empty
results are never cached. The image already sets `CACHE_DIRECTORY=/download`.

App-specific files (REST listing JSON, extension meta, Jira issues, Maven
indexes) go under `CACHE_DIR` (default `/download/provider`) so they cannot
collide with download8's `{key}.json` files in the shared folder.

## Listing cache

List and info responses are stored as JSON files under
`CACHE_DIR/listings/{generation}/` (on Cloud Run,
`/download/provider/listings/<K_REVISION>/`):

- `/rest/update/provider/list` (short and extended)
- `/rest/update/provider/info/{version}`
- `/rest/extension/provider/info`

The generation is Cloud Run's `K_REVISION` when that env var is set, or a
per-process boot id otherwise. A new revision therefore never serves
another revision's listing JSON. On boot, leftover `listings/*.json`
files from the earlier (flat) layout are removed; other generation
subdirectories are left alone so a rolling deploy does not wipe a
revision that is still serving traffic.

`LISTING_CACHE_SECONDS` (default **300**, five minutes) is the TTL.
While an entry is fresh it is served as-is. When it is stale, the stale
copy is still served and a background thread refreshes it. A miss (or
`?flush=true`) is refreshed on the request. Writes are atomic (temp
file + rename) so a shared Cloud Storage FUSE mount is not left with a
half-written file.

List and info requests are answered with `503` until the Maven services
are ready (see Readiness) and then rebuild a missing listing. They do not
return a cached copy while startup is still running. `GET /healthcheck/`
and `GET /ready/` are separate applications and answer immediately.

Storage errors on the shared mount (for example "Stale file handle"
after another instance replaced a file while it was open) never leave
the service broken:

- A cache file that cannot be read is read again with a fresh open
  (after 100, 400 and 1000 ms). The extension meta, the extension Maven
  state and the Jira issues also keep a local copy of the last good
  content under the container's temp directory, which is used when the
  shared file still cannot be read. Otherwise it is a cache miss and is
  rebuilt from Maven / Jira.
- Writing a cache file is best effort: a failed write is logged and
  never fails the services load or a request.
- A failed services load is tried again right away (3 attempts), then
  by the next request after `SERVICES_RETRY_SECONDS`. Services that were
  loaded before are kept and still served.
- `/healthcheck/` answers `503` once the services have been failing for
  `HEALTH_FAIL_AFTER_SECONDS` (default 300). It never fails during the
  first load. Add a liveness probe so Cloud Run replaces such a
  container (the startup probe alone only runs at startup):
  `--liveness-probe=httpGetPath=/healthcheck/,periodSeconds=30,timeoutSeconds=5,failureThreshold=3`

The extension listings are built from the extension meta, which is
rebuilt in the background once it is older than
`EXTENSIONS_META_CACHE_SECONDS` (default `LISTING_CACHE_SECONDS`): the
listing cache's refresh brings it up to date first, so a refreshed
listing has the versions published since. The maven-metadata.xml reads
behind it are shared by the instances under `CACHE_DIR/maven/` for
`MAVEN_METADATA_CACHE_SECONDS` (default 300), with the HEAD results of
the download redirects (`maven-head.json`).

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
  -e CACHE_DIRECTORY=/download \
  -e CACHE_DIR=/download/provider \
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

Set the trigger's **included files** filter so only changes to this app
build and deploy a new revision (every new revision has a cold start):

```text
apps/updateserver-maven/**
apps/updateserver/Dockerfile
devops/.CFconfig-update.json5
```

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
couple of minutes when the cache is empty; later revisions are fast
because listings, the shared download8 cache and Maven indexes live on the bucket. `--min-instances 0`
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
  --startup-probe=httpGetPath=/ready/,periodSeconds=10,timeoutSeconds=5,failureThreshold=23,initialDelaySeconds=10 \
  --liveness-probe=httpGetPath=/healthcheck/,periodSeconds=30,timeoutSeconds=5,failureThreshold=3 \
  --set-env-vars=CACHE_DIRECTORY=/download,CACHE_DIR=/download/provider,ALLOW_RELOAD=false,LUCEE_LOGGING_FORCE_APPENDER=console,LISTING_CACHE_SECONDS=300
```

Mount Cloud Storage bucket `lucee_downloads` at `/download` (volume type
Cloud Storage FUSE, the same mapping as the download8 service) so the
shared version/extension cache, listing JSON, Maven indexes and extension
meta survive restarts and are shared with download8 and between instances.
Both services must point `CACHE_DIRECTORY` at that same folder.
`cloudbuild.yaml` only builds the image; the volume and the environment
variables are set on the service.

The image sets `LUCEE_JAVA_OPTS=-Xms256m -Xmx1200m` (Tomcat's `setenv.sh`
copies that into `CATALINA_OPTS`). The base Lucee image defaults to a
512m heap, which is tight for a 2GiB service. A cold start reads
extension `.lex` files with `java.util.zip.ZipFile` so Lucee's `zip://`
resource does not extract whole archives (including large bundled jars)
into `{lucee-config}/temp/compress`. That extract folder previously grew
to several gigabytes and the Cloud Run container was SIGKILL'd with an
out-of-memory event, even though the JVM heap itself was only 512m.

Recommended probe settings (also in the snippet above):

| Setting | Value | Why |
|---------|-------|-----|
| Startup path | `/ready/` | separate app, `503` until the services are loaded |
| Initial delay | 10s | Tomcat start |
| Period | 10s | |
| Timeout | 5s | the probe does not load the main app |
| Failure threshold | 23 | 10s + 23 x 10s = 240s, the most a startup probe can wait; a revision that is not ready by then does not get traffic |
| Liveness path | `/healthcheck/` | `503` only after the services failed to load for `HEALTH_FAIL_AFTER_SECONDS` |

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
| `CACHE_DIRECTORY` | `/download` in the image. Shared with download8 (same keys, same JSON files). Both services must set this to the same folder (the `lucee_downloads` bucket mounted at `/download`). Falls back to `CACHE_DIR`, then `/download`. |
| `CACHE_DIR` | `/download/provider` in the image. App-specific caches (listing JSON, Maven indexes, extension meta, Jira issues) go under this folder so they cannot collide with download8's shared `{key}.json` files. If unset, defaults to `CACHE_DIRECTORY/provider`. |
| `LOCAL_CACHE_DIR` | fallback alias for `CACHE_DIR` when `CACHE_DIR` is not set |
| `LISTING_CACHE_SECONDS` | `300` (five minutes). TTL for list/info JSON under `CACHE_DIR/listings/`. |
| `INFO_CACHE_SECONDS` | `300`. `Cache-Control: public, max-age=` of `/rest/extension/provider/info` and `/info/{id}`. Both send a weak `ETag` and answer `If-None-Match` with 304; `/info` also sends `Last-Modified`. JSON responses are gzip-compressed by Tomcat (set up in `docker-entrypoint.sh`). |
| `DOWNLOAD_CACHE_SECONDS` / `LATEST_CACHE_SECONDS` / `NOT_FOUND_CACHE_SECONDS` | `86400` / `300` / `300`. `Cache-Control: public, max-age=` of the `/full/{id}` and `/trial/{id}` answers: a redirect to an explicitly given version, a redirect to the latest version (no `version`), and a 404. |
| `LUCEE_LOGGING_FORCE_APPENDER` | `console` in the image (needed so `ARTIFACT_NOT_FOUND` lines show up in Cloud Logging) |
| `LUCEE_JAVA_OPTS` | `-Xms256m -Xmx1200m` in the image (a 2GiB Cloud Run container; the base image default is `-Xms64m -Xmx512m`) |
| `ALLOW_RELOAD` | unset/false (`?fwreinit` only works when this is true) |
| `HEALTH_FAIL_AFTER_SECONDS` | `300`. `/healthcheck/` answers `503` once the services have been failing to load this long, so a liveness probe replaces the container. `0` disables it. |
| `REQUEST_TIMEOUT_SECONDS` | `240`. Lucee request timeout, kept below the Cloud Run request timeout (`--timeout 300`). Background work (service load, meta and listing refreshes) has its own timeout. |
| `NOT_READY_RETRY_AFTER_SECONDS` | `30`. `Retry-After` of the `503` a `/rest/` request gets while the services are not loaded yet. |
| `SERVICES_RETRY_SECONDS` | `30`. When loading the provider services fails (for example an IO error on the shared cache folder), the next request after this many seconds starts a new load. The failure is never kept for the life of the instance. |
| `PORT` | Cloud Run sets this to `8080` |
| `EXTENSIONS_MAVEN_REPOS_RELEASES` / `LUCEE_MVN_REPO_RELEASES` | Maven Central |
| `EXTENSIONS_MAVEN_REPOS_SNAPSHOTS` / `LUCEE_MVN_REPO_SNAPSHOTS` | Sonatype snapshots |
| `EXTENSIONS_MAVEN_REPOS_MIXED` / `LUCEE_MVN_REPO_MIXED` | `https://maven.lucee-services.com/` |
| `EXTENSIONS_MAVEN_TIMEOUT` | `20` |
| `EXTENSIONS_MAVEN_DOWNLOAD_TIMEOUT` | `120` |
| `EXTENSIONS_MAVEN_THREADS` | `4` |
| `EXTENSIONS_META_CACHE_SECONDS` | `LISTING_CACHE_SECONDS` (300). Age at which the extension meta is rebuilt in the background |
| `MAVEN_METADATA_CACHE_SECONDS` | `300`. maven-metadata.xml reads shared under `CACHE_DIR/maven/` |
| `EXTENSIONS_MAVEN_FETCH_THREADS` | `5` |
| `EXTENSIONS_MAVEN_ONLY_MIN_CORE` | empty |
| `EXTENSIONS_PACKAGING_BACKFILL_MAX` | `200` |
| `UPDATES_VERSION_FILTER` | `major` |
| `UPDATES_MAVEN_CACHE_SECONDS` | `300` |

Jira changelogs are read from the public Jira Cloud API and cached under
`CACHE_DIR/jira/` (default `/download/provider/jira/`); no Jira token is required. The live Jira fetch runs in the background after the provider is ready and never blocks startup.
