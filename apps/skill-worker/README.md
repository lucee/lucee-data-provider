# Skill worker

Cloudflare Worker port of [`apps/skill`](../skill), the site behind `skill.lucee-services.com` that
serves the Lucee skill file for AI assistants. It serves the same paths with the same answers,
without a container and without Cloud Run.

It serves **`skill.lucee-services.com`** and the test hostname **`skl.lucee-services.com`**. The Cloud
Run service stays deployed as a rollback until it is retired. `skill.lucee.io` is not touched by this worker.

## What it does

| Path | Answer |
|------|--------|
| `/`, `/index.cfm` | landing page: one card per skill (name, description, size, last update), same HTML as `index.cfm` |
| `/<file>.skill` | the skill file (`text/plain; charset=utf-8`), only for files listed in `SKILLS` (name matched case-insensitively, like the Cloud Run site) |
| `/health`, `/health.cfm` | `ok`, or `503 <file> not available` when a skill cannot be loaded |
| `/res/*` | static assets (`public/res`, copied from `apps/skill/www/res`) |
| anything else | `404 Not Found`; methods other than `GET`/`HEAD` answer `405` |

### Mirroring

The skill files are mirrored from their source (`https://docs.lucee.org/lucee.skill`) into the KV
namespace `SKILL_CACHE` (key `skill:<file>`: body, ETag, source ETag, Last-Modified, fetch time).

- An hourly cron (`0 * * * *`) checks every source with a conditional GET
  (`If-None-Match` / `If-Modified-Since`). `304` only updates the fetch time; `200` with a non-empty
  body replaces the copy.
- When the source fails, the last good copy is kept and served. The cron run is marked as failed
  (it throws), so the failure shows up in the worker logs.
- When KV has no copy yet (first deploy, new entry in `SKILLS`), the file is fetched on the first
  request. If the source fails then, the skill answers `503`.
- A copy older than `REFRESH_MINUTES` is also refreshed in the background (`waitUntil`) when it is
  requested, in case a cron run was missed (at most one such refresh per file and isolate at a time).

### Skill file responses

- `ETag` (SHA-256 of the body), `Last-Modified` (from the source, or the time the body last changed
  when the source sends none), `cache-control: public, max-age=600`.
- `If-None-Match` (or `If-Modified-Since` without `If-None-Match`) answers `304`.
- `HEAD` answers the headers and the `content-length` of the body without the body.

The landing page is `cache-control: public, max-age=300`; the health check is `no-store`.

## Configuration

`wrangler.toml` `[vars]`:

| Var | Default | Meaning |
|-----|---------|---------|
| `SKILL_SOURCE_URL` | `https://docs.lucee.org/lucee.skill` | source of the first skill file |
| `SKILLS` | `main.skill` | comma separated files served as `/<file>`. `file\|url` sets the source; other files are resolved relative to `SKILL_SOURCE_URL` (`extensions.skill` → `https://docs.lucee.org/extensions.skill`), which is ready for more skill files (LDEV-6552) |
| `REFRESH_MINUTES` | `60` | age after which a requested copy is refreshed in the background |
| `TIMEOUT` | `60` | timeout in seconds for requests to the source |

File names must match `[A-Za-z0-9][A-Za-z0-9._-]*\.skill`.

## Develop and test

Node 22.

```sh
cd apps/skill-worker
npm ci
npm run typecheck
npm test                                  # vitest in the Workers runtime, no network
npx wrangler deploy --dry-run --outdir dist
npx wrangler dev                          # local, with a local KV
```

## Deploy

`.github/workflows/skill-worker.yml` runs typecheck, tests and a dry-run build on every pull request
and push that touches the worker. Pushes to `main` (and manual runs on `main`) also deploy:

1. `scripts/provision.mjs` creates the KV namespace `lucee-skill-cache` if it does not exist yet and
   writes its id into `wrangler.toml` (in CI only, nothing is committed).
2. `wrangler deploy` deploys the worker `lucee-skill` with the custom domains `skill.lucee-services.com`
   and `skl.lucee-services.com`.

It uses the organization secrets `CLOUDFLARE_API_TOKEN` (Workers Scripts, Workers KV Storage and
Workers Routes edit, DNS edit for the zone) and `CLOUDFLARE_ACCOUNT_ID`; they are only passed to the
provisioning and deploy steps.

## Compare with the current site

`scripts/compare.mjs` requests each path on both hosts and compares status, content type and a
hash of the body. HTML is normalized first (whitespace, character references, the host in the skill
link and the "Updated" date); error pages are compared by status only.

```sh
npm run compare                                   # skill.lucee-services.com vs skl.lucee-services.com
npm run compare -- --target http://127.0.0.1:8787 --verbose   # against `wrangler dev`
npm run compare -- --paths my-paths.txt --strict
```

## Differences to apps/skill

- The skill file is served with `ETag`, `Last-Modified` and `cache-control`, and `HEAD` and
  conditional requests are handled.
- "Updated" on the landing page is the source's `Last-Modified` (the Cloud Run site used the
  modification time of the downloaded file, i.e. its last download).
- The skill card's "Refreshed hourly from …" names the host of the skill's source.
- A skill that was never mirrored is fetched on the first request instead of waiting for the next
  refresh.
- Methods other than `GET` and `HEAD` answer `405` (Cloud Run answered them like `GET`).
- `/health` is new (Cloud Run only has `/health.cfm`); both answer `text/plain` instead of `text/html`.
- Error pages are a plain `Not Found` (`text/plain`) instead of the Tomcat HTML page.
- The landing page HTML-encodes fewer characters (e.g. `:`, `/`, `(`, `—` stay as they are); the
  rendered page is the same.

## Cutover

1. Merge; the workflow deploys to `skl.lucee-services.com`.
2. Compare both hosts (above) and watch the cron runs in the worker logs for a few hours.
3. Add `skill.lucee-services.com` as a second custom domain in `wrangler.toml`
   (`routes = [{ pattern = "skl.lucee-services.com", custom_domain = true }, { pattern = "skill.lucee-services.com", custom_domain = true }]`).
   Cloudflare creates the DNS record of each custom domain. A deploy from CI (non-interactive) replaces an
   existing DNS record on that hostname; an interactive `wrangler deploy` asks first.
4. Once traffic has moved, retire the Cloud Run service and `apps/skill`.

Rollback for `skill.lucee-services.com`: remove it from `routes` and deploy (this removes the custom domain
and its record), then restore the DNS-only CNAME `skill` → `ghs.googlehosted.com` (Cloud Run).
