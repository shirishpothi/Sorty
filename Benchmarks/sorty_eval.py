#!/usr/bin/env python3
"""Sorty organization benchmark scorer.

This is intentionally local and deterministic. It scores the contract and safety
checks that code can judge, then leaves semantic preference to manual or LLM
pairwise review packs.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import statistics
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent
FIXTURES_DIR = ROOT / "fixtures"
DEFAULT_RUNS_DIR = ROOT / "runs"
UNSAFE_RENAME_NAMES = {
    ".gitignore",
    "Makefile",
    "Package.swift",
    "package.json",
    "package-lock.json",
    "pnpm-lock.yaml",
    "yarn.lock",
    "vite.config.ts",
}


@dataclass
class OutputFile:
    filename: str
    folder_path: tuple[str, ...]
    suggested_name: str | None
    rename_reason: str | None
    raw: dict[str, Any]


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")


def fixture_paths(fixtures_dir: Path) -> list[Path]:
    return sorted(path for path in fixtures_dir.iterdir() if path.is_dir())


def load_fixture(fixture_id: str, fixtures_dir: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    fixture_dir = fixtures_dir / fixture_id
    return load_json(fixture_dir / "manifest.json"), load_json(fixture_dir / "expectations.json")


def input_filenames(manifest: dict[str, Any]) -> list[str]:
    return [file["filename"] for file in manifest.get("files", [])]


def normalize_output(record: dict[str, Any]) -> dict[str, Any]:
    output = record.get("output", record)
    if isinstance(output, str):
        return json.loads(output)
    if isinstance(output, dict):
        return output
    raise ValueError("output must be a JSON object or JSON string")


def folder_name(folder: dict[str, Any]) -> str:
    return str(folder.get("name") or folder.get("folderName") or "")


def child_folders(folder: dict[str, Any]) -> list[dict[str, Any]]:
    return folder.get("subfolders") or folder.get("children") or []


def direct_files(folder: dict[str, Any]) -> list[dict[str, Any]]:
    files = folder.get("files") or []
    normalized: list[dict[str, Any]] = []
    rename_by_original = {}
    for mapping in folder.get("fileRenameMappings") or []:
        original = mapping.get("originalFile") or {}
        name = original.get("filename") or original.get("displayName") or original.get("name")
        if not name and original.get("path"):
            name = os.path.basename(original["path"])
        if name:
            rename_by_original[name] = mapping

    for file in files:
        if isinstance(file, str):
            normalized.append({"filename": file})
            continue
        item = dict(file)
        name = item.get("filename") or item.get("displayName") or item.get("name")
        if not name and item.get("path"):
            name = os.path.basename(item["path"])
        item["filename"] = name
        mapping = rename_by_original.get(name)
        if mapping:
            item.setdefault("suggested_name", mapping.get("suggestedName"))
            item.setdefault("rename_reason", mapping.get("renameReason"))
        if item.get("suggestedFilename"):
            item.setdefault("suggested_name", item["suggestedFilename"])
        normalized.append(item)
    return normalized


def top_folders(output: dict[str, Any]) -> list[dict[str, Any]]:
    return output.get("folders") or output.get("suggestions") or []


def flatten_output(output: dict[str, Any]) -> tuple[list[OutputFile], list[str], int]:
    files: list[OutputFile] = []
    names: list[str] = []
    max_depth = 0

    def visit(folder: dict[str, Any], parents: tuple[str, ...]) -> None:
        nonlocal max_depth
        name = folder_name(folder)
        path = parents + ((name,) if name else tuple())
        if path:
            names.append(path[-1])
            max_depth = max(max_depth, len(path))
        for file in direct_files(folder):
            files.append(
                OutputFile(
                    filename=str(file.get("filename") or ""),
                    folder_path=path,
                    suggested_name=file.get("suggested_name") or file.get("suggestedName"),
                    rename_reason=file.get("rename_reason") or file.get("renameReason"),
                    raw=file,
                )
            )
        for child in child_folders(folder):
            visit(child, path)

    for folder in top_folders(output):
        visit(folder, tuple())

    for item in output.get("unorganized") or output.get("unorganizedFiles") or []:
        if isinstance(item, str):
            filename = item
        else:
            filename = item.get("filename") or item.get("displayName") or item.get("name")
            if not filename and item.get("path"):
                filename = os.path.basename(item["path"])
        files.append(OutputFile(str(filename or ""), ("unorganized",), None, None, item if isinstance(item, dict) else {}))
    return files, names, max_depth


def extension(name: str) -> str:
    if name.startswith(".") and name.count(".") == 1:
        return ""
    return Path(name).suffix.lower()


def file_folder_map(files: list[OutputFile]) -> dict[str, tuple[str, ...]]:
    mapping: dict[str, tuple[str, ...]] = {}
    for file in files:
        mapping[file.filename] = file.folder_path
    return mapping


def count_passed_pairs(pairs: list[list[str]], folders: dict[str, tuple[str, ...]], expect_same: bool) -> int:
    passed = 0
    for group in pairs:
        paths = [folders.get(name) for name in group]
        if any(path is None for path in paths):
            continue
        unique = {path for path in paths}
        if (len(unique) == 1) == expect_same:
            passed += 1
    return passed


def five_point(passed: int, total: int) -> float:
    if total == 0:
        return 5.0
    return round((passed / total) * 5, 2)


def score_fixture(record: dict[str, Any], manifest: dict[str, Any], expectations: dict[str, Any]) -> dict[str, Any]:
    hard_failures: list[str] = []
    scores: dict[str, float] = {}
    try:
        output = normalize_output(record)
    except Exception as error:
        return {
            "fixture": record.get("fixture") or manifest["id"],
            "scores": {metric: 0 for metric in metric_names()},
            "average": 0,
            "hardFailures": [f"invalid JSON: {error}"],
        }

    files, folder_names, max_depth = flatten_output(output)
    input_names = input_filenames(manifest)
    input_set = set(input_names)
    output_names = [file.filename for file in files if file.filename]
    counts = Counter(output_names)
    missing = sorted(input_set - set(output_names))
    hallucinated = sorted(set(output_names) - input_set)
    duplicates = sorted(name for name, count in counts.items() if count > 1)

    if missing:
        hard_failures.append(f"missing files: {', '.join(missing)}")
    if hallucinated:
        hard_failures.append(f"hallucinated files: {', '.join(hallucinated)}")
    if duplicates:
        hard_failures.append(f"duplicate files: {', '.join(duplicates)}")
    if max_depth > expectations.get("maxDepth", manifest.get("settings", {}).get("maxDepth", 3)):
        hard_failures.append(f"folder depth {max_depth} exceeds limit")
    if len(top_folders(output)) > expectations.get("maxTopLevelFolders", manifest.get("settings", {}).get("maxTopLevelFolders", 99)):
        hard_failures.append("top-level folder count exceeds limit")

    bad_folder_names = {name.lower() for name in expectations.get("badFolderNames", [])}
    bad_names_used = [name for name in folder_names if name.lower() in bad_folder_names]
    top_level_ok = len(top_folders(output)) > 0
    scores["jsonContractValidity"] = 5.0 if isinstance(output, dict) and top_level_ok else 2.0
    scores["fileCoverage"] = five_point(len(input_set) - len(missing) - len(duplicates) - len(hallucinated), max(len(input_set), 1))

    folders = file_folder_map(files)
    together = expectations.get("shouldGroupTogether", [])
    apart = expectations.get("shouldNotGroupTogether", [])
    grouping_total = len(together) + len(apart)
    grouping_passed = count_passed_pairs(together, folders, True) + count_passed_pairs(apart, folders, False)
    grouping_score = five_point(grouping_passed, grouping_total)
    unique_non_unorganized_folders = {
        path for path in folders.values()
        if path and path != ("unorganized",)
    }
    useful_separation_score = 5.0
    if len(input_set) >= 4 and len(unique_non_unorganized_folders) <= 1 and manifest.get("organizationMode") != "renameOnly":
        useful_separation_score = 1.0
    elif len(input_set) >= 6 and len(unique_non_unorganized_folders) <= 2 and len(together) >= 2:
        useful_separation_score = 3.0
    specific_folder_count = sum(
        1 for name in folder_names
        if len(name.strip()) >= 5 and name.lower() not in bad_folder_names and name not in {".", "All Files"}
    )
    folder_clarity_score = five_point(specific_folder_count, max(len(folder_names), 1))
    grouping_score = round(statistics.mean([grouping_score, useful_separation_score, folder_clarity_score]), 2)
    if bad_names_used:
        grouping_score = max(0, grouping_score - min(2, len(bad_names_used)))
    scores["organizationQuality"] = grouping_score

    rename_expect = expectations.get("rename", {})
    renamed = {file.filename: file for file in files if file.suggested_name}
    must_keep = set(rename_expect.get("mustKeepUnrenamed", []))
    never_rename = set(rename_expect.get("neverRename", [])) | {name for name in input_names if name in UNSAFE_RENAME_NAMES}
    may_rename = set(rename_expect.get("mayRenameWithEvidence", []))
    disallow_rename_fields = bool(rename_expect.get("disallowRenameFields") or manifest.get("organizationMode") == "organize")

    unnecessary_renames = sorted((must_keep | never_rename) & set(renamed))
    allowed_renames = sorted(set(renamed) & may_rename)
    rename_fields_in_organize = sorted(renamed) if disallow_rename_fields else []
    if rename_fields_in_organize:
        hard_failures.append("rename fields present in organize-only mode")
    if unnecessary_renames:
        hard_failures.append(f"unsafe or unnecessary renames: {', '.join(unnecessary_renames)}")

    rename_denominator = max(len(must_keep | never_rename | may_rename), 1)
    rename_passed = len((must_keep | never_rename) - set(renamed)) + len(allowed_renames)
    scores["renameNecessity"] = five_point(rename_passed, rename_denominator)

    trust_penalties = 0
    forbidden = [value.lower() for value in rename_expect.get("forbiddenSuggestedNameSubstrings", [])]
    for original, file in renamed.items():
        suggested = str(file.suggested_name)
        if extension(original) != extension(suggested):
            hard_failures.append(f"extension changed for {original}")
            trust_penalties += 2
        if not file.rename_reason and rename_expect.get("renameOnlyWhenEvidence", True):
            trust_penalties += 1
        lowered = suggested.lower()
        if any(term in lowered for term in forbidden):
            hard_failures.append(f"forbidden invented context in rename for {original}")
            trust_penalties += 2
    scores["renameTrustworthiness"] = max(0.0, 5.0 - trust_penalties)

    insights = record.get("liveInsights") or record.get("insights") or []
    scores["liveInsightQuality"] = score_insights(insights, expectations)

    instruction_score = 5.0
    if disallow_rename_fields and renamed:
        instruction_score -= 3
    if bad_names_used:
        instruction_score -= 1
    if max_depth > expectations.get("maxDepth", 3):
        instruction_score -= 1
    scores["instructionPersonaAdherence"] = max(0.0, instruction_score)

    average = round(statistics.mean(scores.values()), 2)
    if hard_failures:
        average = round(min(average, 2.5), 2)

    return {
        "fixture": record.get("fixture") or manifest["id"],
        "scores": scores,
        "average": average,
        "hardFailures": hard_failures,
        "details": {
            "missing": missing,
            "duplicates": duplicates,
            "hallucinated": hallucinated,
            "renamed": sorted(renamed),
            "badFolderNamesUsed": bad_names_used,
            "maxDepth": max_depth,
            "topLevelFolderCount": len(top_folders(output)),
        },
    }


def score_insights(insights: list[Any], expectations: dict[str, Any]) -> float:
    cleaned = [str(item).strip() for item in insights if str(item).strip()]
    if not cleaned:
        return 0.0
    score = 2.0
    concise = sum(1 for item in cleaned if 12 <= len(item) <= 140)
    score += min(1.0, concise / max(len(cleaned), 1))
    fake_move_terms = ("moving ", "moved ", "creating folder")
    if not any(term in item.lower() for item in cleaned for term in fake_move_terms):
        score += 1.0
    needles = [term.lower() for term in expectations.get("liveInsightMustMentionAny", [])]
    if needles and any(needle in item.lower() for item in cleaned for needle in needles):
        score += 1.0
    return round(min(score, 5.0), 2)


def metric_names() -> list[str]:
    return [
        "jsonContractValidity",
        "fileCoverage",
        "organizationQuality",
        "renameNecessity",
        "renameTrustworthiness",
        "liveInsightQuality",
        "instructionPersonaAdherence",
    ]


def read_outputs(path: Path) -> list[dict[str, Any]]:
    records = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            stripped = line.strip()
            if not stripped:
                continue
            try:
                records.append(json.loads(stripped))
            except json.JSONDecodeError as error:
                records.append({"fixture": f"line-{line_number}", "output": stripped, "_jsonError": str(error)})
    return records


def command_validate_fixtures(args: argparse.Namespace) -> int:
    problems: list[str] = []
    for fixture_dir in fixture_paths(args.fixtures):
        manifest_path = fixture_dir / "manifest.json"
        expectations_path = fixture_dir / "expectations.json"
        if not manifest_path.exists() or not expectations_path.exists():
            problems.append(f"{fixture_dir.name}: missing manifest.json or expectations.json")
            continue
        manifest = load_json(manifest_path)
        expectations = load_json(expectations_path)
        names = input_filenames(manifest)
        if len(names) != len(set(names)):
            problems.append(f"{fixture_dir.name}: duplicate input filenames")
        referenced = set()
        for key in ("shouldGroupTogether", "shouldNotGroupTogether"):
            for group in expectations.get(key, []):
                referenced.update(group)
        rename = expectations.get("rename", {})
        for key in ("mustKeepUnrenamed", "mayRenameWithEvidence", "neverRename"):
            referenced.update(rename.get(key, []))
        unknown = sorted(referenced - set(names))
        if unknown:
            problems.append(f"{fixture_dir.name}: expectations reference unknown files: {', '.join(unknown)}")
    if problems:
        for problem in problems:
            print(problem, file=sys.stderr)
        return 1
    print(f"Validated {len(fixture_paths(args.fixtures))} fixtures.")
    return 0


def command_score(args: argparse.Namespace) -> int:
    records = read_outputs(args.outputs)
    results = []
    by_fixture = {record.get("fixture"): record for record in records}
    for fixture_dir in fixture_paths(args.fixtures):
        fixture_id = fixture_dir.name
        record = by_fixture.get(fixture_id)
        manifest, expectations = load_fixture(fixture_id, args.fixtures)
        if record is None:
            results.append({
                "fixture": fixture_id,
                "scores": {metric: 0 for metric in metric_names()},
                "average": 0,
                "hardFailures": ["missing output record"],
            })
            continue
        results.append(score_fixture(record, manifest, expectations))

    aggregate = {
        "fixtureCount": len(results),
        "average": round(statistics.mean(item["average"] for item in results), 2) if results else 0,
        "metricAverages": {
            metric: round(statistics.mean(item["scores"].get(metric, 0) for item in results), 2)
            for metric in metric_names()
        },
        "hardFailureCount": sum(1 for item in results if item.get("hardFailures")),
    }
    payload = {"aggregate": aggregate, "fixtures": results}
    scores_path = args.scores or args.outputs.with_name("scores.json")
    write_json(scores_path, payload)
    print(f"Wrote {scores_path}")
    print(json.dumps(aggregate, indent=2, sort_keys=True))
    return 0


def command_compare(args: argparse.Namespace) -> int:
    left = load_json(args.left)
    right = load_json(args.right)
    left_by_fixture = {item["fixture"]: item for item in left.get("fixtures", [])}
    right_by_fixture = {item["fixture"]: item for item in right.get("fixtures", [])}
    fixture_ids = sorted(set(left_by_fixture) | set(right_by_fixture))
    wins = defaultdict(int)
    rows = []
    for fixture_id in fixture_ids:
        left_score = left_by_fixture.get(fixture_id, {}).get("average", 0)
        right_score = right_by_fixture.get(fixture_id, {}).get("average", 0)
        if left_score > right_score:
            winner = "left"
        elif right_score > left_score:
            winner = "right"
        else:
            winner = "tie"
        wins[winner] += 1
        rows.append({"fixture": fixture_id, "left": left_score, "right": right_score, "winner": winner})
    payload = {
        "left": str(args.left),
        "right": str(args.right),
        "wins": dict(wins),
        "rows": rows,
        "judgePrompt": "Which result is better for a real user? A, B, tie, or both bad. Consider organization usefulness, rename necessity, trustworthiness, and live insight quality.",
    }
    if args.output:
        write_json(args.output, payload)
        print(f"Wrote {args.output}")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


def command_run(args: argparse.Namespace) -> int:
    run_dir = args.run_dir or DEFAULT_RUNS_DIR / args.name
    run_dir.mkdir(parents=True, exist_ok=True)
    output_path = run_dir / "outputs.jsonl"
    if args.outputs:
        records = read_outputs(args.outputs)
        with output_path.open("w", encoding="utf-8") as handle:
            for record in records:
                record.setdefault("model", args.model)
                record.setdefault("prompt", args.prompt)
                handle.write(json.dumps(record, sort_keys=True) + "\n")
        print(f"Copied {len(records)} records to {output_path}")
        return command_score(argparse.Namespace(outputs=output_path, scores=run_dir / "scores.json", fixtures=args.fixtures))
    print("Model execution is intentionally not wired to provider credentials yet.", file=sys.stderr)
    print("Pass --outputs with captured Sorty responses to create and score a run.", file=sys.stderr)
    return 2


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Score Sorty organization benchmark runs.")
    parser.set_defaults(func=lambda _: parser.print_help() or 0)
    subparsers = parser.add_subparsers()

    validate = subparsers.add_parser("validate-fixtures")
    validate.add_argument("--fixtures", type=Path, default=FIXTURES_DIR)
    validate.set_defaults(func=command_validate_fixtures)

    score = subparsers.add_parser("score")
    score.add_argument("--outputs", type=Path, required=True)
    score.add_argument("--scores", type=Path)
    score.add_argument("--fixtures", type=Path, default=FIXTURES_DIR)
    score.set_defaults(func=command_score)

    compare = subparsers.add_parser("compare")
    compare.add_argument("left", type=Path)
    compare.add_argument("right", type=Path)
    compare.add_argument("--output", type=Path)
    compare.set_defaults(func=command_compare)

    run = subparsers.add_parser("run")
    run.add_argument("--model", required=True)
    run.add_argument("--prompt", required=True)
    run.add_argument("--name", default=None)
    run.add_argument("--outputs", type=Path)
    run.add_argument("--run-dir", type=Path)
    run.add_argument("--fixtures", type=Path, default=FIXTURES_DIR)
    run.set_defaults(func=command_run)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if getattr(args, "name", None) is None and hasattr(args, "model") and hasattr(args, "prompt"):
        safe_model = re.sub(r"[^A-Za-z0-9_.-]+", "-", args.model)
        safe_prompt = re.sub(r"[^A-Za-z0-9_.-]+", "-", args.prompt)
        args.name = f"{safe_model}-{safe_prompt}"
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
