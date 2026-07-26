#!/usr/bin/env python3
"""Validate, apply, or undo a Sorty-style filesystem plan without overwrites."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


VALID_MODES = {"organize", "organize-and-rename", "rename-only"}
STABLE_NAMES = {
    "Dockerfile",
    "Gemfile",
    "LICENSE",
    "Makefile",
    "Package.swift",
    "Podfile",
    "README",
    "README.md",
}
SEMVER_PATTERN = re.compile(r"(?:^|[-_.])v?\d+\.\d+(?:\.\d+)?(?:[-_.]|$)", re.IGNORECASE)


class PlanError(Exception):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plan", nargs="?", type=Path, help="JSON plan to validate or apply")
    parser.add_argument("--execute", action="store_true", help="Perform the validated moves")
    parser.add_argument("--manifest", type=Path, help="Execution manifest path")
    parser.add_argument("--allow-destination-root", action="append", default=[], type=Path, metavar="PATH")
    parser.add_argument("--undo", type=Path, metavar="MANIFEST", help="Validate or execute an undo manifest")
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.expanduser().read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PlanError(f"cannot read JSON from {path}: {error}") from error
    if not isinstance(value, dict):
        raise PlanError("top-level JSON value must be an object")
    return value


def is_within(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def resolved_candidate(path: Path) -> Path:
    return path.expanduser().resolve(strict=False)


def require_relative_source(raw: Any, root: Path) -> Path:
    if not isinstance(raw, str) or not raw.strip():
        raise PlanError("source must be a non-empty string")
    candidate = Path(raw)
    if candidate.is_absolute():
        raise PlanError(f"source must be relative to root: {raw}")
    resolved = resolved_candidate(root / candidate)
    if not is_within(resolved, root):
        raise PlanError(f"source escapes root: {raw}")
    return resolved


def resolve_destination(raw: Any, root: Path, allowed_roots: list[Path]) -> Path:
    if not isinstance(raw, str) or not raw.strip():
        raise PlanError("destination must be a non-empty string")
    candidate = Path(raw)
    resolved = resolved_candidate(candidate if candidate.is_absolute() else root / candidate)
    if not any(is_within(resolved, allowed_root) for allowed_root in allowed_roots):
        raise PlanError(f"destination is outside approved roots: {raw}")
    return resolved


def extension(path: Path) -> str:
    return path.suffix.casefold()


def is_protected_rename(source: Path) -> bool:
    return source.name.startswith(".") or source.name in STABLE_NAMES or bool(SEMVER_PATTERN.search(source.stem))


def validate_plan(plan: dict[str, Any], extra_roots: list[Path]) -> tuple[Path, str, list[dict[str, Any]], list[Path]]:
    if plan.get("version") != 1:
        raise PlanError("version must be 1")
    mode = plan.get("mode")
    if mode not in VALID_MODES:
        raise PlanError(f"mode must be one of: {', '.join(sorted(VALID_MODES))}")
    raw_root = plan.get("root")
    if not isinstance(raw_root, str) or not Path(raw_root).is_absolute():
        raise PlanError("root must be an absolute path string")
    root = Path(raw_root).expanduser().resolve()
    if not root.is_dir():
        raise PlanError(f"root is not an existing directory: {root}")

    allowed_roots = [root]
    for raw_allowed in extra_roots:
        allowed = raw_allowed.expanduser().resolve()
        if not allowed.is_dir():
            raise PlanError(f"approved destination root is not a directory: {allowed}")
        allowed_roots.append(allowed)

    raw_operations = plan.get("operations")
    if not isinstance(raw_operations, list):
        raise PlanError("operations must be an array")

    operations: list[dict[str, Any]] = []
    seen_sources: set[Path] = set()
    seen_destinations: set[Path] = set()
    for index, raw_operation in enumerate(raw_operations, start=1):
        if not isinstance(raw_operation, dict):
            raise PlanError(f"operation {index} must be an object")
        source = require_relative_source(raw_operation.get("source"), root)
        destination = resolve_destination(raw_operation.get("destination"), root, allowed_roots)
        if source in seen_sources:
            raise PlanError(f"duplicate source: {source}")
        if destination in seen_destinations:
            raise PlanError(f"duplicate destination: {destination}")
        seen_sources.add(source)
        seen_destinations.add(destination)

        if not source.exists():
            raise PlanError(f"source does not exist: {source}")
        if source.is_symlink() or not source.is_file():
            raise PlanError(f"source is not a regular non-symlink file: {source}")
        if source == destination:
            raise PlanError(f"operation is a no-op: {source}")
        if destination.exists():
            raise PlanError(f"destination already exists: {destination}")
        if source in seen_destinations:
            raise PlanError(f"a destination is also an earlier source, which is unsupported: {source}")
        if destination in seen_sources:
            raise PlanError(f"a destination is also a source, which is unsupported: {destination}")

        renamed = source.name != destination.name
        moved = source.parent != destination.parent
        if mode == "organize" and renamed:
            raise PlanError(f"organize mode cannot rename: {source.name} -> {destination.name}")
        if mode == "rename-only" and moved:
            raise PlanError(f"rename-only mode cannot move between directories: {source} -> {destination}")
        if renamed and extension(source) != extension(destination):
            raise PlanError(f"rename must preserve extension: {source.name} -> {destination.name}")
        if renamed and is_protected_rename(source):
            raise PlanError(f"protected or versioned file cannot be renamed: {source.name}")

        confidence = raw_operation.get("confidence")
        if confidence is not None and (not isinstance(confidence, (int, float)) or isinstance(confidence, bool) or not 0 <= confidence <= 1):
            raise PlanError(f"operation {index} confidence must be between 0 and 1")

        operations.append(
            {
                "source": source,
                "destination": destination,
                "reason": str(raw_operation.get("reason", "")).strip(),
                "confidence": confidence,
            }
        )
    return root, mode, operations, allowed_roots


def relative_or_absolute(path: Path, root: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return str(path)


def print_preview(root: Path, mode: str, operations: list[dict[str, Any]], action: str) -> None:
    print(f"{action} preview: {len(operations)} operation(s)")
    print(f"root: {root}")
    print(f"mode: {mode}")
    for index, operation in enumerate(operations, start=1):
        source = relative_or_absolute(operation["source"], root)
        destination = relative_or_absolute(operation["destination"], root)
        reason = f" — {operation['reason']}" if operation.get("reason") else ""
        print(f"{index}. {source} -> {destination}{reason}")


def default_manifest_path(root: Path) -> Path:
    stamp = datetime.now(tz=timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return root / ".sorty-organizer-history" / f"{stamp}.json"


def execute_plan(root: Path, mode: str, operations: list[dict[str, Any]], manifest_path: Path | None) -> Path:
    manifest = (manifest_path or default_manifest_path(root)).expanduser().resolve(strict=False)
    if manifest.exists():
        raise PlanError(f"manifest already exists: {manifest}")
    temporary_manifest = manifest.with_name(f".{manifest.name}.{os.getpid()}.tmp")
    if temporary_manifest.exists():
        raise PlanError(f"temporary manifest already exists: {temporary_manifest}")

    moved: list[dict[str, Any]] = []
    created_directories: list[Path] = []
    try:
        manifest.parent.mkdir(parents=True, exist_ok=True)
        temporary_manifest.touch(exist_ok=False)
        for operation in operations:
            destination_parent = operation["destination"].parent
            missing: list[Path] = []
            cursor = destination_parent
            while not cursor.exists():
                missing.append(cursor)
                cursor = cursor.parent
            if not cursor.is_dir():
                raise PlanError(f"destination parent resolves through a non-directory: {cursor}")
            destination_parent.mkdir(parents=True, exist_ok=True)
            created_directories.extend(reversed(missing))
            shutil.move(str(operation["source"]), str(operation["destination"]))
            moved.append(operation)

        payload = {
            "version": 1,
            "kind": "sorty-organizer-manifest",
            "root": str(root),
            "mode": mode,
            "executed_at": datetime.now(tz=timezone.utc).isoformat(),
            "operations": [
                {
                    "source": str(operation["source"]),
                    "destination": str(operation["destination"]),
                    "reason": operation["reason"],
                }
                for operation in moved
            ],
            "created_directories": [str(path) for path in created_directories],
        }
        temporary_manifest.write_text(
            json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        os.replace(temporary_manifest, manifest)
    except Exception as error:
        rollback_errors: list[str] = []
        for operation in reversed(moved):
            try:
                if operation["destination"].exists() and not operation["source"].exists():
                    operation["source"].parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(str(operation["destination"]), str(operation["source"]))
            except Exception as rollback_error:
                rollback_errors.append(str(rollback_error))
        try:
            temporary_manifest.unlink(missing_ok=True)
        except OSError as cleanup_error:
            rollback_errors.append(str(cleanup_error))
        for directory in sorted(created_directories, key=lambda path: len(path.parts), reverse=True):
            try:
                directory.rmdir()
            except OSError:
                pass
        detail = f"; rollback errors: {'; '.join(rollback_errors)}" if rollback_errors else ""
        raise PlanError(f"apply failed and completed moves were rolled back: {error}{detail}") from error
    return manifest


def validate_undo(manifest: dict[str, Any]) -> tuple[Path, list[dict[str, Path]], list[Path]]:
    if manifest.get("version") != 1 or manifest.get("kind") != "sorty-organizer-manifest":
        raise PlanError("unsupported undo manifest")
    raw_root = manifest.get("root")
    if not isinstance(raw_root, str) or not Path(raw_root).is_absolute():
        raise PlanError("manifest root must be absolute")
    root = Path(raw_root).expanduser().resolve(strict=False)
    raw_operations = manifest.get("operations")
    if not isinstance(raw_operations, list):
        raise PlanError("manifest operations must be an array")

    operations: list[dict[str, Path]] = []
    for index, raw_operation in enumerate(reversed(raw_operations), start=1):
        if not isinstance(raw_operation, dict):
            raise PlanError(f"undo operation {index} must be an object")
        source = Path(str(raw_operation.get("source", ""))).expanduser().resolve(strict=False)
        destination = Path(str(raw_operation.get("destination", ""))).expanduser().resolve(strict=False)
        if not destination.exists() or destination.is_symlink() or not destination.is_file():
            raise PlanError(f"current destination is missing or unsafe: {destination}")
        if source.exists():
            raise PlanError(f"original source path is occupied: {source}")
        operations.append({"source": destination, "destination": source})

    created = [
        Path(str(path)).expanduser().resolve(strict=False)
        for path in manifest.get("created_directories", [])
        if isinstance(path, str)
    ]
    return root, operations, created


def execute_undo(operations: list[dict[str, Path]], created_directories: list[Path]) -> None:
    restored: list[dict[str, Path]] = []
    try:
        for operation in operations:
            operation["destination"].parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(operation["source"]), str(operation["destination"]))
            restored.append(operation)
    except Exception as error:
        rollback_errors: list[str] = []
        for operation in reversed(restored):
            try:
                if operation["destination"].exists() and not operation["source"].exists():
                    operation["source"].parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(str(operation["destination"]), str(operation["source"]))
            except Exception as rollback_error:
                rollback_errors.append(str(rollback_error))
        detail = f"; rollback errors: {'; '.join(rollback_errors)}" if rollback_errors else ""
        raise PlanError(f"undo failed and restored moves were reversed: {error}{detail}") from error

    for directory in sorted(created_directories, key=lambda path: len(path.parts), reverse=True):
        try:
            directory.rmdir()
        except OSError:
            pass


def main() -> int:
    args = parse_args()
    try:
        if args.undo:
            if args.plan:
                raise PlanError("provide either a plan or --undo, not both")
            manifest = load_json(args.undo)
            root, operations, created_directories = validate_undo(manifest)
            print_preview(root, "undo", operations, "undo")
            if not args.execute:
                print("validated; no files changed (pass --execute after approval)")
                return 0
            execute_undo(operations, created_directories)
            print(f"undo complete: {len(operations)} operation(s)")
            return 0

        if not args.plan:
            raise PlanError("a plan path is required unless --undo is used")
        plan = load_json(args.plan)
        root, mode, operations, _ = validate_plan(plan, args.allow_destination_root)
        print_preview(root, mode, operations, "apply")
        if not args.execute:
            print("validated; no files changed (pass --execute after approval)")
            return 0
        manifest = execute_plan(root, mode, operations, args.manifest)
        print(f"apply complete: {len(operations)} operation(s)")
        print(f"undo manifest: {manifest}")
        return 0
    except PlanError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
