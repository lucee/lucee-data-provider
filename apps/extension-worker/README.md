# Extension provider worker

Cloudflare Worker port of the extension provider of [`apps/updateserver`](../updateserver)
([`rest/ExtensionProvider.cfc`](../updateserver/rest/ExtensionProvider.cfc) and
[`services/ExtensionMetadataReader.cfc`](../updateserver/services/ExtensionMetadataReader.cfc)), the REST
service behind `extension.lucee.org` (LDEV-6902). It answers the same requests with the same answers, so
Lucee core and the Administrator can use it as an extension provider without any change.

It is **not deployed**: `wrangler.toml` has no routes and no `workers.dev` url yet, see [Deploying](#deploying).

## Endpoints

Lucee core resolves the provider paths from the root of the provider url (`new URL(providerUrl, "/rest/extension/provider/...")`).
Paths are matched ignoring case and a trailing slash, url parameter names ignoring case (like the url scope).
Every endpoint answers `GET` and `HEAD`, anything else `405`.

| Path | Parameters (url) | Answer |
|------|------------------|--------|
| `/rest/extension/provider/info` | `withLogo` (true), `type` (release), `coreVersion` | `200` JSON: `{"META":{...},"EXTENSIONS":{"COLUMNS":[...],"DATA":[[...]]}}` |
| `/rest/extension/provider/info/{id}` | `version`, `coreVersion`, `type` (release), `withLogo` (true) | `200` JSON struct of one version, `404` text `There is no extension at this provider with id [...]` |
| `/rest/extension/provider/full/{id}` | `version`, `coreVersion`, `type` (release) | `302` with `Location` of the `.lex`, `404` without a body |
| `/rest/extension/provider/trial/{id}` | as `full` | as `full` |
| `/rest/extension/provider/updateCache`, `/reset` | | rebuild the index, need `FLUSH_TOKEN` (see below) |
| `/rest/extension/provider/status` | | build time and counters of the index, needs `FLUSH_TOKEN` (worker only) |
| `/healthcheck` | | `OK` |
| `/extension/extension-provider.png` | | the image of the provider meta (static asset) |

Other parameters (Lucee core sends `ioid`) are ignored, as before.

### `info`

As `getInfo()` and `ExtensionMetadataReader.list()`:

- `META` has the same keys in the same order (`MODE`, `URL`, `IMAGE`, `TITLE`, `DESCRIPTION`), built from the
  `Host` header. On a host name starting with `beta.` the type is always `abc`.
- `EXTENSIONS` is the serialized query Lucee reads with `deserializeJSON( json, false )`: the columns of the
  extension meta plus `coreVersion`. One row per extension, the newest version that the core version can
  load (`coreVersion`, compared with the `minCoreVersion` like `VersionUtils::checkVersionGTE`) of the type
  (`release`: finals, `snapshot`, `abc`: alpha/beta/RC, anything else, e.g. `all`: every version), the type
  filter applied first (LDEV-6789). `older`, `olderName`, `olderDate` and `coreVersion` hold the other
  versions of that selection, newest first. Sorted by name (ignoring case), then version.
- `image` is the base64 logo, empty with `withLogo=false`.

### `info/{id}`, `full/{id}`, `trial/{id}`

As `getExtensionDetail()`: without a `version` (or `latest`) the newest version of `type` that fits
`coreVersion`; a version that is asked for is answered whatever its type, unless the core version can't load
it (`404`, LDEV-6795). The id and the version are matched ignoring case. `info/{id}` answers the struct of the
row (the meta columns, in their order, `trial` as a boolean). `full` and `trial` redirect to the download url,
in the order of `getDownloadUrl()` (LDEV-6795, Maven first):

1. the Maven layout of the core bucket (`S3_CORE_CDN_URL` + `S3_EXTENSIONS_MAVEN_PATH`, i.e.
   `https://cdn.lucee.org/org/lucee/<artifact>/<version>/<artifact>-<version>.lex`)
2. the first Maven repository that has the version (releases, snapshots, then the mixed Lucee repository);
   snapshots point to their timestamped file, read from the `maven-metadata.xml` of the version
3. the flat file (`S3_EXTENSIONS_CDN_URL` + file name), the fallback

A flat file of the meta gets the Maven location of the same id and version, also under another file name
(the older files have their old names in the flat bucket).

## How the data is read

The CFML provider reads the S3 buckets with credentials, downloads every extension file and reads its
manifest and logo. The worker reads over http only, no secrets:

| What | CFML provider | Worker |
|------|---------------|--------|
| extension meta | `<S3_EXTENSIONS_ROOT>/extensions.json`, kept up to date by itself | the same file over http, `EXTENSIONS_META_URL` (default `https://ext.lucee.org/extensions.json`) |
| what is known about the Maven files | `<S3_EXTENSIONS_ROOT>/extensions-maven.json` | the same file over http (`EXTENSIONS_MAVEN_STATE_URL`), plus what the worker learned (KV) |
| Maven layout of the core bucket | S3 directory listing | `maven-metadata.xml` of the group and of each artifact (the bucket can't be listed by prefix over http) |
| Maven repositories | html listings + `maven-metadata.xml` (`MavenExtensionSource.cfc`) | the same (`src/maven.ts`) |
| files the meta doesn't have yet | downloaded, `ManifestRead()`, logo as GIF | read with range requests: the zip central directory, then only `META-INF/MANIFEST.MF` and `META-INF/logo.png` (`src/lex.ts`), at most `EXTENSIONS_DISCOVERY_MAX` per build |
| packaging (LDEV-6795) | probed from the file | from the meta; probed for files without one, only with `EXTENSIONS_MAVEN_ONLY_MIN_CORE` |

The result, the **index**, is the meta without the logos, sorted like `_updateExtensionSorting()`
(versionSortable recomputed, id asc, version desc), plus the Maven location of every file. It is stored in
the KV namespace `EXT_CACHE` (`index`, `logos`, `state`), rebuilt by the cron trigger (every 10 minutes) and,
when a request finds it older than `INDEX_TTL_MINUTES`, in the background (one build at a time, KV lock).
Each isolate keeps the index in memory and looks at KV again after a minute; the logos are only read for
answers that have them (`withLogo`). Without the KV binding every isolate builds the index itself on its
first request. Upstream metadata is cached at the edge for `METADATA_CACHE_SECONDS`.

A list answer is computed from the index in memory (cached per isolate like the `_simpleCache` of the CFML
version), so requests don't wait for the network once the index is there. A build reads the meta (~15 MB with
the logos), ~200 small metadata files and the discovered extensions; it runs in the cron, not in requests.

## Configuration

`[vars]` in `wrangler.toml`, the same names as the environment variables of
[`Application.cfc`](../updateserver/Application.cfc):

| Variable | Default | |
|----------|---------|---|
| `S3_EXTENSIONS_CDN_URL` | `https://ext.lucee.org/` | flat extension files, the download fallback |
| `S3_CORE_CDN_URL` | `https://cdn.lucee.org/` | core bucket with the Maven layout |
| `S3_EXTENSIONS_MAVEN_PATH` | `org/lucee/` | path of the extensions in the core bucket, empty: none |
| `EXTENSIONS_MAVEN_REPOS_ENABLED` | `true` | `false`: no Maven repositories |
| `EXTENSIONS_MAVEN_REPOS_RELEASES` (`LUCEE_MVN_REPO_RELEASES`) | `https://repo1.maven.org/maven2/` | comma separated, `none` for none |
| `EXTENSIONS_MAVEN_REPOS_SNAPSHOTS` (`LUCEE_MVN_REPO_SNAPSHOTS`) | `https://central.sonatype.com/repository/maven-snapshots/` | |
| `EXTENSIONS_MAVEN_REPOS_MIXED` (`LUCEE_MVN_REPO_MIXED`) | `https://maven.lucee-services.com/` | |
| `EXTENSIONS_MAVEN_TIMEOUT` | `20` | seconds |
| `EXTENSIONS_FLAT_S3_FALLBACK` | `true` | `false`: only what is served from a Maven source (LDEV-6795) |
| `EXTENSIONS_MAVEN_ONLY_MIN_CORE` | | min core version of Maven packaged extensions (LDEV-6795) |
| `EXTENSIONS_META_URL` | `<S3_EXTENSIONS_CDN_URL>extensions.json` | worker only |
| `EXTENSIONS_MAVEN_STATE_URL` | `<S3_EXTENSIONS_CDN_URL>extensions-maven.json` | worker only |
| `EXTENSIONS_DISCOVERY_MAX` | `10` | extension files read per build (new files, packaging), `0` = off; worker only |
| `INDEX_TTL_MINUTES` | `15` | worker only |
| `METADATA_CACHE_SECONDS` | `300` | worker only |
| `FLUSH_TOKEN` | | **secret** (`wrangler secret put FLUSH_TOKEN`), worker only |

Not used by the worker: `S3_EXTENSION_ACCESS_KEY_ID`, `S3_EXTENSION_SECRET_KEY`, `S3_*_ROOT` (no S3 access),
`EXTENSIONS_MAVEN_THREADS` and `EXTENSIONS_MAVEN_FETCH_THREADS` (fixed to 6, the connection limit of a Worker),
`EXTENSIONS_PACKAGING_BACKFILL_MAX` (`EXTENSIONS_DISCOVERY_MAX` instead).

### Flush and the admin endpoints

In the CFML version anyone can call `?flush=true`, `/updateCache` and `/reset`, which reload the whole meta.
Here they need the `FLUSH_TOKEN` secret (header `x-flush-token: <token>` or `Authorization: Bearer <token>`)
and are disabled without it: `/updateCache`, `/reset` and `/status` answer `403`, `flush=true` without a valid
token is ignored (the cached index is answered, Lucee core never sends it). `/updateCache` answers
`{"META":{},"EXTENSIONS":<meta>}` like before, without the logos.

## Differences and gaps

Checked against the live provider with `scripts/compare.mjs` (every list variant, and details and downloads of
every extension in several ways, 454 requests): the answers are the same, except for the logos of the
extensions the worker discovered itself (see below).

- **The meta comes from the CFML provider.** The worker reads the `extensions.json` the CFML provider writes.
  New versions published to a Maven source are discovered by the worker too, but files that only go to the
  flat bucket are not (the bucket can't be listed over http), and the meta is not written back. Before the
  CFML provider is switched off, `extensions.json` should be frozen as it is (or written by the publishing
  workflows); after that the Maven sources are the only way new versions come in, which is the plan anyway
  (LDEV-6807).
- **Logos of discovered extensions are PNG**, the CFML version converts them to GIF (8 bit). Lucee renders
  both (`data:image/png;base64,...`), the PNG is larger.
- **No bundle registration.** The CFML provider registers the jars of every extension for the bundle
  downloads of the update provider (`BundleDownloadService`); that stays with the update provider.
- **Maven layout of the core bucket** is read from the `maven-metadata.xml` files, not a bucket listing: a
  version missing from the metadata is not seen there (it can still come from a Maven repository).
- **Files that are gone are not removed** from the meta (`_removeRedundantExtensions()`), that is left to the
  CFML provider's `extensions.json`.
- **A core version of less than 4 parts** in `info?coreVersion=` is treated like missing parts, the CFML
  version answers a serialized exception (with status 200).
- **Errors**: when the index can't be built at all the answer is `503`; an error in `info` is a `500` JSON
  `{"message":...}` instead of the serialized exception.
- An invalid boolean (`withLogo=maybe`) falls back to the default instead of a cast error.

## Development

```sh
npm ci
npm run typecheck
npm test                         # vitest in the Workers runtime, fetch is mocked
npm run dev                      # wrangler dev --local on http://localhost:8787, reads the real sources
node scripts/compare.mjs         # compare the local worker with https://extension.lucee.org (read-only)
node scripts/record-fixtures.mjs # record test/fixtures/compat.json from the live provider (read-only)
npm run dry-run                  # build without deploying
```

`npm run dev` needs no secrets; to try the admin endpoints locally pass one:
`npx wrangler dev --local --var FLUSH_TOKEN:localtoken`. The first request builds the index (~10-25 s).

Tests:

- `test/unit.test.ts`: version sorting and comparison (`VersionUtils.cfc`), release types, configuration,
  manifest parsing, packaging, reading a `.lex` with range requests.
- `test/worker.test.ts`: every endpoint against a small made-up world (meta, core bucket, three
  repositories, a discovered `.lex`): response shapes and headers, filters, redirects, 404s, flat fallback
  switched off, min core version for Maven packaged extensions, KV storage, cron, flush and admin endpoints.
- `test/compat.test.ts`: answers recorded from the live provider for five extensions (lists filtered to them,
  details, versions, downloads, 404s) compared byte for byte with what the worker answers from the sources
  recorded at the same time.

## Deploying

Not done yet. What it needs:

1. A KV namespace for `EXT_CACHE` (`wrangler kv namespace create lucee-extension-provider-cache`, put its id
   in `wrangler.toml`).
2. Optionally the `FLUSH_TOKEN` secret.
3. `wrangler deploy` with an API token of the Lucee Cloudflare account (Workers Scripts and KV edit).
   Workers Paid plan: a build parses ~15 MB of JSON and makes a few hundred subrequests, more than the Free
   plan allows.
4. A route: first a test host name (e.g. a custom domain `ext-provider.lucee-services.com`) to compare with
   `scripts/compare.mjs <test host>`, then `extension.lucee.org` (already proxied by Cloudflare) as a custom
   domain or a route `extension.lucee.org/rest/extension/provider/*`, which leaves the rest of the host on
   the current server.
5. A deploy workflow like the other workers once it should go live; this change only tests it in CI.
