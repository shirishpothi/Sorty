# Sorty Eval Benchmarks

This benchmark suite measures expected user value for Sorty's organization output. It intentionally uses behavioral expectations instead of one exact folder tree, because several useful organizations can be correct.

## Layout

```text
Benchmarks/
  fixtures/
    messy-downloads/
      manifest.json
      expectations.json
  runs/
    2026-06-18-openai-gpt-x-system-v3/
      outputs.jsonl
      scores.json
```

Each fixture has:

- `manifest.json`: scanned file inputs with real-ish names, paths, sizes, dates, tags, Finder comments, and content summaries.
- `expectations.json`: required safety rules, acceptable groupings, rename policy, scoring hints, and notes about what "good" means.

## Output Contract

The scorer accepts either Sorty's production prompt JSON shape:

```json
{
  "folders": [
    {
      "name": "FolderName",
      "description": "Purpose",
      "files": [
        {
          "filename": "IMG_1234.jpg",
          "suggested_name": "Golden Gate Sunset.jpg",
          "rename_reason": "Content confirms the scene",
          "rename_confidence": 0.92
        }
      ],
      "subfolders": []
    }
  ],
  "unorganized": [],
  "notes": "..."
}
```

or the app model shape with `suggestions`, `folderName`, `fileRenameMappings`, and `unorganizedFiles`.

`outputs.jsonl` should contain one JSON object per fixture:

```json
{"fixture":"messy-downloads","prompt":"current","model":"gpt-4.1","output":{...},"liveInsights":["Grouped installer downloads separately from trip screenshots."]}
```

## CLI

```bash
python3 Benchmarks/sorty_eval.py validate-fixtures
python3 Benchmarks/sorty_eval.py score --outputs Benchmarks/runs/current/outputs.jsonl
python3 Benchmarks/sorty_eval.py compare Benchmarks/runs/current/scores.json Benchmarks/runs/candidate/scores.json
```

`score` writes `scores.json` next to the output file unless `--scores` is provided.

## Metrics

Each category is scored 0-5:

- `jsonContractValidity`
- `fileCoverage`
- `organizationQuality`
- `renameNecessity`
- `renameTrustworthiness`
- `liveInsightQuality`
- `instructionPersonaAdherence`

Hard failures are recorded for invalid JSON, missing files, duplicate files, hallucinated files, folder depth over 3, top-level folder count over the fixture setting, extension changes, unsafe renames, and organize-only rename fields.
