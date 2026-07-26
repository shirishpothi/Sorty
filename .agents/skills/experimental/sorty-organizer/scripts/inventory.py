#!/usr/bin/env python3
"""Create a read-only JSON inventory for a Sorty-style organization plan."""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import stat
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_EXCLUDED_DIRECTORIES = {
    ".git",
    ".hg",
    ".svn",
    ".sorty-organizer-history",
    ".Spotlight-V100",
    ".TemporaryItems",
    ".Trashes",
    "__pycache__",
    "DerivedData",
    "node_modules",
}

DEFAULT_EXCLUDED_FILES = {
    ".DS_Store",
    "Thumbs.db",
    "desktop.ini",
}

TYPE_EXTENSIONS = {
    "image": {"ai", "bmp", "dng", "gif", "heic", "heif", "ico", "jpeg", "jpg", "png", "psd", "raw", "svg", "tif", "tiff", "webp"},
    "video": {"3gp", "avi", "flv", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "webm", "wmv"},
    "audio": {"aac", "aiff", "alac", "flac", "m4a", "mid", "midi", "mp3", "ogg", "wav", "wma"},
    "document": {"csv", "doc", "docx", "epub", "key", "keynote", "markdown", "md", "numbers", "odp", "ods", "odt", "pages", "pdf", "ppt", "pptx", "rtf", "txt", "xls", "xlsx"},
    "archive": {"7z", "bz2", "dmg", "gz", "iso", "pkg", "rar", "tar", "xz", "zip"},
    "code": {"c", "cpp", "css", "go", "h", "hpp", "html", "java", "js", "json", "kt", "m", "mm", "php", "py", "rb", "rs", "scala", "sh", "sql", "swift", "toml", "ts", "xml", "yaml", "yml", "zsh"},
    "font": {"eot", "otf", "ttf", "woff", "woff2"},
    "database": {"accdb", "db", "mdb", "realm", "sqlite", "sqlite3"},
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path, help="Folder to inventory")
    parser.add_argument("--output", type=Path, help="Write JSON to this path instead of stdout")
    parser.add_argument("--exclude", action="append", default=[], metavar="GLOB", help="Exclude a relative path or basename glob; repeatable")
    parser.add_argument("--include-hidden", action="store_true", help="Include hidden files and folders")
    parser.add_argument("--max-depth", type=int, default=20, help="Maximum directory depth to traverse")
    parser.add_argument("--hash-duplicates", action="store_true", help="SHA-256 only files sharing the same byte size")
    return parser.parse_args()


def iso_timestamp(epoch_seconds: float) -> str:
    return datetime.fromtimestamp(epoch_seconds, tz=timezone.utc).isoformat()


def file_category(suffix: str) -> str:
    extension = suffix.removeprefix(".").lower()
    for category, extensions in TYPE_EXTENSIONS.items():
        if extension in extensions:
            return category
    return "other"


def matches_glob(relative_path: str, name: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(relative_path, pattern) or fnmatch.fnmatch(name, pattern) for pattern in patterns)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    args = parse_args()
    root = args.root.expanduser().resolve()
    if not root.is_dir():
        print(f"error: root is not a directory: {root}", file=sys.stderr)
        return 2
    if args.max_depth < 0:
        print("error: --max-depth must be non-negative", file=sys.stderr)
        return 2

    files: list[dict[str, Any]] = []
    directories: list[str] = []
    skipped: list[dict[str, str]] = []
    paths_by_size: dict[int, list[Path]] = defaultdict(list)

    def walk(directory: Path, depth: int) -> None:
        if depth > args.max_depth:
            skipped.append({"path": directory.relative_to(root).as_posix(), "reason": "maximum depth exceeded"})
            return
        try:
            entries = sorted(os.scandir(directory), key=lambda entry: entry.name.casefold())
        except OSError as error:
            skipped.append({"path": directory.relative_to(root).as_posix(), "reason": f"unreadable: {error}"})
            return

        for entry in entries:
            path = Path(entry.path)
            relative = path.relative_to(root).as_posix()
            hidden = entry.name.startswith(".")
            if matches_glob(relative, entry.name, args.exclude):
                skipped.append({"path": relative, "reason": "matched exclusion glob"})
                continue
            if entry.is_symlink():
                skipped.append({"path": relative, "reason": "symbolic link"})
                continue
            if entry.is_dir(follow_symlinks=False):
                if entry.name in DEFAULT_EXCLUDED_DIRECTORIES:
                    skipped.append({"path": relative, "reason": "protected directory"})
                    continue
                if hidden and not args.include_hidden:
                    skipped.append({"path": relative, "reason": "hidden directory"})
                    continue
                directories.append(relative)
                walk(path, depth + 1)
                continue
            if not entry.is_file(follow_symlinks=False):
                skipped.append({"path": relative, "reason": "not a regular file"})
                continue
            if entry.name in DEFAULT_EXCLUDED_FILES:
                skipped.append({"path": relative, "reason": "system file"})
                continue
            if hidden and not args.include_hidden:
                skipped.append({"path": relative, "reason": "hidden file"})
                continue

            try:
                metadata = entry.stat(follow_symlinks=False)
            except OSError as error:
                skipped.append({"path": relative, "reason": f"unreadable metadata: {error}"})
                continue
            if not stat.S_ISREG(metadata.st_mode):
                skipped.append({"path": relative, "reason": "not a regular file"})
                continue

            suffix = path.suffix
            item = {
                "path": relative,
                "name": entry.name,
                "extension": suffix.removeprefix(".").lower(),
                "category": file_category(suffix),
                "size_bytes": metadata.st_size,
                "created_at": iso_timestamp(metadata.st_birthtime if hasattr(metadata, "st_birthtime") else metadata.st_ctime),
                "modified_at": iso_timestamp(metadata.st_mtime),
            }
            files.append(item)
            paths_by_size[metadata.st_size].append(path)

    walk(root, 0)

    duplicate_groups: list[dict[str, Any]] = []
    if args.hash_duplicates:
        for size, candidates in sorted(paths_by_size.items()):
            if len(candidates) < 2:
                continue
            by_hash: dict[str, list[Path]] = defaultdict(list)
            for candidate in candidates:
                try:
                    by_hash[sha256(candidate)].append(candidate)
                except OSError as error:
                    skipped.append({"path": candidate.relative_to(root).as_posix(), "reason": f"hash failed: {error}"})
            for digest, matching_paths in sorted(by_hash.items()):
                if len(matching_paths) > 1:
                    duplicate_groups.append(
                        {
                            "sha256": digest,
                            "size_bytes": size,
                            "paths": [path.relative_to(root).as_posix() for path in matching_paths],
                        }
                    )

    payload = {
        "schema_version": 1,
        "root": str(root),
        "generated_at": datetime.now(tz=timezone.utc).isoformat(),
        "options": {
            "include_hidden": args.include_hidden,
            "max_depth": args.max_depth,
            "exclusions": args.exclude,
            "hashed_duplicate_candidates": args.hash_duplicates,
        },
        "directories": directories,
        "files": files,
        "skipped": skipped,
        "exact_duplicate_groups": duplicate_groups,
    }
    encoded = json.dumps(payload, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        args.output.expanduser().write_text(encoded, encoding="utf-8")
    else:
        sys.stdout.write(encoded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
