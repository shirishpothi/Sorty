# getdroppy.app website source mirror

This folder contains a local mirror of the publicly served client-side website source from https://getdroppy.app/.

- `getdroppy.app/index.html.orig` is the original HTML response saved before local link conversion.
- `getdroppy.app/index.html` is the same page with links rewritten by `wget` for local browsing.
- `getdroppy.app/supplied-source.html` is the HTML source supplied from `/Users/shirishpothi/Downloads/output-2026-06-27T04-56-17-765Z.txt`.
- `getdroppy.app/assets/`, `framerusercontent.com/`, and `fonts.gstatic.com/` contain the public assets downloaded from the page.
- `cdn.jsdelivr.net/` and `cdn.affonso.io/` contain third-party scripts referenced by the page.
- `getdroppy.app/recover-license.html` and `getdroppy.app/changelog.json` were downloaded from public routes referenced by inline page scripts.

This is a mirror of the public website payload only. Private server-side source code is not available from the live site response.

The live links `https://getdroppy.app/legal/privacy-policy` and `https://getdroppy.app/legal/term-of-service` returned Netlify 404 responses when checked, so no public source for those routes is included.
