#!/usr/bin/env python3
"""Generate Markdown and HTML release notes for Sparkle appcasts."""

from __future__ import annotations

import argparse
import html
import os
import subprocess
from pathlib import Path


def git_lines(args: list[str]) -> list[str]:
    result = subprocess.run(
        ["git", *args],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return []
    return [line for line in result.stdout.splitlines() if line.strip()]


def commit_range(args: argparse.Namespace) -> tuple[str, str, str]:
    repository = os.environ.get("GITHUB_REPOSITORY", "sorty-organizer/Sorty")
    head = "".join(git_lines(["rev-parse", "HEAD"])) or "HEAD"
    if args.from_tag:
        baseline = args.from_tag
        return f"{baseline}..HEAD", f"https://github.com/{repository}/compare/{baseline}...{head}", baseline

    previous = "".join(git_lines(["rev-list", "-n", "1", "nightly"]))
    if previous:
        return f"{previous}..HEAD", f"https://github.com/{repository}/compare/{previous}...{head}", previous[:7]
    return f"HEAD~{args.fallback_count}..HEAD", f"https://github.com/{repository}/commit/{head}", f"last {args.fallback_count} commits"


def categorize(subject: str) -> str:
    lower = subject.lower()
    if any(token in lower for token in ("design", "tour", "what's new", "whats new", "ui", "settings")):
        return "User-facing changes"
    if any(token in lower for token in ("nightly", "appcast", "sparkle", "release", "ci:")):
        return "Update system"
    if lower.startswith(("fix:", "bug", "repair")):
        return "Fixes"
    return "Engineering"


def load_commits(range_spec: str) -> dict[str, list[tuple[str, str]]]:
    rows = git_lines(["log", range_spec, "--pretty=format:%h%x09%s", "--no-merges"])
    groups: dict[str, list[tuple[str, str]]] = {
        "User-facing changes": [],
        "Update system": [],
        "Fixes": [],
        "Engineering": [],
    }
    for row in rows:
        if "\t" not in row:
            continue
        short_hash, subject = row.split("\t", 1)
        groups[categorize(subject)].append((short_hash, subject))
    return {key: value for key, value in groups.items() if value}


def commit_url(short_hash: str) -> str:
    repository = os.environ.get("GITHUB_REPOSITORY", "sorty-organizer/Sorty")
    return f"https://github.com/{repository}/commit/{short_hash}"


def markdown(
    args: argparse.Namespace,
    groups: dict[str, list[tuple[str, str]]],
    compare_url: str,
    baseline_label: str,
) -> str:
    lines = [
        f"## {args.title}",
        "",
        "### Important: install this update from GitHub",
        "We revamped Sorty's update system to support nightly builds, so older updater builds may download this version and then fail during install. This manual install is safe: it uses the same signed GitHub release asset and gets you onto the fixed updater path.",
        "",
        "Please install this one manually: [download `Sorty-universal.zip` from GitHub](https://github.com/sorty-organizer/Sorty/releases/latest), quit Sorty, and replace your existing `Sorty.app` in `/Applications`. After this update is installed, future in-app updates should work normally again.",
        "",
        args.summary,
        "",
        "### TL;DR",
        "- This preview is available through the normal Sorty update flow.",
        "- Installing it does not opt you into future nightly builds.",
        "- Future nightly builds are controlled from Settings > Experimental > Nightly Updates.",
        "",
        f"Changes shown below are everything since `{baseline_label}`.",
        "",
    ]
    if groups:
        for heading, commits in groups.items():
            lines.append(f"### {heading}")
            for short_hash, subject in commits:
                lines.append(f"- {subject} ([`{short_hash}`]({commit_url(short_hash)}))")
            lines.append("")
    else:
        lines.extend(["### Changes", "- No user-facing commits since the previous nightly.", ""])

    lines.extend(
        [
            "### Update Channel",
            "Future nightly-only builds are more fragile and may include unfinished changes.",
            "Turn them on or off from Settings > Experimental > Nightly Updates.",
            "",
            f"Full change comparison: {compare_url}",
            "",
        ]
    )
    return "\n".join(lines)


def html_document(
    args: argparse.Namespace,
    groups: dict[str, list[tuple[str, str]]],
    compare_url: str,
    baseline_label: str,
) -> str:
    sections = []
    for heading, commits in groups.items():
        items = "".join(
            f'<li>{html.escape(subject)} <a class="hash" href="{html.escape(commit_url(short_hash))}">{html.escape(short_hash)}</a></li>'
            for short_hash, subject in commits
        )
        sections.append(f"<h2>{html.escape(heading)}</h2><ul>{items}</ul>")
    if not sections:
        sections.append("<h2>Changes</h2><ul><li>No user-facing commits since the previous nightly.</li></ul>")

    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(args.title)}</title>
  <style>
    :root {{ color-scheme: light dark; }}
    body {{ margin: 0; padding: 28px; font: -apple-system-body; color: CanvasText; background: Canvas; }}
    main {{ max-width: 720px; margin: 0 auto; }}
    h1 {{ font: -apple-system-title1; margin: 0 0 8px; }}
    h2 {{ font: -apple-system-headline; margin: 28px 0 10px; }}
    p {{ line-height: 1.45; opacity: 0.82; }}
    ul {{ margin: 0; padding-left: 22px; }}
    li {{ margin: 8px 0; line-height: 1.4; }}
    .manual-update {{ border: 1px solid rgba(45, 145, 150, 0.28); border-radius: 16px; padding: 16px 18px; margin: 0 0 22px; background: rgba(45, 145, 150, 0.12); }}
    .manual-update strong {{ display: block; font: -apple-system-headline; margin-bottom: 6px; }}
    .manual-update p {{ margin: 6px 0 0; opacity: 0.9; }}
    .callout {{ border: 1px solid rgba(128, 128, 128, 0.24); border-radius: 14px; padding: 14px 16px; background: rgba(128, 128, 128, 0.08); }}
    .hash {{ opacity: 0.62; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.88em; }}
    a {{ color: LinkText; }}
  </style>
