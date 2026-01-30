#!/bin/bash
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

print_header "${PROJECT_NAME} Build" 50

VERSION=$(get_version)
BUILD_NUM=$(get_build_number)

# Build method: "spm" (default for local) or "xcodebuild" (for CI releases)
BUILD_METHOD="${BUILD_METHOD:-spm}"

print_summary "Build Configuration" \
    "Version" "${VERSION}" \
    "Build" "${BUILD_NUM}" \
    "Scheme" "${SCHEME}" \
    "Method" "${BUILD_METHOD}" \
    "Output" "${BUILD_DIR}"

# Cleanup and setup
rm -rf "${BUILD_DIR}" || true
mkdir -p "${BUILD_DIR}"
mkdir -p "${RELEASE_DIR}"

# Binary and App names from config if needed, or hardcoded for reliability
BINARY_NAME="SortyApp"
APP_BUNDLE="Sorty.app"

TOTAL_STEPS=4

# Build configuration
BUILD_CONFIG="${BUILD_CONFIG:-release}"
log_item "Configuration: ${BUILD_CONFIG}"

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

# Inject Git Info
"${SCRIPT_DIR}/inject_git_info.sh" "${PROJECT_DIR}/Resources"

print_step 2 $TOTAL_STEPS "Compiling Project"
start_step_timer "build"

if [ "$BUILD_METHOD" = "xcodebuild" ]; then
    # Use xcodebuild for CI releases - ensures proper SDK targeting and deployment target
    XCODE_CONFIG="Release"
    if [ "$BUILD_CONFIG" = "debug" ]; then
        XCODE_CONFIG="Debug"
    fi
    
    log_item "Using xcodebuild with configuration: ${XCODE_CONFIG}"
    
    # Build with xcodebuild using the Xcode project
    # -destination ensures we build for macOS with proper SDK
    if ! xcodebuild -project "${PROJECT_DIR}/Sorty.xcodeproj" \
        -scheme "FileOrganiser" \
        -configuration "${XCODE_CONFIG}" \
        -destination "generic/platform=macOS" \
        -derivedDataPath "${BUILD_DIR}/DerivedData" \
        INFOPLIST_FILE="${PROJECT_DIR}/Info.plist" \
        PRODUCT_BUNDLE_IDENTIFIER="com.sorty.app" \
        PRODUCT_NAME="Sorty" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        clean build 2>&1 | tail -50; then
        log_failure "xcodebuild failed"
        exit 1
    fi
    
    # Find the built app in DerivedData
    BUILT_APP=$(find "${BUILD_DIR}/DerivedData" -name "*.app" -type d | head -1)
    if [ -z "$BUILT_APP" ]; then
        log_failure "Built app not found in DerivedData"
        exit 1
    fi
    
    # Copy to release directory
    rm -rf "${APP_PATH}"
    cp -R "$BUILT_APP" "${APP_PATH}"
    
    log_success "xcodebuild succeeded ($(get_step_duration "build"))"
    
    # Skip assembly step for xcodebuild - app is already complete
    print_step 3 $TOTAL_STEPS "Verifying App Bundle"
    start_step_timer "assemble"
    
    if [ ! -d "${APP_PATH}" ]; then
        log_failure "App bundle not found at ${APP_PATH}"
        exit 1
    fi
    log_success "App bundle verified ($(get_step_duration "assemble"))"
else
    # Use swift build (SPM) for local development
    if ! swift build -c "${BUILD_CONFIG}"; then
        log_failure "Compilation failed"
        exit 1
    fi
    BIN_PATH=$(swift build -c "${BUILD_CONFIG}" --show-bin-path)
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

    # Copy SPM resource bundle (required for Bundle.module to work)
    SPM_BUNDLE_PATH="${BIN_PATH}/Sorty_SortyLib.bundle"
    if [ -d "${SPM_BUNDLE_PATH}" ]; then
        cp -R "${SPM_BUNDLE_PATH}" "${RESOURCES_DIR}/"
        log_item "Copied SPM resource bundle"
    else
        log_item "Warning: SPM resource bundle not found at ${SPM_BUNDLE_PATH}"
    fi

    # Copy Images folder directly for Bundle.main fallback (ensures icons work in distributed builds)
    IMAGES_SRC="${PROJECT_DIR}/Sources/SortyLib/Resources/Images"
    if [ -d "${IMAGES_SRC}" ]; then
        cp -R "${IMAGES_SRC}" "${RESOURCES_DIR}/"
        log_item "Copied Images folder to Resources"
    fi

    log_success "App bundle assembled ($(get_step_duration "assemble"))"
fi

# Step 4: Signing (common for both build methods)
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
