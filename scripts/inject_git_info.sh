#!/bin/bash
set -e

# Script to inject git commit info into the build
# Usage: ./inject_git_info.sh [OUTPUT_DIR]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${1:-$SCRIPT_DIR/../Resources}"

mkdir -p "$OUTPUT_DIR"

# Get commit hash
if command -v git &> /dev/null && git rev-parse --is-inside-work-tree &> /dev/null; then
    COMMIT_HASH=$(git rev-parse HEAD)
else
    COMMIT_HASH="unknown"
    echo "Warning: Git not found or not in a git repo. Using 'unknown'."
fi

# Write to file
echo "$COMMIT_HASH" > "$OUTPUT_DIR/commit.txt"
echo "Injected commit hash: $COMMIT_HASH into $OUTPUT_DIR/commit.txt"
