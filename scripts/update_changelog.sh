#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

NEW_VERSION=$1

if [ -z "$NEW_VERSION" ]; then
    log_failure "Usage: $0 <version>"
    exit 1
fi

CHANGELOG_FILE="${PROJECT_DIR}/CHANGELOG.md"
DATE=$(date +%Y-%m-%d)

print_header "Updating Changelog for ${NEW_VERSION}" 50

if [ ! -f "$CHANGELOG_FILE" ]; then
    log_failure "$CHANGELOG_FILE not found."
    exit 1
fi

# Determine if this is a pre-release
RELEASE_TYPE=""
if [[ "$NEW_VERSION" == *"beta"* ]] || [[ "$NEW_VERSION" == *"alpha"* ]]; then
    RELEASE_TYPE=" (Pre-release)"
fi

# Insert new version header after the [Unreleased] section or at top if not present
# This simple version assumes a standard format.
# It inserts the new version below [Unreleased] if it exists, or at the top.

# We will use a temporary file to construct the new content
TEMP_FILE=$(mktemp)

# Check if [Unreleased] exists
if grep -q "## \[Unreleased\]" "$CHANGELOG_FILE"; then
    # Insert after [Unreleased] link or header
    awk -v version="$NEW_VERSION" -v date="$DATE" -v type="$RELEASE_TYPE" '
    /## \[Unreleased\]/ {
        print $0
        print ""
        print "## [" version "] - " date type
        next
    }
    { print }
    ' "$CHANGELOG_FILE" > "$TEMP_FILE"
else
    # Prepend to file
    echo "## [$NEW_VERSION] - $DATE$RELEASE_TYPE" > "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
    cat "$CHANGELOG_FILE" >> "$TEMP_FILE"
fi

mv "$TEMP_FILE" "$CHANGELOG_FILE"
log_success "CHANGELOG.md updated"
