---
name: sorty-organizer
description: Semantically inspect and organize folder contents with a Sorty-style preview-first workflow, including organize-only, organize-and-rename, and rename-only modes; content-aware grouping; exclusion rules; exact duplicate reporting; collision-safe application; and undo manifests. Use when the user asks Codex to clean up, sort, categorize, restructure, or intelligently rename files in a local folder. This experimental skill handles one-shot folder organization and must not silently delete files or start background folder monitoring.
---

# Sorty Organizer

Organize local files by meaning and context while keeping every filesystem change reviewable and reversible. Treat AI judgment as plan generation; enforce exclusions, path boundaries, mode rules, and collisions deterministically.

## Workflow

1. **Resolve the scope.** Identify the exact root folder and one mode:
   - `organize`: move files while preserving every filename.
   - `organize-and-rename`: move files and suggest evidence-backed names.
   - `rename-only`: rename each file in its current directory.

   Default to `organize`. Treat user instructions as higher priority than heuristics, but never let them bypass filesystem safety. Do not include folders outside the named root unless the user explicitly names them as approved destination roots.

2. **Inventory without mutation.** Run:

   ```bash
   python3 <skill-dir>/scripts/inventory.py "/absolute/root" --hash-duplicates --output /tmp/sorty-inventory.json
   ```

   Add `--exclude GLOB` for each user exclusion. Hidden files, package/build internals, version-control data, and known system files are excluded by default. Never broaden the root implicitly.

3. **Understand the files.** Read the inventory first, then inspect only enough content to distinguish ambiguous files:
   - Prefer filenames, relative paths, dates, sizes, Finder metadata, and the existing folder structure.
   - Read text and document content locally with the appropriate file tools.
   - Inspect images only when visual meaning affects placement or renaming.
   - Do not upload private file content or use external services unless the user explicitly authorizes it.
   - Reuse sensible existing folders. Create semantic folders around projects, subjects, clients, events, or workflows; use broad type folders only when content gives no better signal.

4. **Build a complete plan.** Read [references/plan-schema.md](references/plan-schema.md), then write a JSON plan outside the target root, normally under `/tmp`. Assign each eligible file exactly once or list it under `unorganized`. Keep excluded and skipped files out of operations.

   For renames, preserve the extension, use one consistent pattern within a folder, avoid invented facts, and keep the original name when evidence is weak. Never rename dotfiles, stable config names, or semantic-versioned artifacts. Report exact duplicate groups separately; never delete duplicates automatically.

5. **Validate and preview.** Run the executor without `--execute`:

   ```bash
   python3 <skill-dir>/scripts/apply_plan.py /tmp/sorty-plan.json
   ```

   Add one `--allow-destination-root "/absolute/path"` per explicitly approved external destination. Fix every validation error before presenting the plan. Show a compact preview with source, destination, reason, exclusions/unorganized files, duplicate groups, and warnings. For a large or consequential plan, summarize by folder and call out surprising moves individually.

6. **Apply only after approval.** A request to inspect, suggest, preview, or plan is read-only. After the user approves the shown plan, run the same command with `--execute`. Let the script write its undo manifest under `<root>/.sorty-organizer-history/` unless another manifest path is appropriate.

7. **Verify the actual result.** Re-inventory the root, confirm every approved destination exists and every source is absent, and report the manifest path. Do not claim success from the executor exit code alone.

## Editing and partial approval

If the user changes a proposed destination, edit the JSON plan and preflight it again. If the user approves only part of the plan, create a smaller plan containing only those operations; do not apply the rest.

If a source changes or disappears between preview and apply, stop and regenerate the affected operation. Never substitute a similarly named file.

## Undo

Preview an undo:

```bash
python3 <skill-dir>/scripts/apply_plan.py --undo "/absolute/manifest.json"
```

After explicit approval, repeat with `--execute`, then verify the restored paths. Undo must stop on collisions rather than overwriting current files.

## Boundaries

- Never overwrite, merge, delete, Trash, or deduplicate files as part of organization.
- Never move a source through a symlink or outside the selected root.
- Never place a destination outside the root without an explicit approved destination root.
- Never manufacture a confident category or filename from weak evidence; use a broad folder or `unorganized`.
- Never install a watcher, LaunchAgent, automation, or recurring task unless the user separately requests it.
