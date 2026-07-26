# Plan schema

Use UTF-8 JSON with this shape:

```json
{
  "version": 1,
  "mode": "organize",
  "root": "/Users/example/Downloads",
  "operations": [
    {
      "source": "chemistry-notes.pdf",
      "destination": "School/Chemistry/chemistry-notes.pdf",
      "reason": "The document title and extracted headings identify chemistry coursework.",
      "confidence": 0.96
    }
  ],
  "unorganized": [
    {
      "path": "unknown.bin",
      "reason": "There is not enough evidence to categorize this safely."
    }
  ],
  "notes": "Existing School and Chemistry folders were reused."
}
```

## Fields

- `version` must be `1`.
- `mode` must be `organize`, `organize-and-rename`, or `rename-only`.
- `root` must be the absolute inventory root.
- `operations` must contain each source at most once and each destination at most once.
- `source` must be a relative path inside `root` and must identify an existing regular file.
- `destination` should be relative to `root`. Use an absolute path only for a destination under a storage root the user explicitly approved.
- `reason` should cite the evidence that drove the decision.
- `confidence` is optional and must be between `0` and `1`.
- `unorganized` records eligible files intentionally left in place. It is explanatory and is not executed.
- `notes` is optional plan-level context.

## Mode invariants

- `organize`: the source and destination basenames must match exactly.
- `organize-and-rename`: the parent directory and basename may both change, but the extension must remain unchanged.
- `rename-only`: the source and destination parent directories must resolve to the same directory, and the extension must remain unchanged.

The executor rejects collisions, missing sources, symlink sources, escaping paths, duplicate sources or destinations, extension changes, and mode violations. It creates destination directories only during an approved execution.
