#!/usr/bin/env python3
"""Generate the Sorty website changelog page from CHANGELOG.md.

The changelog page (website/changelog/index.html) is the public, rendered
release history. This script parses the Keep-a-Changelog formatted
``CHANGELOG.md`` — the single source of truth, updated on every release by
``scripts/update_changelog.sh`` — and regenerates the page so the website never
drifts from what actually shipped.

Usage:
    scripts/build_changelog.py            # writes website/changelog/index.html
    scripts/build_changelog.py --check   # exits non-zero if a rebuild is needed

Run it locally before committing a release, or wire it into the release flow
after ``update_changelog.sh`` so the published changelog always matches the
release notes.
"""

from __future__ import annotations

import argparse
import html
import re
import sys
from datetime import date
from pathlib import Path

REPO = "sorty-organizer/Sorty"
ROOT = Path(__file__).resolve().parent.parent
CHANGELOG = ROOT / "CHANGELOG.md"
OUT = ROOT / "website" / "changelog" / "index.html"

# Keep-a-Changelog section -> CSS group class
GROUPS = {
    "added": "added",
    "changed": "changed",
    "fixed": "fixed",
    "removed": "removed",
    "deprecated": "changed",
    "security": "fixed",
    "features": "added",
}
MONTHS = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
]


def esc(text: str) -> str:
    return html.escape(text, quote=False)


def fmt_date(iso: str) -> str:
    try:
        y, m, d = (int(x) for x in iso.split("-"))
        return f"{MONTHS[m - 1]} {d}, {y}"
    except (ValueError, IndexError):
        return iso


def slugify(version: str) -> str:
    return "unreleased" if version.lower() == "unreleased" else "v" + version


def parse_changelog(text: str) -> list[dict]:
    """Parse Keep-a-Changelog markdown into a list of release dicts."""
    releases: list[dict] = []
    cur: dict | None = None
    cur_group: str | None = None

    header_re = re.compile(r"^##\s*\[([^\]]+)\](?:\s*-\s*(\d{4}-\d{2}-\d{2}))?\s*(.*)$")
    group_re = re.compile(r"^###\s+(.+?)\s*$")
    bullet_re = re.compile(r"^\s*-\s+(.*)$")

    def push_release() -> None:
        nonlocal cur
        if cur is not None:
            releases.append(cur)
        cur = None

    for raw in text.splitlines():
        line = raw.rstrip()

        m = header_re.match(line)
        if m:
            push_release()
            version, datestr, _tail = m.groups()
            cur = {
                "version": version,
                "date": datestr,
                "groups": [],          # list of {kind, label, items: [{name, desc}]}
                "highlights": [],       # list of (bold_inline_html)
                "paragraphs": [],
            }
            cur_group = None
            continue

        if cur is None:
            continue

        gm = group_re.match(line)
        if gm:
            label = gm.group(1).strip()
            key = label.lower()
            if key == "highlights":
                cur_group = "__highlights__"
            elif key == "requirements":
                cur_group = "__requirements__"
            else:
                cur_group = GROUPS.get(key, "changed")
                cur["groups"].append({"kind": cur_group, "label": label, "items": []})
            continue

        bm = bullet_re.match(line)
        if bm and cur_group and cur_group not in ("__highlights__", "__requirements__"):
            body = bm.group(1).strip()
            name, desc = split_name_desc(body)
            cur["groups"][-1]["items"].append({"name": name, "desc": desc})
            continue

        if bm and cur_group == "__highlights__":
            cur["highlights"].append(render_inline(bm.group(1).strip()))
            continue

        if line.strip() == "":
            continue

        # Non-bullet prose (e.g. highlights paragraph or notes)
        if cur_group == "__highlights__":
            cur["highlights"].append(render_inline(line.strip()))
        else:
            cur["paragraphs"].append(render_inline(line.strip()))

    push_release()
    return releases


def split_name_desc(body: str) -> tuple[str, str]:
    """Split '- **Name** — desc' into (name, desc). Falls back to ('', body)."""
    m = re.match(r"^\*\*(.+?)\*\*\s*[—–-]\s*(.*)$", body)
    if m:
        return m.group(1).strip(), m.group(2).strip()
    m = re.match(r"^\*\*(.+?)\*\*\s*$", body)
    if m:
        return m.group(1).strip(), ""
    return "", body


def render_inline(text: str) -> str:
    """Render a subset of inline markdown: **bold**, `code`, *italic*."""
    out = esc(text)
    out = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"`([^`]+)`", r'<code>\1</code>', out)
    out = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<em>\1</em>", out)
    return out


