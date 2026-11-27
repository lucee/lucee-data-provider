# artifacts.lucee.org

Public host for extension logos, and later other small artifacts. It is the Cloudflare R2 bucket `lucee-artifacts-public`, served at the custom domain `artifacts.lucee.org`. Core Lucee jar / light / `.lco` fallbacks stay on `cdn.lucee.org`.

## URL layout

One configurable base URL, `ARTIFACTS_URL`, default:

```
https://artifacts.lucee.org/
```

A logo is then at the domain root (no `artifacts/` or other prefix):

```
https://artifacts.lucee.org/{group}-{artifact}.png
```

Dots in the Maven group and artifact become dashes. There is no version in the path, so a logo change under the same coordinates keeps the same URL.

Examples:

| Coordinates | Public URL / R2 key |
|---|---|
| `org.lucee` / `ajax-extension` | `https://artifacts.lucee.org/org-lucee-ajax-extension.png` |
| `com.example.foo` / `bar.baz-extension` | `https://artifacts.lucee.org/com-example-foo-bar-baz-extension.png` |

R2 object keys are the file names at the bucket root, for example `org-lucee-ajax-extension.png`. A file in `/Users/mic/Downloads/artifacts/org-lucee-ajax-extension.png` is uploaded as that key, not under an `artifacts/` prefix.

To use a different host or path later, set `ARTIFACTS_URL` (a trailing slash is added when missing). The download page and the Maven update/extension provider both read this variable.

If a GitHub raw logo or a leftover `https://cdn.lucee.org/artifacts/…` URL is still in cached metadata, it is rewritten to the artifacts host at render time **only when that file exists** there. Otherwise the original URL is kept.

## Environment variable

| Name | Default | Used by |
|---|---|---|
| `ARTIFACTS_URL` | `https://artifacts.lucee.org/` | `apps/download8` (`Util.cfc`) and `apps/updateserver-maven` (`ExtensionMetadataReader`) |

## Cloudflare bucket

Already in place:

- Bucket: `lucee-artifacts-public`
- Custom domain: `artifacts.lucee.org` (active)
- Public development (r2.dev) URL: leave disabled
- CORS: not required for ordinary `<img src>` requests

Optional: a Cache Rule for `artifacts.lucee.org/*` with a one-day edge TTL. Do not mark the objects immutable — a logo can be replaced under the same name. After replacing a file, purge that URL if the old copy is still cached.

Check a file with:

```sh
curl -sSI https://artifacts.lucee.org/org-lucee-ajax-extension.png
```

You want `200`, `content-type: image/png`, and a `cache-control` header. A missing object currently returns `404`.

## Upload

From a local folder of PNGs (for example `~/Downloads/artifacts`):

```sh
./scripts/upload-extension-logos.sh /Users/mic/Downloads/artifacts lucee-artifacts-public
```

The script uses `npx wrangler r2 object put … --remote` with `Content-Type: image/png` and `Cache-Control: public, max-age=86400`, and writes each file to the bucket root under its existing name. It can also print an equivalent `rclone` command.

## Files currently on cdn.lucee.org/artifacts

The CDN prefix does not list its objects (the `/artifacts/` URL returns an empty S3 directory). The live download page at https://download.lucee.org/ currently uses these **34** files from `https://cdn.lucee.org/artifacts/`. Upload them to the matching root keys on `artifacts.lucee.org`:

```
org-lucee-administrator-extension.png
org-lucee-ajax-extension.png
org-lucee-argon2-extension.png
org-lucee-axis-extension.png
org-lucee-chart-extension.png
org-lucee-couchbase-extension.png
org-lucee-documentation-extension.png
org-lucee-duckdb-jdbc-extension.png
org-lucee-dynamodb-extension.png
org-lucee-ec2-extension.png
org-lucee-exasol-jdbc-extension.png
org-lucee-form-extension.png
org-lucee-ftp-extension.png
org-lucee-git-extension.png
org-lucee-h2-jdbc-extension.png
org-lucee-json-extension.png
org-lucee-jtds-jdbc-extension.png
org-lucee-kinesis-extension.png
org-lucee-mail-extension.png
org-lucee-markdown-extension.png
org-lucee-memcached-extension.png
org-lucee-mongodb-extension.png
org-lucee-mssql-jdbc-extension.png
org-lucee-mysql-jdbc-extension.png
org-lucee-oracle-jdbc-extension.png
org-lucee-poi-extension.png
org-lucee-postgresql-jdbc-extension.png
org-lucee-quartz-extension.png
org-lucee-redshift-jdbc-extension.png
org-lucee-scheduler-classic-extension.png
org-lucee-sentry-extension.png
org-lucee-smb-extension.png
org-lucee-tasks-extension.png
org-lucee-yaml-extension.png
```

The same download page also serves other extension logos from its own `/logo-*.png` cache (taken from the `.lex`) and one GitHub raw URL (`extension-osgi`). Those are not on the CDN today. If you have PNGs for them, upload them under the same `{group}-{artifact}.png` names (for example `org-lucee-redis-extension.png`, `org-lucee-s3-extension.png`, `org-lucee-osgi-extension.png`) and the existence check will start using them automatically.
