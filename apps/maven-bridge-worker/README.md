# Maven bridge worker

Cloudflare Worker port of [`apps/maven-bridge`](../maven-bridge) — the Maven repository layout behind
`maven.lucee-services.com`. It serves the same paths with the same answers, without a JVM and
without Cloud Run, and it can serve artifacts straight from Cloudflare R2.

It serves **`maven.lucee-services.com`** and the test hostname **`mvn.lucee-services.com`**.
The Cloud Run service stays deployed as a rollback until it is retired.

## What it does

| Path | Answer |
|------|--------|
| `/` | landing page (groups, artifacts, latest versions) |
| `/health`, `/healthcheck`, `/health.cfm` | JSON status, artifact count and providers |
| `/{group}/`, `/{group}/maven-metadata.xml` | group index / group metadata |
| `/{group}/{artifact}/maven-metadata.xml` | versions of an artifact |
| `/{group}/{artifact}/{version}/…` | version index, version metadata, pom, artifact files |

Two kinds of groups, configured in `EXTENSION_PROVIDERS`:

- **REST provider groups** (`io.forgebox`): the provider's `/rest/extension/provider/info` index is
  translated into Maven metadata; `.lex` files redirect (302) to the provider download URL; poms are
  generated.
- **Upstream mirror groups** (`org.lucee` → `https://cdn.lucee.org/`): metadata and indexes are passed
  through from the upstream; files redirect (302) to the upstream. Lucee core files (`org.lucee:lucee`)
  are looked up in this order: GitHub Releases (7.1+ final/RC jar, lco, war, light, zero, express),
  the Maven layout on the CDN (`org/lucee/lucee/8.0.1.12-SNAPSHOT/lucee-8.0.1.12-SNAPSHOT.pom`, also
  every pom and snapshot), then the legacy flat CDN names (`lucee-light-6.2.0.321.jar`,
  `6.2.0.321.lco`, …) for older builds. Existence checks are HEAD requests; hits are cached.

#### Checksums

`.sha1`, `.md5`, `.sha256` and `.sha512` files (plain hex digest, as Maven expects):

- Upstream mirror groups redirect to the upstream checksum file when there is one (core files: Maven
  layout first, then the legacy name, e.g. `lucee-6.2.0.321.jar.sha1`, `6.2.0.321.lco.sha1`).
- Otherwise (core poms, RCs and snapshots have none on the CDN) the checksum is computed from the
  artifact the bridge serves (R2 object, GitHub Release asset or CDN file): streamed, never buffered,
  only for artifacts up to `CHECKSUM_MAX_MB`. One download yields all four checksum types (native
  `crypto.DigestStream`, read in 1 MiB blocks into one reused buffer). Artifacts over
  `CHECKSUM_INLINE_MAX_MB` (core jars) are hashed in the background (`waitUntil`, same download):
  the request answers 404 right away (`cache-control: no-store`), which Maven only warns about, and
  the next request after the hash is cached gets it; a KV marker (`checksum-pending:…`, 5 minutes)
  keeps parallel and repeated requests from downloading the artifact again meanwhile. Background work
  shares the invocation's CPU and memory limits and must finish within 30 s of the response; runs
  ended early are counted (`checksum-attempts:…`) and logged, and after 3 the artifact is left alone
  for a day. A download that ends short of its `content-length` is never cached. Results
  are cached in KV, for 30 days for immutable artifacts and for `CACHE_TTL_MINUTES` for snapshots;
  with fill-on-miss, checksums of immutable artifacts are also stored in R2 next to the artifact.
- REST provider groups have no checksum files: pom checksums are computed from the generated pom,
  `.lex` checksums from the provider download. Anything else answers 404, never the artifact.

### R2

With `R2_MODE = "serve"` every artifact file request first looks in the `ARTIFACTS` bucket. A hit is
streamed by the worker (content type, ETag, Last-Modified, Content-Length, `Range` → 206,
`If-None-Match`/`If-Modified-Since` → 304, `HEAD`). A miss falls back to the redirect logic above.
Group-level files (`maven-metadata.xml`, `index.html`) of upstream groups are read from R2 first too.

Object keys use the Maven layout of the upstream, so a copy of `cdn.lucee.org` can be used as is:

