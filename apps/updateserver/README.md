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

A Cloudflare Worker port of the extension endpoints only lives in
`apps/extension-worker`; it is not deployed and is not used here.

## Local

From this directory, with the same S3 credentials the Pixl8 service uses:

```sh
docker compose up --build
# http://localhost:8080/healthcheck/  (should be "OK")
# http://localhost:8080/rest/extension/provider/info
# http://localhost:8080/rest/update/provider/list
```

From the repository root:

```sh
docker build -f apps/updateserver/Dockerfile -t lucee-update .
docker run --rm -p 8080:8080 \
  -e S3_EXTENSION_ACCESS_KEY_ID \
  -e S3_EXTENSION_SECRET_KEY \
  lucee-update
```

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

Create these in Secret Manager (names only; reuse the values already set on the
Pixl8 service). They are required for the app to reach the extension and core
buckets:

- `S3_EXTENSION_ACCESS_KEY_ID`
- `S3_EXTENSION_SECRET_KEY`

Optional, for the Sentry loggers already baked into the image:

- `SENTRY_DSN`

```sh
# example: create an empty secret, then add a version from a file you do not commit
gcloud secrets create S3_EXTENSION_ACCESS_KEY_ID --project=fine-way-396107
gcloud secrets versions add S3_EXTENSION_ACCESS_KEY_ID --project=fine-way-396107 --data-file=...
```

The Cloud Run runtime service account needs `roles/secretmanager.secretAccessor`
on those secrets.

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

The first start is slow, so the startup probe allows several minutes, and
`--min-instances=1` avoids a cold start on every Lucee "check for updates".
Adjust CPU and memory if the first revision is tight.

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
  --min-instances 1 \
  --max-instances 4 \
  --startup-probe=httpGetPath=/healthcheck/,periodSeconds=10,timeoutSeconds=5,failureThreshold=30,initialDelaySeconds=15 \
  --set-env-vars=SENTRY_ENV=production,ALLOW_RELOAD=false \
  --set-secrets=S3_EXTENSION_ACCESS_KEY_ID=S3_EXTENSION_ACCESS_KEY_ID:latest,S3_EXTENSION_SECRET_KEY=S3_EXTENSION_SECRET_KEY:latest
```

If `SENTRY_DSN` was created, add it in a follow-up update:

```sh
gcloud run services update "$SERVICE" --project "$PROJECT" --region "$REGION" \
  --set-secrets=SENTRY_DSN=SENTRY_DSN:latest
```

### 4. Test the `run.app` URL

```sh
URL=$(gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" --format='value(status.url)')
curl -fsS "$URL/healthcheck/"
curl -fsS -o /dev/null -w '%{http_code}\n' "$URL/rest/extension/provider/info"
curl -fsS "$URL/rest/update/provider/list" | head
```

Compare those answers with `https://extension.lucee.org` and
`https://update.lucee.org` before touching DNS.

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

Required:

| Name | |
|------|--|
| `S3_EXTENSION_ACCESS_KEY_ID` | AWS key used for every `s3://` path (`this.s3` in `Application.cfc`) |
| `S3_EXTENSION_SECRET_KEY` | Matching secret |

Optional (defaults in `Application.cfc` are what production uses today):

| Name | Default |
|------|---------|
| `SENTRY_DSN` | empty (Sentry loggers no-op) |
| `SENTRY_ENV` | empty (`production` on Cloud Run) |
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
`S3_CORE_ROOT`; no Jira token is required.

`S3_DOWNLOAD_ACCESS_KEY_ID` and `S3_DOWNLOAD_SECRET_KEY` are used only by
`apps/download`, not by this app.
