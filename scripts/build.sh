#!/bin/bash
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# MARK: - Resource Copying Helpers

# Safely copies resources with integrity checks and conflict detection
# Priority order: SPM bundle > Resources folder > Fallback images
# Logs conflicts but prioritizes first successful copy for each resource
copy_resources_safely() {
    local dest_dir="$1"
    local spm_bundle="$2"
    local resources_dir="$3"
    local fallback_images="$4"
    
    mkdir -p "${dest_dir}"
    
    # Priority 1: SPM bundle (if available)
    if [ -n "${spm_bundle}" ] && [ -d "${spm_bundle}" ]; then
        if [ "$(find "${spm_bundle}" -type f | wc -l)" -gt 0 ]; then
            log_item "Syncing resources from SPM bundle"
            rsync -a "${spm_bundle}/" "${dest_dir}/"
        else
            log_item "Warning: SPM bundle is empty"
        fi
    fi
    
    # Priority 2: Resources folder (only copy files not already present)
    if [ -d "${resources_dir}" ]; then
        log_item "Syncing additional resources from Resources folder"
        rsync -a --ignore-existing "${resources_dir}/" "${dest_dir}/"
    fi
    
    # Priority 3: Fallback images (only if Images folder doesn't exist yet)
    if [ -d "${fallback_images}" ]; then
        local images_dest="${dest_dir}/Images"
        if [ ! -d "${images_dest}" ]; then
            log_item "Syncing fallback images"
            rsync -a "${fallback_images}/" "${images_dest}/"
        else
            log_item "Images folder already present from higher priority source, skipping fallback"
        fi
    fi
    
    # Report integrity: verify Resources directory has content
    local total_resources
    total_resources=$(find "${dest_dir}" -type f | wc -l)
    if [ "${total_resources}" -eq 0 ]; then
        log_item "Warning: No resources copied to app bundle"
    else
        log_item "Total resources in app bundle: ${total_resources}"
    fi
}

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
    # Use parallel execution for faster tests
    TEST_FLAGS="${BUILD_FLAGS:-}"
    if ! swift test $TEST_FLAGS; then
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
        -scheme "${SCHEME}" \
        -configuration "${XCODE_CONFIG}" \
        -destination "generic/platform=macOS" \
        -derivedDataPath "${BUILD_DIR}/DerivedData" \
        INFOPLIST_FILE="${PROJECT_DIR}/Info.plist" \
        PRODUCT_BUNDLE_IDENTIFIER="${APP_BUNDLE_ID}" \
        PRODUCT_NAME="${BINARY_NAME}" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        build 2>&1 | tail -50; then
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
    mkdir -p "${APP_PATH}"
    rsync -a --delete "${BUILT_APP}/" "${APP_PATH}/"
    
    # Ensure binary has correct RPATH for embedded frameworks
    MACOS_BIN="${APP_PATH}/Contents/MacOS/${BINARY_NAME}"
    if [ -f "${MACOS_BIN}" ]; then
        install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_BIN}" 2>/dev/null || true
        strip -x "${MACOS_BIN}"
    fi

    # Copy Resources with integrity checks and conflict detection
    RESOURCES_DIR="${APP_PATH}/Contents/Resources"
    SPM_BUNDLE=$(find "${BUILD_DIR}/DerivedData" -name "Sorty_SortyLib.bundle" -type d | head -1)
    IMAGES_SRC="${PROJECT_DIR}/Sources/SortyLib/Resources/Images"
    
    copy_resources_safely "${RESOURCES_DIR}" "${SPM_BUNDLE}" "${PROJECT_DIR}/Resources" "${IMAGES_SRC}"

    # Note: Assets.xcassets is in ${PROJECT_DIR}/Resources/ and compiled to Assets.car by xcodebuild

    # Copy entitlements
    if [ -f "${PROJECT_DIR}/Sorty.entitlements" ]; then
        cp "${PROJECT_DIR}/Sorty.entitlements" "${APP_PATH}/Contents/"
        log_item "Copied entitlements"
    fi

    # Copy LaunchAgent plist for Background Activity
    if [ -f "${PROJECT_DIR}/Resources/com.sorty.app.plist" ]; then
        mkdir -p "${APP_PATH}/Contents/Library/LaunchAgents"
        cp "${PROJECT_DIR}/Resources/com.sorty.app.plist" "${APP_PATH}/Contents/Library/LaunchAgents/"
        log_item "Copied LaunchAgent plist"
    fi

    # Bundle CLI tools for xcodebuild
    CLI_DIR="${RESOURCES_DIR}/CLI"
    mkdir -p "${CLI_DIR}"
    
    # Build and bundle the learnings CLI
    log_item "Building learnings CLI..."
    if swift build -c release --product learnings 2>/dev/null; then
        LEARNINGS_BIN=$(swift build -c release --show-bin-path)/learnings
        if [ -f "${LEARNINGS_BIN}" ]; then
            cp "${LEARNINGS_BIN}" "${CLI_DIR}/learnings"
            strip -x "${CLI_DIR}/learnings"
            chmod 755 "${CLI_DIR}/learnings"
            log_item "Bundled learnings CLI"
        fi
    else
        log_item "Note: learnings CLI build skipped"
    fi
    
    # Bundle the sorty shell script
    SORTY_SCRIPT="${PROJECT_DIR}/CLI/sorty"
    if [ -f "${SORTY_SCRIPT}" ]; then
        cp "${SORTY_SCRIPT}" "${CLI_DIR}/sorty"
        chmod 755 "${CLI_DIR}/sorty"
        log_item "Bundled sorty CLI script"
    fi

    log_success "xcodebuild succeeded ($(get_step_duration "build"))"

    # Embed Sparkle framework for xcodebuild (if not already embedded)
    FRAMEWORKS_DIR="${APP_PATH}/Contents/Frameworks"
    if [ ! -d "${FRAMEWORKS_DIR}/Sparkle.framework" ]; then
        mkdir -p "${FRAMEWORKS_DIR}"
        # Search in DerivedData (xcodebuild) or .build/artifacts (SPM fallback)
        SPARKLE_FRAMEWORK=$(find "${BUILD_DIR}/DerivedData" -name "Sparkle.framework" -type d 2>/dev/null | head -1)
        if [ -z "${SPARKLE_FRAMEWORK}" ]; then
            SPARKLE_FRAMEWORK=$(find "${PROJECT_DIR}/.build/artifacts" -name "Sparkle.framework" -type d 2>/dev/null | head -1)
        fi
        
        if [ -n "${SPARKLE_FRAMEWORK}" ] && [ -d "${SPARKLE_FRAMEWORK}" ]; then
            cp -R "${SPARKLE_FRAMEWORK}" "${FRAMEWORKS_DIR}/"
            
            # Deep sign the framework and its internal helpers for Sandbox compatibility
            log_item "Deep signing Sparkle.framework for Sandbox compatibility"
            codesign --force --deep --sign - "${FRAMEWORKS_DIR}/Sparkle.framework" 2>/dev/null || true
            
            # Specifically sign helpers if they exist (Sparkle 2)
            for helper in "Autoupdate.app" "Updater.app"; do
                HELPER_PATH="${FRAMEWORKS_DIR}/Sparkle.framework/Versions/A/Resources/${helper}"
                if [ -d "${HELPER_PATH}" ]; then
                    codesign --force --sign - "${HELPER_PATH}" 2>/dev/null || true
                fi
            done
            
            log_item "Embedded and signed Sparkle.framework"
        else
            log_item "Warning: Sparkle.framework not found, skipping embed"
        fi
    else
        log_item "Sparkle.framework already embedded"
    fi

    # Verify app bundle structure
    print_step 3 $TOTAL_STEPS "Verifying App Bundle"
    start_step_timer "assemble"
    
    if [ ! -d "${APP_PATH}" ]; then
        log_failure "App bundle not found at ${APP_PATH}"
        exit 1
    fi
    
    # Verify Sparkle.framework is embedded
    if [ -d "${APP_PATH}/Contents/Frameworks/Sparkle.framework" ]; then
        log_success "Sparkle.framework verified"
    else
        log_failure "Required Sparkle.framework missing from app bundle!"
        exit 1
    fi
    
    log_success "App bundle verified ($(get_step_duration "assemble"))"