- `org/lucee/redis-extension/3.0.0.1/redis-extension-3.0.0.1.lex`, `org/lucee/lucee/7.1.0.10/lucee-7.1.0.10.jar`
- core files are also looked up under their legacy flat CDN name at the bucket root
  (`lucee-light-6.2.0.321.jar`, `6.2.0.321.lco`) when the Maven-layout key is missing; fill on miss
  always writes the Maven-layout key.

`R2_PREFIX` is prepended to every key.

#### Fill on miss (lazy migration)

With `R2_MODE = "serve"` and `R2_FILL_ON_MISS = "true"`, a miss for an upstream-mirror file is fetched
from its source (GitHub Releases or the CDN) and stored in R2 under its Maven-layout key. The next request is
served from R2.

- Files up to `R2_FILL_STREAM_MAX_MB` (default 32) are streamed to the client and stored at the same
  time (`waitUntil`).
- Larger files (core jars, express zips) are stored first and then served from R2, so a slow client
  never makes the worker hold a large file in memory.
- If the source cannot be reached, or the store fails, the request falls back to the redirect.

Only immutable files are stored: a `200` answer with a known `Content-Length` and no `Content-Encoding`, for a plain `GET`
(no `Range`), and never `SNAPSHOT` versions, `maven-metadata.xml*` or `index.html`. Anything else
keeps the redirect behaviour. Stored objects carry `customMetadata.source` and `filledAt`.

ForgeBox downloads are not filled (they are served by ForgeBox, not mirrored).

### Caching

The CFML bridge kept everything in the server scope. Here:

- **KV (`BRIDGE_CACHE`)**: REST provider indexes (`index:<groupId>`) and upstream group files
  (`upstream:<url>`), refreshed by the **hourly cron**. Entries older than `CACHE_TTL_MINUTES` are
  served while a refresh runs in the background; if the provider is down the last good copy is used.
  Computed checksums (`checksum:<generation>:<type>:<source>`) are kept in KV too, with an expiration,
  next to the short-lived markers of background computations (`checksum-pending:<generation>:<source>`)
  and their attempt counts (`checksum-attempts:<generation>:<source>`, 1 day).
- **Cache API**: upstream metadata/index pages and positive `HEAD` checks on the upstream, keyed by a
  cache generation that a flush bumps.

### Flush

`?flush=true` (also `1`, `yes`, `force`) on any path empties KV, bumps the cache generation (which also drops
computed checksums cached in KV; checksums stored in R2 stay) and resyncs,
like `health.cfm?flush=true`. It needs the `FLUSH_TOKEN` secret, sent as `X-Flush-Token: <token>` or
`Authorization: Bearer <token>`. Without the secret flushing is disabled (403).

```sh
curl -H "X-Flush-Token: $FLUSH_TOKEN" "https://mvn.lucee-services.com/health?flush=true"
```

## Configuration

`wrangler.toml` `[vars]` (no secrets in the file):

| Variable | Default | Meaning |
|----------|---------|---------|
| `EXTENSION_PROVIDERS` | ForgeBox + extension.lucee.org/cdn | `provider\|groupId[\|upstream]`, comma separated, or a JSON array of `{provider, groupId, upstream}` |
| `CACHE_TTL_MINUTES` | `60` | age after which KV entries are refreshed |
| `TIMEOUT` | `300` | upstream/provider timeout in seconds |
| `GITHUB_RELEASES_URL` | `https://github.com/lucee/Lucee/releases/download/` | 7.1+ core builds; empty disables |
| `R2_MODE` | `off` | `off` or `serve` |
| `R2_FILL_ON_MISS` | `false` | store immutable upstream files in R2 on first request (serve mode only) |
| `CHECKSUM_MAX_MB` | `128` | checksums the upstream does not have are computed for artifacts up to this size; larger ones answer 404 (`0` = never compute) |
| `CHECKSUM_INLINE_MAX_MB` | `16` | computed checksums of larger artifacts are hashed in the background and answer 404 until cached (`0` = always in the background) |
| `R2_FILL_STREAM_MAX_MB` | `32` | fill-on-miss files up to this size are streamed while stored; larger ones are stored first (`0` = always store first) |
| `R2_PREFIX` | empty | key prefix in the bucket |

Secrets: `FLUSH_TOKEN` (`wrangler secret put FLUSH_TOKEN`; CI sets it from the
`MAVEN_BRIDGE_FLUSH_TOKEN` secret when that exists).

