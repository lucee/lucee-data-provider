#!/usr/bin/env python3
"""Optional tiny build: wraps content/*.html fragments in the shared page shell.

The generated *.html files are committed, so deploying needs no build step.
Fragment format: "key: value" header lines, a line with ---, then the <main> body.
Keys: title, description, path (output file), nav (header highlight), robots (optional)
"""
import pathlib, re, html, json, datetime

ROOT = pathlib.Path(__file__).parent
SITE = "https://lucee.org"          # TODO: confirm production origin
NAV = [("Download", "https://download.lucee.org/"), ("Docs", "https://docs.lucee.org/"),
       ("Extensions", "/extensions"), ("Community", "/community"),
       ("AI", "/ai"), ("Support", "/support")]

# ---- Lucee 8.0 launch notice (homepage, one plain line above "Get started") ----
# Hidden by default: while LAUNCH_NOTICE is False nothing is rendered. To switch it on:
#   1. fill in LAUNCH_HIGHLIGHTS and LAUNCH_CHANGELOG_URL below (the build refuses to run with TODOs left)
#   2. set LAUNCH_NOTICE = True
#   3. run `python3 build.py` and commit the regenerated index.html
LAUNCH_NOTICE = False
LAUNCH_HIGHLIGHTS = "TODO highlights"   # plain text, e.g. a short comma-separated list
LAUNCH_CHANGELOG_URL = "TODO https://download.lucee.org/changelog.cfm?version=<8.0 version>"

def launch_notice():
    if not LAUNCH_NOTICE:
        return ""
    if "TODO" in LAUNCH_HIGHLIGHTS or "TODO" in LAUNCH_CHANGELOG_URL:
        raise SystemExit("build.py: LAUNCH_NOTICE is on but LAUNCH_HIGHLIGHTS / LAUNCH_CHANGELOG_URL still contain TODO")
    return ('<p class="launch-note"><strong>Lucee 8.0 is here:</strong> '
            f'{html.escape(LAUNCH_HIGHLIGHTS)}. '
            f'<a href="{html.escape(LAUNCH_CHANGELOG_URL, quote=True)}">Read what\'s new</a></p>\n')


FOOTER = """<footer class="site-footer">
  <div class="inner">
    <nav aria-label="Footer"><ul>
      <li><a href="/about.html">About</a></li>
      <li><a href="/members.html">Members</a></li>
      <li><a href="/releases.html">Releases</a></li>
      <li><a href="https://github.com/lucee/Lucee/blob/7.1/License.txt">License (LGPL&nbsp;2.1)</a></li>
      <li><a href="/security.html">Security</a></li>
      <li><a href="https://github.com/lucee/Lucee">GitHub</a></li>
    </ul></nav>
    <p>Contact: <a href="mailto:hello@lucee.org">hello@lucee.org</a></p>
    <p class="legal">Lucee is an open source project led by the Lucee Association Switzerland.</p>
  </div>
</footer>"""

# ---- release data (releases.json -> HTML at build time, no client-side JS) ----
STATUS = {"alpha": "Alpha", "latest": "Latest", "lts": "LTS", "security": "Security fixes only",
          "eol": "End of life", "older": "Older"}

def _line_name(l):
    return l["line"]

def _date(v, row, what):
    """ISO date -> <time>; unsupported rows -> n/a; not-yet-announced -> TBA*; unknown -> visible TODO."""
    if v:
        d = datetime.date.fromisoformat(v)
        return f'<time datetime="{v}">{d.strftime("%b %Y")}</time>'
    if row.get("unsupported"):
        return '<span class="muted">n/a</span>'
    if row.get("notApplicable"):
        return '<span class="muted">TBA*</span>'
    return f'<span class="todo">TODO {what}</span>'

def _released(row):
    if row.get("released"):
        return _date(row["released"], row, "date")
    if row.get("releasedText"):
        return f'<span class="muted">{html.escape(row["releasedText"])}</span>'
    return _date(None, row, "date")

def _badge(row):
    st = row["status"]
    extra = ' <span class="todo">TODO confirm status</span>' if st == "older" else ""
    return f'<span class="badge st-{st}">{STATUS[st]}</span>{extra}'

def load_releases():
    return json.loads((ROOT / "releases.json").read_text())

def releases_table(data):
    rows = []
    for r in data["lines"]:
        name = html.escape(_line_name(r))
        rows.append(
            f'<tr><th scope="row" data-label="Version">{name}</th>'
            f'<td data-label="Status">{_badge(r)}</td>'
            f'<td data-label="Released">{_released(r)}</td>'
            f'<td data-label="Active support until">{_date(r.get("activeSupportUntil"), r, "date")}</td>'
            f'<td data-label="End of life">{_date(r.get("endOfLife"), r, "date")}</td></tr>')
    return ('<div class="table-wrap"><table class="rel-table">'
            '<thead><tr><th>Version</th><th>Status</th><th>Released</th><th>Active support until</th><th>End of life</th></tr></thead>'
            '<tbody>' + "".join(rows) + '</tbody></table></div>')

