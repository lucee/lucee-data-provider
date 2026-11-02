# lucee.org website (static)

Static source of the lucee.org website. Plain HTML/CSS/JS, no framework, no runtime. It is deployed to Cloudflare Pages and is independent of the other apps in this repository.

- `content/*.html` + `build.py`: page sources and the optional generator. `python3 build.py` (Python 3, no dependencies) regenerates the pages and `sitemap.xml`. The generated files are committed, so the folder can also be served as is, without a build step.
- `releases.json`: data for the release table on `/releases.html`, see "Release info" below.
- `shared/header.js` + `shared/header.css` + `shared/lucee-logo.svg`: the `<lucee-header>` web component, meant to be included by other Lucee sites from one URL.
- `assets/site.css`: page styles (design tokens shared with download.lucee.org / skill.lucee.io).
- `_headers`, `_redirects`: Cloudflare Pages configuration. `robots.txt`, `sitemap.xml`, `.well-known/security.txt`.

All internal links and assets are root-relative (`/shared/header.js`, `/assets/site.css`), so the site works on any host name at the root of the host, including `*.pages.dev`. Canonical and Open Graph URLs point to `https://lucee.org` on purpose.

## Local preview

```
cd apps/website
python3 build.py              # optional, only after editing content/ or releases.json
python3 -m http.server 8000   # open http://localhost:8000/
```

## Deploy on Cloudflare Pages

Create a Pages project: Workers & Pages, Create, Pages, Connect to Git, select `lucee/lucee-data-provider`.

| Setting | Value |
|---|---|
| Production branch | `main` |
| Framework preset | None |
| Root directory | `apps/website` |
| Build command | leave empty (or `python3 build.py`, which only regenerates the committed files) |
| Build output directory | `/` (the root directory itself) |

Before a custom domain is linked, the site is reachable at `https://<project-name>.pages.dev`. Every other branch and pull request gets its own preview at `https://<branch>.<project-name>.pages.dev` (and a per-commit URL). `_headers` sets `X-Robots-Tag: noindex` on these `pages.dev` hosts so they stay out of search engines. The header does not apply to the custom domain.

Because the project only needs the files in this folder, a change elsewhere in the repository also triggers a Pages build. This can be limited under Settings, Build, Build watch paths (include `apps/website/*`).

### Linking lucee.org

When the domain goes live: Pages project, Custom domains, Set up a custom domain, enter `lucee.org` (and `www.lucee.org` if wanted), and follow the DNS instructions. If the zone is on Cloudflare, the DNS record is created automatically. Once active, optionally fill `_redirects` with the old `www.lucee.org` URLs that should keep working (examples are in the file).

Include the header on another site:

```html
<script src="https://lucee.org/shared/header.js" defer></script>
<lucee-header home="https://lucee.org/" current="download"></lucee-header>
```

## Theme (light / dark)

Default follows the system (`prefers-color-scheme`). `<lucee-header>` has a system / light / dark switch on its right side.
The choice is stored in `localStorage` (`lucee-theme`) and applied as `<html data-theme="light|dark">` (no attribute = system).
`shared/theme.css` (loaded automatically by header.js) maps that attribute to the shared tokens
(`--bg --bright --text --muted --lines --lines-bright --shadow*`), so sibling sites that use those token names follow the switch.
Note: localStorage is per origin, so each site remembers the choice separately.

## Member logos

`assets/members/*.png` are the logo files from the lucee.org members page (transparent margins trimmed; doTERRA downscaled). DistroKid is the official vector SVG from https://distrokid.com/logo/ (black wordmark, transparent background). They are shown monochrome via CSS (`.logo-grid` in `assets/site.css`). To add a member, add an `<li>` in `content/members.html` and a file in `assets/members/`. If there is no logo, use a visible TODO placeholder with the name rather than drawing one.

## Release info

`releases.json` (in this folder) is the single data file for release info: one entry per version line with `status` (`alpha`, `latest`, `lts`, `security`, `eol`, plus neutral `older`), `released`, `activeSupportUntil`, `endOfLife` and a short note. `build.py` renders it at build time into the "Supported versions" table and the history timeline on `/releases.html`. No client-side JS.

- A `null` date renders as a visible `TODO` chip. Never add a date without a source (`released` = first final release on Maven Central).
- To change a status or add a line, edit `releases.json` and run `python3 build.py`.
- Exact version numbers are not shown on this site. Take them from https://download.lucee.org/.
