# Skill worker

Cloudflare Worker port of [`apps/skill`](../skill), the site that serves the Lucee skill file for AI
assistants. It serves the same paths with the same answers, without a container and without Cloud Run.

It serves:

| Hostname | Role |
|----------|------|
| `skill.lucee-services.com` | production custom domain on this worker |
| `skl.lucee-services.com` | test custom domain on this worker |
| `skill.lucee.io` | production; Cloudflare for SaaS custom hostname on the `lucee-services.com` zone, with the Worker route `skill.lucee.io/*`. In Route 53 it is a CNAME to `skill.lucee-services.com` |
| `skills.lucee.io` | same as `skill.lucee.io`, with the Worker route `skills.lucee.io/*` |

The old Cloud Run service is left running until it is retired; it is no longer deployed to.

## What it does

| Path | Answer |
|------|--------|
| `/`, `/index.cfm` | landing page: one card per skill (name, description, size, last update) and a table of the topic indexes from `skills.json` (title, id, description, entries, size, approximate tokens), same HTML as `index.cfm` |
| `/<file>.skill` | the skill file (`text/plain; charset=utf-8`), only for files listed in `SKILLS` (name matched case-insensitively, like the Cloud Run site). `/main.skill` is the router of the Lucee skill (`https://docs.lucee.org/lucee.skill`), so existing installs keep working |
| `/skills.json` | the mirrored manifest (`application/json; charset=utf-8`) |
| `/skill/<id>.md` | a topic index listed in `skills.json` (`text/markdown; charset=utf-8`); ids not in the manifest answer `404` |
| `/health`, `/health.cfm` | `ok`, or `503 <file> not available` when a skill cannot be loaded |
| `/res/*` | static assets (`public/res`, kept in sync with `apps/skill/www/res`, including the shared `lucee-header`) |
| anything else | `404 Not Found`; methods other than `GET`/`HEAD` answer `405` |

The landing page HTML in `src/landing.ts` and the assets under `public/res` are a port of `apps/skill/www`. When the header or CSS in `apps/skill/www` changes, copy `apps/skill/www/res` into `public/res` again and update `renderLanding` to match `index.cfm`.

### Mirroring

The skill files are mirrored from their source (`https://docs.lucee.org/lucee.skill`) into the KV
namespace `SKILL_CACHE` (key `skill:<file>`: body, ETag, source ETag, Last-Modified, fetch time).

Since LDEV-6552 the Lucee skill is a short router plus one index file per topic. The manifest
`https://docs.lucee.org/skill/skills.json` lists them, and it drives the mirror: every topic it lists is
mirrored as `skill:skill/<id>.md` and served as `/skill/<id>.md`, so a new topic needs no change here.

- Each topic file, and the router when it is the manifest's `router.url`, is checked against the
  `sha256` in the manifest. A file that does not match is not stored (the last good copy stays). A copy
  that no longer matches the manifest is fetched in full, not with a conditional GET.
- The manifest is only stored when it is valid JSON with valid topic ids, and every topic URL is on the
  manifest's own origin. Otherwise the last good copy keeps driving the mirror.
- The landing page uses the mirrored manifest. A router or topic copy that does not match it (or is
  missing) is refreshed in the background right away, so the page does not show an outdated size until
  the next cron run.

- An hourly cron (`0 * * * *`) refreshes `skills.json` first, then checks every source with a conditional GET
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
| `SKILLS` | `main.skill` | comma separated files served as `/<file>`. `file\|url` sets the source; other files are resolved relative to `SKILL_SOURCE_URL` (`extensions.skill` → `https://docs.lucee.org/extensions.skill`). The topic files of the router come from `SKILL_MANIFEST_URL`, not from here |
| `SKILL_MANIFEST_URL` | `https://docs.lucee.org/skill/skills.json` | manifest of the topic files (LDEV-6552); empty disables `/skills.json` and `/skill/*` |
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
   and `skl.lucee-services.com`. `skill.lucee.io` and `skills.lucee.io` are not in `wrangler.toml`; they
   are Cloudflare for SaaS custom hostnames plus Worker routes, as in the table above.

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

## Hostnames and the old Cloud Run service

The cutover is done. `skill.lucee-services.com`, `skill.lucee.io` and `skills.lucee.io` are served by
this worker. Do not deploy [`apps/skill`](../skill) to Google Cloud Run any more; that service stays
as it is until it is deleted by hand.

`skill.lucee.io` and `skills.lucee.io` must keep their Cloudflare for SaaS records in Route 53
(`_acme-challenge.*` CNAME and `_cf-custom-hostname.*` TXT) and the matching custom hostnames and
Worker routes on the `lucee-services.com` zone, or the certificates will not renew.
