#!/usr/bin/env python3
"""Reject private PostHog credentials embedded in a packaged macOS app."""

from __future__ import annotations

import os
import pathlib
import re
import sys


PRIVATE_KEY_PATTERN = re.compile(rb"phx_[A-Za-z0-9_-]{20,}")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify_posthog_release_secrets.py <app-bundle>", file=sys.stderr)
        return 2

    app_bundle = pathlib.Path(sys.argv[1])
    if not app_bundle.is_dir():
        print(f"App bundle does not exist: {app_bundle}", file=sys.stderr)
        return 2

    configured_key = os.environ.get("POSTHOG_CLI_API_KEY", "").encode()
    for path in app_bundle.rglob("*"):
        if not path.is_file():
            continue
        try:
            contents = path.read_bytes()
        except OSError as error:
            print(f"Unable to inspect {path}: {error}", file=sys.stderr)
            return 2

        if PRIVATE_KEY_PATTERN.search(contents) or (
            configured_key and configured_key in contents
        ):
            print(
                f"Private PostHog credential found in release artifact: {path}",
                file=sys.stderr,
            )
            return 1

    print("Release artifact contains no private PostHog credentials.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