</head>
<body>
  <main>
    <h1>{html.escape(args.title)}</h1>
    <div class="manual-update">
      <strong>Important: install this update from GitHub</strong>
      <p>We revamped Sorty's update system to support nightly builds, so older updater builds may download this version and then fail during install. This manual install is safe: it uses the same signed GitHub release asset and gets you onto the fixed updater path.</p>
      <p>Please install this one manually: <a href="https://github.com/sorty-organizer/Sorty/releases/latest"><strong>download Sorty-universal.zip from GitHub</strong></a>, quit Sorty, and replace your existing <strong>Sorty.app</strong> in <strong>/Applications</strong>. After this update is installed, future in-app updates should work normally again.</p>
    </div>
    <p>{html.escape(args.summary)}</p>
    <p>Changes shown below are everything since <span class="hash">{html.escape(baseline_label)}</span>.</p>
    <div class="callout">
      <strong>Update behavior:</strong> This preview is offered through the normal update channel. Installing it does not switch Sorty to future nightly builds unless you enable Nightly Updates in Settings &gt; Experimental.
    </div>
    <h2>TL;DR</h2>
    <ul>
      <li>This preview is available through the normal Sorty update flow.</li>
      <li>Installing it does not opt you into future nightly builds.</li>
      <li>Future nightly builds are controlled from Settings &gt; Experimental &gt; Nightly Updates.</li>
    </ul>
    {''.join(sections)}
    <h2>Update Channel</h2>
    <p>Turn future nightly builds on or off from Settings &gt; Experimental &gt; Nightly Updates.</p>
    <p><a href="{html.escape(compare_url)}">View the full change comparison</a></p>
  </main>
</body>
</html>
"""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--title", required=True)
    parser.add_argument("--summary", required=True)
    parser.add_argument("--markdown", required=True)
    parser.add_argument("--html", required=True)
    parser.add_argument("--from-tag", default="")
    parser.add_argument("--fallback-count", type=int, default=25)
    args = parser.parse_args()

    range_spec, compare_url, baseline_label = commit_range(args)
    groups = load_commits(range_spec)
    Path(args.markdown).write_text(markdown(args, groups, compare_url, baseline_label), encoding="utf-8")
    Path(args.html).write_text(html_document(args, groups, compare_url, baseline_label), encoding="utf-8")


if __name__ == "__main__":
    main()
