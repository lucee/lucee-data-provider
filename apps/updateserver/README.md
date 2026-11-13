# REST update and extension provider

This is the CFML REST application behind `update.lucee.org` and `extension.lucee.org`.
Both hostnames are the same app: Lucee REST mappings in `rest/UpdateProvider.cfc` and
`rest/ExtensionProvider.cfc`.

Today those hostnames still point at Pixl8 (`endpoint.pixl8.cloud`). CI keeps building
`markdrew/lucee-update` from `devops/Dockerfile.update` and deploying it with
`DEPLOY_API_ENDPOINT` (`deploy-to-update` in `.github/workflows/ci.yml`). That path is
unchanged.

This directory also has a **Cloud Run** image, in the same style as
`download.lucee.org` (`apps/download8`): a tomcat-only Lucee light image whose
entrypoint listens on `$PORT` (Cloud Run sets this to 8080). Use it to stand up a
new Cloud Run service so the two hostnames can later move from Pixl8 to Google.
Do not change DNS until that service has been tested on its `run.app` URL.

## Storage modes

The app runs in one of two modes, chosen with the `STORAGE` environment variable:

- **`s3`** (the default, what Pixl8 runs): the Maven repositories first, the old flat
  files of S3 as the fallback, caches (extension meta, bundle lookups, Jira issues)
  kept in S3. Needs the S3 credentials.
- **`maven`** (`STORAGE=maven`, or `NO_S3=true`): a proxy over the Maven repositories
  only (Maven Central, Sonatype snapshots and `https://maven.lucee-services.com/`).
  Nothing is read from or written to S3 and no S3 credentials are needed:
  - core versions and `/rest/update/provider/list` come from the `maven-metadata.xml`
    of `org.lucee:lucee`; downloads (`loader`, `light`, `download`, `war`, `express`,
    `latest/.../redirect`) are 302s to the Maven file, `maven.lucee-services.com` first.
  - extensions are listed from the Maven repositories (each `.lex` is read once per
    instance for its manifest); `full/{id}` and `trial/{id}` redirect to the Maven
    file, `maven.lucee-services.com` first. A file that is in no Maven repository is a 404.
  - bundles (`download/{name}/{version}`) come from the Maven matcher only (no
    `bundle.lucee.org` bucket); lookups are cached in memory.
  - the extension meta and the Jira issues are cached on the local disk under
    `CACHE_DIR` (`LOCAL_CACHE_DIR` is a fallback alias; the default is the Lucee
    temp directory), so a new instance builds them again on its first start unless
    `CACHE_DIR` points at a persistent volume (about two minutes for ~1000 extension
    files when the cache is empty). The same `CACHE_DIR` also holds the Maven
    index, detail and artifact caches (`maven-index/`, `maven-detail/`,
    `maven-artifacts/`).
  - what only exists in S3 answers **501**: `expressTemplates` (there is no Maven
    artifact of the express templates), `forgebox/{version}`, `list-missing` and
    `buildLatest`. Versions and files that are only in the flat S3 files (old 4.x/5.x
    releases, old snapshots) are not offered.

A Cloudflare Worker port of the extension endpoints only lives in
`apps/extension-worker`; it is not deployed and is not used here.

## Local

From this directory, without S3 (no credentials needed):

```sh
STORAGE=maven docker compose up --build
# http://localhost:8080/healthcheck/  (should be "OK")
# http://localhost:8080/rest/extension/provider/info
# http://localhost:8080/rest/update/provider/list
```

With S3 (as Pixl8), export `S3_EXTENSION_ACCESS_KEY_ID` and `S3_EXTENSION_SECRET_KEY`
and run `docker compose up --build` without `STORAGE`.

From the repository root:

```sh
docker build -f apps/updateserver/Dockerfile -t lucee-update .
docker run --rm -p 8080:8080 -e STORAGE=maven \
  -e LUCEE_LOGGING_FORCE_APPENDER=console \
  lucee-update
```

The Cloud Run image does not install Sentry. Set
`LUCEE_LOGGING_FORCE_APPENDER=console` as in the example (`docker compose`
already does). The Pixl8 image (`devops/Dockerfile.update`) still uses Sentry
when `SENTRY_DSN` is set.