def render_release(release: dict, prev_tag: str | None) -> str:
    version = release["version"]
    unreleased = version.lower() == "unreleased"
    sid = slugify(version)
    classes = "release unreleased" if unreleased else "release"
    head_title = "Unreleased" if unreleased else f"Sorty {version}"
    tag_label = "next" if unreleased else f"v{version}"
    date_label = "In development" if unreleased else (fmt_date(release["date"]) if release["date"] else "")

    parts: list[str] = []
    parts.append(f'    <article class="{classes}" id="{sid}">')
    parts.append('      <div class="release-head">')
    parts.append(f"        <h2>{esc(head_title)}</h2>")
    parts.append(f'        <span class="tag">{esc(tag_label)}</span>')
    if date_label:
        parts.append(f'        <span class="date">{esc(date_label)}</span>')
    parts.append("      </div>")

    # Lead: highlights box, or a maintenance note for empty releases.
    if release["highlights"]:
        parts.append('      <div class="highlights">' + " ".join(release["highlights"]) + "</div>")
    elif not release["groups"] and not release["paragraphs"]:
        parts.append(
            '      <p class="lead">A maintenance release. '
            '<span class="muted">See the repository history for the detailed diff.</span></p>'
        )

    for para in release["paragraphs"]:
        parts.append(f'      <p class="lead">{para}</p>')

    for group in release["groups"]:
        kind = group["kind"]
        label = group["label"]
        items = group["items"]
        count = len(items)
        parts.append(f'      <div class="chg-group {kind}">')
        parts.append(
            f'        <h3>{esc(label)} <span class="pill">{count}</span></h3>'
        )
        parts.append('        <div class="chg-list">')
        for item in items:
            name = render_inline(item["name"]) if item["name"] else ""
            desc = render_inline(item["desc"])
            if name and desc:
                parts.append(
                    f'          <div class="chg-item"><span class="name">{name}</span>'
                    f'<span class="desc">— {desc}</span></div>'
                )
            elif name:
                parts.append(
                    f'          <div class="chg-item"><span class="name">{name}</span></div>'
                )
            else:
                parts.append(
                    f'          <div class="chg-item"><span class="desc">{desc}</span></div>'
                )
        parts.append("        </div>")
        parts.append("      </div>")

    if prev_tag and not unreleased:
        cur_tag = f"v{version}"
        parts.append(
            '      <p class="compare">Full diff: '
            f'<a href="https://github.com/{REPO}/compare/{prev_tag}...{cur_tag}" '
            f'target="_blank" rel="noopener">{prev_tag} → {cur_tag}</a></p>'
        )

    parts.append("    </article>")
    return "\n".join(parts)


NAV_TPL = """\
      <a href="#{sid}">{label}</a>"""


def build_nav(releases: list[dict]) -> str:
    items = []
    for r in releases:
        sid = slugify(r["version"])
        label = "Unreleased" if r["version"].lower() == "unreleased" else r["version"]
        items.append(NAV_TPL.format(sid=sid, label=esc(label)))
    return '    <nav class="release-nav" aria-label="Releases">\n' + "\n".join(items) + "\n    </nav>"


def build_page(releases: list[dict]) -> str:
    nav_html = build_nav(releases)
    # Compare link points from the next-older version to this one (older → newer).
    # releases is newest-first, so the older tag for index i is at i+1.
    older_tag_for: dict[int, str | None] = {}
    for idx, r in enumerate(releases):
        if r["version"].lower() == "unreleased":
            older_tag_for[idx] = None
            continue
        older_tag_for[idx] = None
        # find the next released release after this one (older)
        for j in range(idx + 1, len(releases)):
            if releases[j]["version"].lower() != "unreleased":
                older_tag_for[idx] = f"v{releases[j]['version']}"
                break

    body_parts = []
    for idx, r in enumerate(releases):
        older = older_tag_for[idx]
        body_parts.append(render_release(r, older))

    latest = next((r for r in releases if r["version"].lower() != "unreleased"), None)
    latest_version = latest["version"] if latest else ""

    return PAGE_TPL.format(
        nav=nav_html,
        body="\n".join(body_parts),
        latest_version=esc(latest_version),
    )