def releases_timeline(data):
    older = [r for r in data["lines"] if r["status"] in ("eol", "older", "security") and not r.get("unsupported")]
    older.sort(key=lambda r: r.get("released") or "")
    items = []
    for r in older:
        d = _date(r.get("released"), r, "date")
        items.append(f'<li><div class="tl-head"><strong>Lucee {html.escape(r["line"])}</strong> {_badge(r)} <span class="tl-date">{d}</span></div>'
                     f'<p>{html.escape(r["history"])}</p></li>')
    tail = [r for r in data["lines"] if r.get("unsupported")]
    for r in tail:
        items.append(f'<li><div class="tl-head"><strong>Lucee {html.escape(r["line"])}</strong> {_badge(r)}</div><p>{html.escape(r["history"])}</p></li>')
    return '<ol class="timeline">' + "".join(items) + '</ol>'

def release_strip(data):
    by = {r["status"]: r for r in data["lines"]}
    parts = []
    for st, label in (("latest", "Latest"), ("lts", "LTS")):
        if st in by:
            parts.append(f'<span class="rs-item"><span class="rs-label">{label}</span> <strong>{html.escape(by[st]["line"])}</strong></span>')
    inner = ' <span class="rs-sep" aria-hidden="true">&middot;</span> '.join(parts)
    return ('<div class="release-strip"><div class="container">'
            f'<a href="https://download.lucee.org/" aria-label="Lucee versions: see downloads">{inner}'
            '<span class="rs-more">Downloads and release notes &rarr;</span></a></div></div>')

def releases_sources(data):
    return " &middot; ".join(f'<a href="{html.escape(s["url"])}">{html.escape(s["label"])}</a>' for s in data["sources"])

def inject(body, data):
    return (body.replace("{{LAUNCH_NOTICE}}\n", launch_notice())
                .replace("{{RELEASES_TABLE}}", releases_table(data))
                .replace("{{RELEASES_TIMELINE}}", releases_timeline(data))
                .replace("{{RELEASES_SOURCES}}", releases_sources(data))
                .replace("{{RELEASE_STRIP}}", release_strip(data)))

def page(meta, body):
    nav = meta.get("nav", "")
    fallback = "".join(f'<a href="{h}">{html.escape(l)}</a>' for l, h in NAV)
    title = meta["title"]
    full_title = "Lucee — the CFML engine for the JVM" if meta["path"] == "index.html" else f"{title} · Lucee"
    canon = SITE + ("/" if meta["path"] == "index.html" else "/" + meta["path"])
    robots = f'\n<meta name="robots" content="{meta["robots"]}">' if meta.get("robots") else ""
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(full_title)}</title>
<meta name="description" content="{html.escape(meta['description'], quote=True)}">{robots}
<link rel="canonical" href="{canon}">
<link rel="icon" type="image/png" href="/favicon.png">
<meta property="og:title" content="{html.escape(full_title, quote=True)}">
<meta property="og:description" content="{html.escape(meta['description'], quote=True)}">
<meta property="og:type" content="website">
<meta property="og:url" content="{canon}">
<meta name="theme-color" content="#373b45">
<link rel="stylesheet" href="/shared/theme.css?v=2">
<link rel="stylesheet" href="/assets/site.css?v=2">
<script src="/shared/header.js?v=2" defer></script>
</head>
<body>
<a class="skip-link" href="#main">Skip to content</a>
<lucee-header home="/" current="{nav}">
  <a href="/" aria-label="Lucee home">Lucee</a>{fallback}
</lucee-header>
<main id="main">
{body}
</main>
{FOOTER}
</body>
</html>
"""

def main():
    paths = []
    data = load_releases()
    for f in sorted((ROOT / "content").glob("*.html")):
        head, body = f.read_text().split("\n---\n", 1)
        meta = dict(re.match(r"(\w+):\s*(.*)", l).groups() for l in head.strip().splitlines())
        (ROOT / meta["path"]).write_text(page(meta, inject(body.strip(), data)))
        paths.append(meta)
        print("built", meta["path"])
    # sitemap (noindex pages excluded)
    urls = [m["path"] for m in paths if not m.get("robots")]
    urls.sort(key=lambda p: (p != "index.html", p))
    loc = lambda p: SITE + ("/" if p == "index.html" else "/" + p)
    (ROOT / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        + "".join(f"  <url><loc>{loc(p)}</loc></url>\n" for p in urls) + "</urlset>\n")

if __name__ == "__main__":
    main()
