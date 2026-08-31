# Native Sorty routing

Use the installed app when the request depends on macOS integration, Sorty's saved configuration, or its interactive interface.

## Availability

Check for `/Applications/Sorty.app`, `~/Applications/Sorty.app`, or a running Sorty process without changing system state. If none is available, explain which part can run in agent mode and which part requires the app.

Open a native route only when the user's request authorizes opening Sorty. Build URLs with a URL encoder. Never concatenate an unescaped path, persona, prompt, rule, or pattern.

## Deeplink contract

| Request | Route |
| --- | --- |
| Organize or scan | `sorty://organize?path=...&persona=...&mode=...&autostart=true` |
| Duplicate review | `sorty://duplicates?path=...&autostart=true` |
| Open a folder | `sorty://open?path=...` |
| History and rollback UI | `sorty://history` |
| Learnings | `sorty://learnings?action=stats|withdraw|export|import|clear&project=...` |
| Persona creation or selection | `sorty://persona?action=...&prompt=...&generate=true` |
| Watched folders | `sorty://watched?action=add|remove&path=...` |
| Rules | `sorty://rules?action=add&type=...&pattern=...` |
| Exclusions | `sorty://exclusions?action=add&pattern=...` |
| Exclude one path | `sorty://exclude?path=...` |
| Storage locations | `sorty://storage?action=add|remove&path=...` |
| Settings | `sorty://settings?section=...` |
| Help | `sorty://help?section=...` |

Supported organization modes are `organize`, `organizeAndRename`, and `renameOnly`. `scan` is an alias that autostarts organization.

Use the `open` command with one fully encoded URL. Opening the app is an external UI action, so follow the current environment's approval rules.

## Native-only ownership

Route these to the app instead of approximating them:

- Finder tag changes and tag-color selection semantics;
- semantic duplicate review and visual comparison;
- persistent watched-folder monitoring, snooze, retries, and notify-to-review;
- Finder extension activation or repair;
- provider authentication, Keychain access, Apple Foundation Models, and custom endpoints;
- Learnings encryption, biometric protection, import, export, withdrawal, and clearing;
- personas stored by Sorty;
- cloud, external-drive, and cross-volume destination setup;
- interactive preview edits, HUD and native notifications, widgets, updates, privacy settings, and diagnostics.

Do not claim success after opening a route. The app may still require configuration, permission, review, or a final Apply action.