PAGE_TPL = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Changelog — Sorty</title>
<meta name="description" content="The full Sorty release history. Every version, every change — added, changed, fixed, and removed — with highlights for each release.">
<link rel="canonical" href="https://sorty-organizer.github.io/Sorty/changelog/">
<link rel="icon" href="/assets/img/favicon.png" type="image/png">
<link rel="apple-touch-icon" href="/assets/img/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">
<meta name="theme-color" content="#08080a">
<meta property="og:type" content="article">
<meta property="og:site_name" content="Sorty">
<meta property="og:title" content="Changelog — Sorty">
<meta property="og:description" content="The full Sorty release history with highlights and changes for every version.">
<meta property="og:url" content="https://sorty-organizer.github.io/Sorty/changelog/">
<meta property="og:image" content="https://sorty-organizer.github.io/Sorty/assets/img/screenshots/post-gen.jpg">
<link rel="stylesheet" href="/assets/css/style.css">
<script type="application/ld+json">
{{
  "@context": "https://schema.org",
  "@type": "BreadcrumbList",
  "itemListElement": [
    {{ "@type": "ListItem", "position": 1, "name": "Sorty", "item": "https://sorty-organizer.github.io/Sorty/" }},
    {{ "@type": "ListItem", "position": 2, "name": "Changelog", "item": "https://sorty-organizer.github.io/Sorty/changelog/" }}
  ]
}}
</script>
<script type="application/ld+json">
{{
  "@context": "https://schema.org",
  "@type": "TechArticle",
  "headline": "Sorty Changelog",
  "description": "Full release history for the Sorty macOS app.",
  "url": "https://sorty-organizer.github.io/Sorty/changelog/",
  "about": {{ "@type": "SoftwareApplication", "name": "Sorty", "softwareVersion": "{latest_version}" }}
}}
</script>
</head>
<body>

<header class="nav" id="nav">
  <div class="nav-shell">
    <a class="nav-brand" href="/" aria-label="Sorty home"><img src="/assets/img/icon.png" alt="Sorty"><span>Sorty</span></a>
    <nav class="nav-links" aria-label="Primary">
      <a href="/#features">Features</a>
      <a href="/#how">How it works</a>
      <a href="/changelog/">Changelog</a>
      <a href="/privacy/">Privacy</a>
      <a href="/terms/">Terms</a>
    </nav>
    <div class="nav-cta">
      <a class="btn btn-primary" href="https://github.com/sorty-organizer/Sorty/releases/latest" download>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M17.05 20.28c-.98.95-2.05.8-3.08.36-1.09-.46-2.09-.48-3.24 0-1.44.62-2.2.44-3.06-.36C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09ZM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25Z"/></svg>
        <span class="btn-text">Download</span>
      </a>
      <button class="nav-toggle" aria-label="Menu" aria-expanded="false">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16"/></svg>
      </button>
    </div>
  </div>
</header>

<main class="changelog">
  <div class="wrap">
    <h1>Changelog</h1>
    <p class="lead">Every Sorty release, documented. Highlights for the big ones, and the full record for everything else — generated straight from <code>CHANGELOG.md</code>.</p>

{nav}

{body}

    <p class="muted" style="margin-top: 40px; text-align: center;">
      Looking for downloads? Grab the latest universal build on
      <a href="https://github.com/sorty-organizer/Sorty/releases" target="_blank" rel="noopener" style="color: var(--blue-bright);">GitHub Releases</a>.
    </p>
  </div>
</main>

<footer class="footer">
  <div class="wrap">
    <div class="footer-bottom" style="border-top: none; padding-top: 0;">
      <span>© 2026 Sorty. Released under the <a href="https://www.gnu.org/licenses/gpl-3.0" target="_blank" rel="noopener">GPL-3.0</a> license.</span>
      <span><a href="/">Home</a> · <a href="/terms/">Terms</a> · <a href="/privacy/">Privacy</a></span>
    </div>
  </div>
</footer>

<script src="/assets/js/main.js" defer></script>
</body>
</html>
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="exit 1 if the page would change")
    ap.add_argument("--out", type=Path, default=OUT, help="output file")
    args = ap.parse_args()

    if not CHANGELOG.exists():
        print(f"error: {CHANGELOG} not found", file=sys.stderr)
        return 1

    releases = parse_changelog(CHANGELOG.read_text(encoding="utf-8"))
    if not releases:
        print("error: no releases parsed from CHANGELOG.md", file=sys.stderr)
        return 1

    page = build_page(releases)

    if args.check:
        existing = args.out.read_text(encoding="utf-8") if args.out.exists() else ""
        if existing == page:
            print("changelog up to date")
            return 0
        print("changelog is out of date — run scripts/build_changelog.py", file=sys.stderr)
        return 1

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(page, encoding="utf-8")
    print(f"wrote {args.out.relative_to(ROOT)} ({len(releases)} releases)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
