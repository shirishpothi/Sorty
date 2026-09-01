# Example-folder learning

Sorty can use up to five well-organized folders as examples. It scans folder names, hierarchy depth, file types, extensions, and a small representative set of filenames. The scan never changes the example folder.

For each organization preview, Sorty compares the incoming file types with enabled examples. It sends at most the two closest matches to the selected AI provider. Unrelated examples stay out of the prompt, and rename-only runs do not use example folders.

The Learnings screen shows what each scan found, when it ran, and whether Sorty hit a depth, folder-count, or permission limit. A failed rescan keeps the last successful result. Users can rescan, pause, open, or remove an example folder at any time.

Representative filenames improve naming-pattern detection and may be sent to the selected AI provider. Sorty sends compact evidence, not file contents, and instructs the provider to recreate analogous organization rather than move files into the example folder.
