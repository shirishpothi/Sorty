#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

print_header "Starting Release Process" 60

# --- Step 1: Build & Test ---
# This includes unit tests unless SKIP_TESTS=true
"${SCRIPT_DIR}/build.sh"

# --- Step 2: Package ---
"${SCRIPT_DIR}/package.sh"

# --- Step 3: Notarize (Optional) ---
if [ -n "$NOTARIZATION_USERNAME" ] || [ -n "$KEYCHAIN_PROFILE" ]; then
    "${SCRIPT_DIR}/notarize.sh"
else
    log_item "Skipping notarization (no credentials found)"
fi

# --- Step 4: Appcast (Optional) ---
if [ -f "${SCRIPT_DIR}/generate_appcast.sh" ]; then
    "${SCRIPT_DIR}/generate_appcast.sh"
fi

echo ""
log_success "Release workflow completed successfully!"
echo "Artifacts are in: ${RELEASE_DIR}"
