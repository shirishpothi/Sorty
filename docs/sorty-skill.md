# Sorty skill for Codex

The `$sorty` skill lets Codex handle file-organization requests with the same
safety boundaries as Sorty. It uses the installed macOS app when a workflow
depends on Sorty's interface or saved settings. For direct local work, it can
build and apply a reversible filesystem plan.

The tracked skill lives in [`.agents/skills/sorty`](../.agents/skills/sorty/).
That directory is the source of truth for the skill and its helper.

## What it can do

Ask `$sorty` to:

- organize files without renaming them;
- rename files without moving them;
- organize and rename in one plan;
- scan for byte-identical duplicates;
- preview, validate, and apply a proposed plan;
- roll back moves and renames recorded by the skill;
- open the relevant Sorty screen for exclusions, personas, Learnings, watched
  folders, storage locations, history, settings, or duplicate review.

The fallback handles local scanning, SHA-256 duplicate checks, collision-safe
moves and renames, cross-volume verification, append-only journals, and
rollback. It does not recreate the macOS app. Sorty still owns Finder actions,
Finder tags, semantic duplicate review, background watching, widgets, HUD
notifications, interactive previews, provider credentials, Keychain access,
Learnings security, updates, and diagnostics.

## Install the skill

Codex discovers personal skills under `~/.codex/skills`. Link the repository
copy so edits remain tracked in Git:

```bash
ln -s "/absolute/path/to/Sorty/.agents/skills/sorty" ~/.codex/skills/sorty
```

Do not replace an existing `~/.codex/skills/sorty` entry until you have checked
where it points. Restart Codex if the skill does not appear after installation.

Repository contributors can inspect the skill directly without creating the
personal link.

## Use it

Codex can select the skill automatically for file-organization requests, or you
can invoke it explicitly:

```text
Use $sorty to organize my Downloads folder without renaming anything.
Use $sorty to preview cleaner names for the files in this folder.
Use $sorty to find exact duplicates here.
Use $sorty to open Sorty's watched-folder settings for this folder.
Use $sorty to roll back the last plan it applied.
```

Wording controls whether the request is read-only. "How would you organize
this?" and "suggest a structure" request a preview. "Organize this folder" or
"apply this plan" authorizes the listed non-destructive moves and renames.

The skill asks separately before it deletes or trashes duplicates, overwrites
or merges a destination, resolves an ambiguous collision, sends file contents
to a cloud model, or clears saved Sorty data.

## Native app or agent fallback

| Request | Execution path |
| --- | --- |
| Organize or rename local files | Native Sorty or agent fallback |
| Find exact duplicates | Native Sorty or agent fallback |
| Review similar files visually | Native Sorty |
| Edit an interactive preview | Native Sorty |
| Change Finder tags | Native Sorty |
| Manage watched folders, personas, Learnings, providers, or storage | Native Sorty |
| Roll back work | The path that originally applied the work |

Native workflows open through Sorty's `sorty://` deeplinks. Opening a screen is
not proof that the operation finished. Sorty may still need a permission,
provider configuration, review, or final Apply action.

The app and the skill keep separate histories. Sorty's History restores work
applied by the app. The agent fallback restores only operations recorded in its
own journal under `~/Library/Application Support/Sorty Skill/`.

## Safety model

The skill resolves the exact source folder before applying a plan. It rejects a
filesystem root, a home directory, and unresolved path variables as apply
roots. It inventories first, preserves hidden files and packages by default,
honors exclusions, and refuses silent overwrites.

Every considered item belongs in the plan or appears as unorganized with a
reason. Existing timestamps, extended attributes, and Finder tags move with a
file unless the request explicitly changes them.

Exact duplicates mean identical bytes confirmed with SHA-256. Similar names,
sizes, dates, images, or model judgments are not proof that files are exact
duplicates.

## Maintaining the skill

Keep the entrypoint concise and route detailed behavior through its reference
files:

- [`SKILL.md`](../.agents/skills/sorty/SKILL.md) defines routing and authorization.
- [`capabilities.md`](../.agents/skills/sorty/references/capabilities.md) maps
  Sorty features to native or agent execution.
- [`native-routing.md`](../.agents/skills/sorty/references/native-routing.md)
  records the supported deeplinks.
- [`agent-mode.md`](../.agents/skills/sorty/references/agent-mode.md) defines the
  plan, journal, apply, and rollback contracts.

When Sorty gains a user-facing capability, update the capability map and check
whether the app's deeplink contract also changed. Run the skill validator and
the focused helper tests after changing behavior. Documentation-only edits do
not require an app build.
