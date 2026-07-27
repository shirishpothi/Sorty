# Sorty Website

Next.js marketing site for Sorty.

## Local Preview

```bash
pnpm install
pnpm dev
```

## Static Build

```bash
pnpm build
```

To preview the export with the same base path used by GitHub Pages:

```bash
pnpm build:pages
pnpm preview:pages
```

Open `http://localhost:3100/Sorty/`. Serving `out` directly from `/` will not
load its assets because the Pages build intentionally references `/Sorty`.
