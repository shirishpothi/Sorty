#!/bin/bash
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

print_header "${PROJECT_NAME} Build" 50

VERSION=$(get_version)
BUILD_NUM=$(get_build_number)

print_summary "Build Configuration" \
    "Version" "${VERSION}" \
    "Build" "${BUILD_NUM}" \
    "Scheme" "${SCHEME}" \
    "Output" "${BUILD_DIR}"

# Cleanup and setup
rm -rf "${BUILD_DIR}" || true
mkdir -p "${BUILD_DIR}"
mkdir -p "${RELEASE_DIR}"

# Binary and App names from config if needed, or hardcoded for reliability
BINARY_NAME="SortyApp"
APP_BUNDLE="Sorty.app"

TOTAL_STEPS=4

if [ "$SKIP_TESTS" != "true" ]; then
    print_step 1 $TOTAL_STEPS "Running Unit Tests"
    start_step_timer "test"
    # Use quiet mode or pipe through a formatter if desired
    if ! swift test; then
        log_failure "Tests failed. Set SKIP_TESTS=true to bypass."
        exit 1
    fi
    log_success "Tests passed."
else
    print_step 1 $TOTAL_STEPS "Skipping Unit Tests"
    log_item "SKIP_TESTS is set."
fi

print_step 2 $TOTAL_STEPS "Compiling Project"
start_step_timer "build"

if ! swift build -c release; then
    log_failure "Compilation failed"
    exit 1
fi
BIN_PATH=$(swift build -c release --show-bin-path)
log_success "Compilation succeeded ($(get_step_duration "build"))"

print_step 3 $TOTAL_STEPS "Assembling App Bundle"
start_step_timer "assemble"

# Build structure
MACOS_DIR="${APP_PATH}/Contents/MacOS"
RESOURCES_DIR="${APP_PATH}/Contents/Resources"

rm -rf "${APP_PATH}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy binary
if [ -f "${BIN_PATH}/${BINARY_NAME}" ]; then
    cp "${BIN_PATH}/${BINARY_NAME}" "${MACOS_DIR}/"
else
    log_failure "Binary not found at ${BIN_PATH}/${BINARY_NAME}"
    exit 1
fi

# Copy Info.plist
if [ -f "${PROJECT_DIR}/Info.plist" ]; then
    cp "${PROJECT_DIR}/Info.plist" "${APP_PATH}/Contents/"
fi

# Copy Resources
if [ -d "${PROJECT_DIR}/Resources" ]; then
    cp -R "${PROJECT_DIR}/Resources/" "${RESOURCES_DIR}/"
fi

log_success "App bundle assembled ($(get_step_duration "assemble"))"

print_step 4 $TOTAL_STEPS "Ad-hoc Signing"
start_step_timer "sign"

codesign --force --deep --sign - "${APP_PATH}" 2>/dev/null || true
log_success "App signed ($(get_step_duration "sign"))"

APP_SIZE=$(get_file_size "${APP_PATH}")

echo ""
print_divider "═" 50
echo ""

print_summary "Build Complete ${SYM_SPARKLE}" \
    "App" "${APP_PATH}" \
    "Size" "${APP_SIZE}" \
    "Version" "${VERSION} (build ${BUILD_NUM})" \
    "Duration" "$(get_total_duration)"
