#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

export SKIP_TESTS=true
# Unset credentials to skip automatic notarization if desired, 
# or keep them if quick release just means "skip tests".
# Usually quick release means "I want the binary now".
# We'll skip notarization to make it truly quick.

# Temporarily unset variables just for this run context if exported
export NOTARIZATION_USERNAME=""
export KEYCHAIN_PROFILE=""

echo "🚀 Starting Quick Release (Tests & Notarization Skipped)..."

"${SCRIPT_DIR}/release.sh"