The first start can take well over a minute: `Application.cfc` loads extension
metadata and core versions before it serves traffic.

## Health check

`GET /healthcheck/` returns `OK` (200). That is the Docker `HEALTHCHECK` and the
Cloud Run startup probe. `/healthcheck` without the trailing slash 302s to
`/healthcheck/`.

## Cloud Run (project `fine-way-396107`, region `europe-west1`)

`download.lucee.org` already runs in this project and region as the
`lucee-data-provider` service (the `apps/download8` image). MCP uses the same
project, with images in Artifact Registry repository `cloud-run-source-deploy`
and a manual deploy:

```text
gcloud builds submit --tag $IMG
gcloud run deploy <service> --region europe-west1 --image $IMG
```

Create a sibling service named `lucee-update`. Do not deploy or map domains from
CI; run the following from a machine that is already signed into that GCP project
(after this PR is merged, from the repo root on `main`).

### 1. Secrets

None. The Cloud Run service runs with `STORAGE=maven` (see
[Storage modes](#storage-modes)): it only proxies the Maven repositories, so it
needs no S3 credentials and no secrets.

The Cloud Run image does not install the Sentry extension or import
`.CFconfig-sentry.json`. Leave `SENTRY_DSN` unset. The Pixl8 image
(`devops/Dockerfile.update`) is unchanged and still uses Sentry when
`SENTRY_DSN` is set.

### 2. Build and push the image

```sh
PROJECT=fine-way-396107
REGION=europe-west1
REPO=cloud-run-source-deploy
SERVICE=lucee-update
IMG="${REGION}-docker.pkg.dev/${PROJECT}/${REPO}/${SERVICE}:$(git rev-parse --short HEAD)"

gcloud builds submit --project "$PROJECT" --region "$REGION" \
  --config apps/updateserver/cloudbuild.yaml \
  --substitutions=_IMAGE="$IMG" \
  .
```

### 3. Create or update the service

The first start is slow (it reads the core versions and every extension file from
the Maven repositories, about two minutes when the on-disk cache is empty), so
the startup probe allows several minutes. `--min-instances 0` is fine while
testing; once the domains point here, `--min-instances 1` avoids that cold start
on a Lucee "check for updates". Adjust CPU and memory if the first revision is
tight.

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
  --startup-probe=httpGetPath=/healthcheck/,periodSeconds=10,timeoutSeconds=5,failureThreshold=30,initialDelaySeconds=15 \
  --set-env-vars=STORAGE=maven,ALLOW_RELOAD=false,LUCEE_LOGGING_FORCE_APPENDER=console,CACHE_DIR=/storage
```

Mount a Cloud Storage bucket at `/storage` so on-disk caches (extension meta,
Jira issues, Maven indexes, artifacts, and so on) survive restarts and are
shared between instances. In the Cloud Run console this is a volume of type
Cloud Storage FUSE, bucket `lucee_data_provider`, mount path `/storage`. Then
set `CACHE_DIR=/storage` as above. `cloudbuild.yaml` only builds the image; the
volume and this variable are set on the service when you deploy or update it.

### 4. Test the `run.app` URL

```sh
URL=$(gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" --format='value(status.url)')
curl -fsS "$URL/healthcheck/"
curl -fsS -o /dev/null -w '%{http_code}\n' "$URL/rest/extension/provider/info"
curl -fsS "$URL/rest/update/provider/list" | head
```

Compare those answers with `https://extension.lucee.org` and
`https://update.lucee.org` before touching DNS. Expected differences in the Maven
only mode: `/rest/update/provider/list` has the versions of the Maven layout (no
4.x, fewer old snapshots, but the newest releases), extension downloads redirect to
`maven.lucee-services.com` or Maven Central instead of `cdn.lucee.org`, and the
endpoints listed under [Storage modes](#storage-modes) answer 501.

### 5. Custom domains (later, not part of standing the service up)

When the `run.app` URL looks right, map both hostnames to this one service (they
share the app today) and only then change Route 53 from `endpoint.pixl8.cloud`
to `ghs.googlehosted.com`:

```sh
gcloud beta run domain-mappings create --project "$PROJECT" --region "$REGION" \
  --service "$SERVICE" --domain update.lucee.org
gcloud beta run domain-mappings create --project "$PROJECT" --region "$REGION" \
  --service "$SERVICE" --domain extension.lucee.org
```

Leave the Pixl8 service and the `deploy-to-update` CI job in place until DNS has
been switched and old caches have expired.

## Environment variables

Required with `STORAGE=s3` (the default), not used with `STORAGE=maven`:

| Name | |
|------|--|
| `S3_EXTENSION_ACCESS_KEY_ID` | AWS key used for every `s3://` path (`this.s3` in `Application.cfc`) |
| `S3_EXTENSION_SECRET_KEY` | Matching secret |

Optional (defaults in `Application.cfc` are what production uses today; the `S3_*`
and `*_FLAT_S3_FALLBACK` ones are ignored with `STORAGE=maven`):

| Name | Default |
|------|---------|
| `STORAGE` | `s3`; `maven` for the Maven only mode without S3 (`NO_S3=true` does the same) |
| `CACHE_DIR` | empty (write caches next to the CFCs, as Pixl8 does; in Maven only mode, extension meta and Jira issues go under the Lucee temp directory). On Cloud Run set this to `/storage`. Subfolders: `s3-versions/`, `maven-index/`, `maven-detail/`, `maven-artifacts/`, and in Maven only mode also `extensions/` and `jira/`. |
| `LOCAL_CACHE_DIR` | fallback alias for `CACHE_DIR` when `CACHE_DIR` is not set |
| `LUCEE_LOGGING_FORCE_APPENDER` | unset. On Cloud Run set this to `console`. |
| `ALLOW_RELOAD` | unset/false (`?fwreinit` only works when this is true) |
| `S3_CORE_ROOT` | `s3:///lucee-downloads/` |
| `S3_CORE_CDN_URL` | `https://cdn.lucee.org/` |
| `S3_EXTENSIONS_ROOT` | `s3:///extension-downloads/` |
| `S3_EXTENSIONS_CDN_URL` | `https://ext.lucee.org/` |
| `S3_EXTENSIONS_MAVEN_PATH` | `org/lucee/` |
| `S3_BUNDLES_ROOT` | `s3:///bundle-download/` |
| `S3_BUNDLES_CDN_URL` | `https://bundle.lucee.org/` |
| `EXTENSIONS_MAVEN_REPOS_ENABLED` | `true` |
| `EXTENSIONS_MAVEN_REPOS_RELEASES` / `LUCEE_MVN_REPO_RELEASES` | Maven Central |
| `EXTENSIONS_MAVEN_REPOS_SNAPSHOTS` / `LUCEE_MVN_REPO_SNAPSHOTS` | Sonatype snapshots |
| `EXTENSIONS_MAVEN_REPOS_MIXED` / `LUCEE_MVN_REPO_MIXED` | `https://maven.lucee-services.com/` |
| `EXTENSIONS_MAVEN_TIMEOUT` | `20` |
| `EXTENSIONS_MAVEN_DOWNLOAD_TIMEOUT` | `120` |
| `EXTENSIONS_MAVEN_THREADS` | `10` |
| `EXTENSIONS_MAVEN_FETCH_THREADS` | `5` |
| `EXTENSIONS_FLAT_S3_FALLBACK` | `true` |
| `EXTENSIONS_MAVEN_ONLY_MIN_CORE` | empty |
| `EXTENSIONS_PACKAGING_BACKFILL_MAX` | `200` |
| `UPDATES_MAVEN_REPOS_ENABLED` | `true` |
| `UPDATES_FLAT_S3_FALLBACK` | `true` |
| `UPDATES_VERSION_FILTER` | `major` |
| `UPDATES_MAVEN_CACHE_SECONDS` | `300` |

Jira changelogs are read from the public Jira Cloud API and cached under
`S3_CORE_ROOT` (or under `CACHE_DIR/jira/` with `STORAGE=maven`); no Jira token is required.

`S3_DOWNLOAD_ACCESS_KEY_ID` and `S3_DOWNLOAD_SECRET_KEY` are used only by
`apps/download`, not by this app.
