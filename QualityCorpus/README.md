# Private organization quality corpus

Keep real cases in `QualityCorpus/private/`. Git ignores that directory because filenames, paths, expected destinations, and extracted evidence may be sensitive. The committed `sample/` case is synthetic and documents the schema.

Each JSON file describes one representative folder after a run. Add one decision per file. Cover expected moves, expected non-moves, useful renames, protected names, and cases that should remain uncertain. Record the final preview outcome instead of silently changing the expected answer to match the model.

Run the report with:

```sh
make quality-report
```

Set `QUALITY_CORPUS=QualityCorpus/sample` to verify the synthetic example. Run the executable directly with `--json` for a machine-readable report. Keep generated reports in `QualityCorpus/reports/`, which Git also ignores.

The report tracks placement acceptance and expectation matches, rename accepts, edits, rejections, reverts, manual edits per 100 files, protected-name preservation, ambiguous review handling, and confidence calibration. A 90% confidence bin is calibrated when about 90% of its suggestions are accepted without edits.