Bindings: KV `BRIDGE_CACHE` (namespace `lucee-maven-bridge-cache`), R2 `ARTIFACTS`
(bucket `lucee-artifacts`, only read in serve mode). Custom domains: `maven.lucee-services.com`, `mvn.lucee-services.com`.

## Develop and test

Node 22+.

```sh
cd apps/maven-bridge-worker
npm ci
npm test            # vitest in the Workers runtime (@cloudflare/vitest-plugin), no network
npm run typecheck
npm run dry-run     # wrangler deploy --dry-run --outdir dist
npm run dev         # local worker on http://localhost:8787 with local KV/R2
```

The tests mock `fetch`, so they never reach ForgeBox, the CDN or GitHub. `test/fixtures` holds a real
ForgeBox provider answer and the pom production generates for it.

## Deploy

`.github/workflows/maven-bridge-worker.yml`:

- pull requests touching `apps/maven-bridge-worker/**`: typecheck, tests, dry run — no deploy
- push to `main` touching the folder, or a manual run on `main`: tests, then
  `scripts/provision.mjs` creates the KV namespace and the R2 bucket if missing (idempotent) and writes
  the KV id into `wrangler.toml`, then `cloudflare/wrangler-action` deploys

It uses the org secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`; they are passed only to the
provision, deploy and secret steps. Token permissions:

- Account: Workers Scripts Edit, Workers KV Storage Edit, Workers R2 Storage Edit
- Zone `lucee-services.com`: Workers Routes Edit (custom domain), DNS Edit

Cloudflare creates the DNS record of each custom domain. A deploy from CI (non-interactive) replaces an
existing DNS record on that hostname; an interactive `wrangler deploy` asks first.

Rollback for `maven.lucee-services.com`: remove it from `routes` and deploy (this removes the custom domain
and its record), then restore the DNS-only CNAME `maven` → `ghs.googlehosted.com` (Cloud Run).

## Compare with production

```sh
npm run compare -- --prod https://maven.lucee-services.com --target https://mvn.lucee-services.com
npm run compare -- --paths my-paths.txt --method HEAD
```

`scripts/compare.mjs` requests each path on both hosts without following redirects and compares status,
`Location` and a SHA-256 of the body (generated timestamps normalized; `--strict` disables that).
It exits with 1 when anything differs.

## Cutover plan

1. **Test host**: deploy to `mvn.lucee-services.com` with `R2_MODE = "off"` (pure port, same redirects).
2. **Compare**: run `scripts/compare.mjs` against `maven.lucee-services.com` with a path list taken
   from real traffic; point a Lucee 7 test instance at `https://mvn.lucee-services.com/` and install
   extensions/core updates.
3. **Flip `maven.lucee-services.com`**: move the hostname from Cloud Run to this worker (add it as a
   second custom domain), keep Cloud Run running for a quick rollback, then retire it.
4. **Move artifacts to R2**, then set `R2_MODE = "serve"`:
   - **Bulk copy**: [Super Slurper](https://developers.cloudflare.com/r2/data-migration/super-slurper/)
     for a one-off copy of the bucket behind `cdn.lucee.org`, or
     [Sippy](https://developers.cloudflare.com/r2/data-migration/sippy/) on the `lucee-artifacts`
     bucket, which copies objects from the source bucket into R2 on first access. Both need the
     source to be an S3-compatible or GCS bucket and keep its key layout, which is the layout
     the worker expects.
   - **Lazy alternative**: `R2_FILL_ON_MISS = "true"` fills R2 from whatever the worker would
     redirect to (CDN or GitHub Releases), without access to the source bucket; files nobody asks
     for are never copied.
   - Once R2 has everything, the upstream redirects remain only as a fallback.

## Differences from `apps/maven-bridge`

- Health is also served on `/health` and `/healthcheck`; the CFML `describe` output is not served.
- Unknown (non-Maven) paths answer a plain text 404 instead of the Tomcat error page.
- When a provider or the upstream fails, the last good copy from KV is served instead of an error.
- Positive upstream `HEAD` checks are cached (Cache API); the CFML bridge checked on each request.
- Content types always come from the path's extension.
- Flushing requires `FLUSH_TOKEN`.
- Optional R2 serving and fill-on-miss (not in the CFML bridge).
- Checksums missing upstream are computed; the CFML bridge answered 404 (upstream groups) or
  redirected them to the `.lex` download (REST provider groups).
