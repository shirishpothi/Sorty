#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

print_header "Starting Release Process" 60

# Default settings
RUN_UI_TESTS=false
RUN_UNIT_TESTS=false
RUN_CLI_TESTS=true # Always verify CLI basics unless skipped
SKIP_ALL_TESTS=false

# Argument Parsing
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --ui-tests)
        RUN_UI_TESTS=true
        RUN_UNIT_TESTS=true # Usually implies unit tests too
        shift
        ;;
        --skip-ui)
        RUN_UI_TESTS=false
        RUN_UNIT_TESTS=true
        shift
        ;;
        --no-tests)
        SKIP_ALL_TESTS=true
        shift
        ;;
        --cli-only)
        RUN_UI_TESTS=false
        RUN_UNIT_TESTS=false
        RUN_CLI_TESTS=true
        shift
        ;;
        *)
        echo "Unknown option: $1"
        echo "Usage: $0 [--ui-tests] [--skip-ui] [--no-tests] [--cli-only]"
        exit 1
        ;;
    esac
done

if [ "$SKIP_ALL_TESTS" == "true" ]; then
    export SKIP_TESTS=true
    log_warn "⚠️  Skipping ALL tests at user request."
else
    # Configure build script environment
    if [ "$RUN_UI_TESTS" == "true" ]; then
        export ENABLE_UI_TESTS=true
    else
        export ENABLE_UI_TESTS=false
    fi
    # Unit tests run by default in build.sh unless SKIP_TESTS is set
    # If cli-only, we might want to skip unit tests in build.sh
    if [ "$RUN_UNIT_TESTS" == "false" ] && [ "$RUN_CLI_TESTS" == "true" ]; then
         export SKIP_UNIT_TESTS=true
    fi
fi

# --- Step 1: Build & Test ---
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
