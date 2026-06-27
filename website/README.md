# Sorty marketing site

A static, dependency-free website for the Sorty macOS app. Built to be hosted as
GitHub Pages from this `website/` directory.

## Structure

```
website/
├── index.html            # Landing page
├── changelog/index.html  # Rendered release history (sourced from /CHANGELOG.md)
├── privacy/index.html    # Privacy Policy
├── terms/index.html      # Terms of Service
├── robots.txt            # Crawler directives + sitemap reference
├── sitemap.xml           # SEO sitemap
├── site.webmanifest      # PWA manifest
├── CNAME                 # Custom domain: sorty.app
└── assets/
    ├── css/style.css      # Single stylesheet (Apple-style dark theme)
    ├── js/main.js         # Nav behaviour, scroll reveal, copy-to-clipboard
    └── img/               # Screenshots, app icon, mascot, provider logos
```

## Develop locally

No build step. Serve the directory with any static server:

```bash
cd website
python3 -m http.server 8099
# open http://localhost:8099
```

## Deployment

This directory is self-contained and root-relative (paths start with `/`), so it
deploys cleanly to GitHub Pages. Enable Pages on the repo (served from the
`main` branch `/website` folder) and the `CNAME` file points it at `sorty.app`.

## Keeping the changelog current

The changelog page is hand-structured from `../CHANGELOG.md`. When a new release
ships, add a matching `<article class="release">` block and a nav link in
`changelog/index.html`. Dates and tags match the GitHub releases.

## Updating screenshots

Screenshots live in `Assets/Screenshots/New UI/`. To regenerate optimized web
copies:

```bash
SRC="../Assets/Screenshots/New UI"
for f in "Live Insights View" "Watched Folder View" "Post Generation View" \
         "Workspace Health View" "Settings Providers View" "Duplicates View" \
         "Exclusions View" "Mid-Generation View" "Apply View"; do
  sips -Z 1600 "$SRC/$f.png" --out "assets/img/screenshots/$(echo $f | tr ' A-Z' '_a-z').jpg" \
       -s format jpeg -s formatOptions 85
done
```

## SEO

- Per-page `<title>`, meta description, canonical, Open Graph, and Twitter cards.
- JSON-LD `SoftwareApplication` on the home page; `TechArticle` on the changelog.
- `robots.txt`, `sitemap.xml`, and `site.webmanifest` included.
- Semantic HTML, descriptive alt text, lazy-loaded imagery.