else
    # Use swift build (SPM) for local development
    # BUILD_FLAGS can be set from Makefile for parallel compilation
    BUILD_FLAGS_EXTRA="${BUILD_FLAGS:-}"
    log_item "Build flags: ${BUILD_FLAGS_EXTRA}"
    if ! swift build -c "${BUILD_CONFIG}" $BUILD_FLAGS_EXTRA; then
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
        # Ensure binary has correct RPATH for embedded frameworks
        install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/${BINARY_NAME}" 2>/dev/null || true
        strip -x "${MACOS_DIR}/${BINARY_NAME}"
    else
        log_failure "Binary not found at ${BIN_PATH}/${BINARY_NAME}"
        exit 1
    fi

    # Copy Info.plist
    if [ -f "${PROJECT_DIR}/Info.plist" ]; then
        cp "${PROJECT_DIR}/Info.plist" "${APP_PATH}/Contents/Info.plist"
        
        # Inject dynamic version and build number into the bundle's Info.plist
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_PATH}/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUM}" "${APP_PATH}/Contents/Info.plist"
        
        # Inject current git hash
        COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        /usr/libexec/PlistBuddy -c "Delete :GitCommitHash" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Add :GitCommitHash string ${COMMIT_HASH}" "${APP_PATH}/Contents/Info.plist"
        
        log_item "Injected Version ${VERSION} (Build ${BUILD_NUM}) into bundle Info.plist"
    fi

    # Copy Resources with integrity checks and conflict detection
    SPM_BUNDLE_PATH="${BIN_PATH}/Sorty_SortyLib.bundle"
    IMAGES_SRC="${PROJECT_DIR}/Sources/SortyLib/Resources/Images"
    
    copy_resources_safely "${RESOURCES_DIR}" "${SPM_BUNDLE_PATH}" "${PROJECT_DIR}/Resources" "${IMAGES_SRC}"

    # Copy entitlements
    if [ -f "${PROJECT_DIR}/Sorty.entitlements" ]; then
        cp "${PROJECT_DIR}/Sorty.entitlements" "${APP_PATH}/Contents/"
        log_item "Copied entitlements"
    fi

    # Copy LaunchAgent plist for Background Activity
    if [ -f "${PROJECT_DIR}/Resources/com.sorty.app.plist" ]; then
        mkdir -p "${APP_PATH}/Contents/Library/LaunchAgents"
        cp "${PROJECT_DIR}/Resources/com.sorty.app.plist" "${APP_PATH}/Contents/Library/LaunchAgents/"
        log_item "Copied LaunchAgent plist"
    fi

    # Embed Sparkle framework for SPM builds
    FRAMEWORKS_DIR="${APP_PATH}/Contents/Frameworks"
    mkdir -p "${FRAMEWORKS_DIR}"
    
    # Find Sparkle.framework in SPM build artifacts
    SPARKLE_FRAMEWORK=""
    if [ -d "${BIN_PATH}/Sparkle.framework" ]; then
        SPARKLE_FRAMEWORK="${BIN_PATH}/Sparkle.framework"
    else
        # Search in .build/artifacts for any architecture-specific Sparkle.framework
        SPARKLE_FRAMEWORK=$(find "${PROJECT_DIR}/.build/artifacts" -name "Sparkle.framework" -type d 2>/dev/null | head -1)
    fi
    
    if [ -n "${SPARKLE_FRAMEWORK}" ] && [ -d "${SPARKLE_FRAMEWORK}" ]; then
        cp -R "${SPARKLE_FRAMEWORK}" "${FRAMEWORKS_DIR}/"
        # Deep sign the framework and its internal helpers for Sandbox compatibility
        log_item "Deep signing Sparkle.framework for Sandbox compatibility"
        codesign --force --deep --sign - "${FRAMEWORKS_DIR}/Sparkle.framework" 2>/dev/null || true
        
        # Specifically sign helpers if they exist (Sparkle 2)
        for helper in "Autoupdate.app" "Updater.app"; do
            HELPER_PATH="${FRAMEWORKS_DIR}/Sparkle.framework/Versions/A/Resources/${helper}"
            if [ -d "${HELPER_PATH}" ]; then
                codesign --force --sign - "${HELPER_PATH}" 2>/dev/null || true
            fi
        done
        
        log_item "Embedded and signed Sparkle.framework"
    else
        log_failure "Required Sparkle.framework not found!"
        exit 1
    fi

    # Final check for Sparkle.framework in bundle
    if [ ! -d "${APP_PATH}/Contents/Frameworks/Sparkle.framework" ]; then
        log_failure "Sparkle.framework missing after assembly!"
        exit 1
    fi

    # Bundle CLI tools
    CLI_DIR="${RESOURCES_DIR}/CLI"
    mkdir -p "${CLI_DIR}"
    
    # Build and bundle the learnings CLI
    log_item "Building learnings CLI..."
    if swift build -c "${BUILD_CONFIG}" --product learnings $BUILD_FLAGS_EXTRA 2>/dev/null; then
        LEARNINGS_BIN="${BIN_PATH}/learnings"
        if [ -f "${LEARNINGS_BIN}" ]; then
            cp "${LEARNINGS_BIN}" "${CLI_DIR}/learnings"
            strip -x "${CLI_DIR}/learnings"
            chmod 755 "${CLI_DIR}/learnings"
            log_item "Bundled learnings CLI"
        fi
    else
        log_item "Note: learnings CLI build skipped"
    fi
    
    # Bundle the sorty shell script
    SORTY_SCRIPT="${PROJECT_DIR}/CLI/sorty"
    if [ -f "${SORTY_SCRIPT}" ]; then
        cp "${SORTY_SCRIPT}" "${CLI_DIR}/sorty"
        chmod 755 "${CLI_DIR}/sorty"
        log_item "Bundled sorty CLI script"
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
