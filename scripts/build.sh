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
    local source_resources_dir="$5"
    
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

    # Priority 2b: SortyLib source resources (audio/svg not in top-level Resources)
    if [ -d "${source_resources_dir}" ]; then
        log_item "Syncing additional resources from SortyLib source resources"
        rsync -a --ignore-existing --exclude "Images/" "${source_resources_dir}/" "${dest_dir}/"
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

bundle_cli_tools() {
    local resources_dir="$1"
    local build_config="$2"
    local cli_build_flags="$3"
    local cli_arch="$4"

    if [ "${ENABLE_CLI_BUNDLE}" != "true" ]; then
        log_item "Skipping CLI bundle (ENABLE_CLI_BUNDLE=${ENABLE_CLI_BUNDLE})"
        return
    fi

    local cli_dir="${resources_dir}/CLI"
    mkdir -p "${cli_dir}"

    local -a cli_build_cmd
    cli_build_cmd=(swift build -c "${build_config}" --product learnings)

    if [ -n "${cli_arch}" ]; then
        cli_build_cmd+=(--arch "${cli_arch}")
    fi

    if [ -n "${cli_build_flags}" ]; then
        # shellcheck disable=SC2206
        local extra_flags=( ${cli_build_flags} )
        cli_build_cmd+=("${extra_flags[@]}")
    fi

    log_item "Building learnings CLI..."
    if "${cli_build_cmd[@]}" 2>/dev/null; then
        local learnings_bin=""
        if [ -n "${cli_arch}" ]; then
            learnings_bin="${PROJECT_DIR}/.build/${cli_arch}-apple-macosx/${build_config}/learnings"
        fi

        if [ -z "${learnings_bin}" ] || [ ! -f "${learnings_bin}" ]; then
            local bin_path=""
            bin_path=$(swift build -c "${build_config}" --show-bin-path)
            learnings_bin="${bin_path}/learnings"
        fi

        if [ -f "${learnings_bin}" ]; then
            cp "${learnings_bin}" "${cli_dir}/learnings"
            strip -x "${cli_dir}/learnings"
            chmod 755 "${cli_dir}/learnings"
            log_item "Bundled learnings CLI"
        else
            log_item "Note: learnings CLI binary not found after build"
        fi
    else
        log_item "Note: learnings CLI build skipped"
    fi

    # Bundle the sorty shell script
    local sorty_script="${PROJECT_DIR}/CLI/sorty"
    if [ -f "${sorty_script}" ]; then
        cp "${sorty_script}" "${cli_dir}/sorty"
        chmod 755 "${cli_dir}/sorty"
        log_item "Bundled sorty CLI script"
    fi
}

# Build and embed the SortyFinderSync Finder extension (.appex)
bundle_finder_extension() {
    local app_path="$1"
    local build_config="$2"

    local plugins_dir="${app_path}/Contents/PlugIns"
    local appex_name="SortyFinderSync.appex"
    local xcode_config="Release"
    if [ "$build_config" = "debug" ]; then
        xcode_config="Debug"
    fi

    log_item "Building SortyFinderSync extension..."

    local derived_data="${BUILD_DIR}/FinderSyncDerivedData"

    if xcodebuild -project "${PROJECT_DIR}/Sorty.xcodeproj" \
        -target "SortyFinderSync" \
        -configuration "${xcode_config}" \
        SYMROOT="${derived_data}/Build/Products" \
        OBJROOT="${derived_data}/Build/Intermediates" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        ENABLE_APP_SANDBOX=NO \
        ONLY_ACTIVE_ARCH=NO \
        build 2>&1 | tail -5; then

        local built_appex
        built_appex=$(find "${derived_data}/Build/Products" -name "${appex_name}" -type d | head -1)

        if [ -n "${built_appex}" ] && [ -d "${built_appex}" ]; then
            mkdir -p "${plugins_dir}"
            rm -rf "${plugins_dir}/${appex_name}"
            cp -R "${built_appex}" "${plugins_dir}/${appex_name}"
            codesign --force --sign - "${plugins_dir}/${appex_name}" 2>/dev/null || true
            log_item "Embedded SortyFinderSync.appex in PlugIns"
        else
            log_item "Warning: SortyFinderSync.appex not found after build"
        fi
    else
        log_item "Warning: SortyFinderSync extension build failed (non-fatal)"
    fi
}

print_header "${PROJECT_NAME} Build" 50

VERSION=$(get_version)
BUILD_NUM=$(get_build_number)

# Build method: "spm" (default for local) or "xcodebuild" (for CI releases)
BUILD_METHOD="${BUILD_METHOD:-spm}"
BUILD_ARCHS="${BUILD_ARCHS:-arm64 x86_64}"
XCODE_EXTRA_FLAGS="${XCODE_EXTRA_FLAGS:-COMPILER_INDEX_STORE_ENABLE=NO DEBUG_INFORMATION_FORMAT=dwarf ENABLE_CODE_COVERAGE=NO}"
XCODE_BUILD_JOBS="${XCODE_BUILD_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 8)}"
ENABLE_CLI_BUNDLE="${ENABLE_CLI_BUNDLE:-true}"

print_summary "Build Configuration" \
    "Version" "${VERSION}" \
    "Build" "${BUILD_NUM}" \
    "Scheme" "${SCHEME}" \
    "Method" "${BUILD_METHOD}" \
    "Archs" "${BUILD_ARCHS}" \
    "Xcode Jobs" "${XCODE_BUILD_JOBS}" \
    "Bundle CLI" "${ENABLE_CLI_BUNDLE}" \
    "Output" "${BUILD_DIR}"

if [ "${BUILD_METHOD}" = "xcodebuild" ]; then
    log_item "xcodebuild flags: ${XCODE_EXTRA_FLAGS}"
fi

# Cleanup and setup
mkdir -p "${BUILD_DIR}"
mkdir -p "${RELEASE_DIR}"

# Binary and App names from config if needed, or hardcoded for reliability
BINARY_NAME="Sorty"
SPM_BINARY_NAME="SortyApp"
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

    # shellcheck disable=SC2206
    BUILD_ARCH_ARRAY=( ${BUILD_ARCHS} )
    # shellcheck disable=SC2206
    XCODE_EXTRA_FLAGS_ARRAY=( ${XCODE_EXTRA_FLAGS} )
    
    # Build with xcodebuild using the Xcode project
    # -destination ensures we build for macOS with proper SDK
    if ! xcodebuild -project "${PROJECT_DIR}/Sorty.xcodeproj" \
        -scheme "${SCHEME}" \
        -configuration "${XCODE_CONFIG}" \
        -destination "generic/platform=macOS" \
        -derivedDataPath "${BUILD_DIR}/DerivedData" \
        -parallelizeTargets \
        -jobs "${XCODE_BUILD_JOBS}" \
        -disableAutomaticPackageResolution \
        -showBuildTimingSummary \
        INFOPLIST_FILE="${PROJECT_DIR}/Info.plist" \
        PRODUCT_BUNDLE_IDENTIFIER="${APP_BUNDLE_ID}" \
        PRODUCT_NAME="${BINARY_NAME}" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        ARCHS="${BUILD_ARCHS}" \
        "${XCODE_EXTRA_FLAGS_ARRAY[@]}" \
        build 2>&1 | tee "${BUILD_DIR}/build_output.log" | tail -50; then
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
    
    copy_resources_safely "${RESOURCES_DIR}" "${SPM_BUNDLE}" "${PROJECT_DIR}/Resources" "${IMAGES_SRC}" "${PROJECT_DIR}/Sources/SortyLib/Resources"

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

    CLI_BUILD_ARCH=""
    if [ "${#BUILD_ARCH_ARRAY[@]}" -eq 1 ]; then
        CLI_BUILD_ARCH="${BUILD_ARCH_ARRAY[0]}"
    fi
    bundle_cli_tools "${RESOURCES_DIR}" "${BUILD_CONFIG}" "" "${CLI_BUILD_ARCH}"

    # Embed Finder Sync extension
    bundle_finder_extension "${APP_PATH}" "${BUILD_CONFIG}"

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

    # Copy binary (SPM output target remains SortyApp; bundled executable is Sorty)
    if [ -f "${BIN_PATH}/${SPM_BINARY_NAME}" ]; then
        cp "${BIN_PATH}/${SPM_BINARY_NAME}" "${MACOS_DIR}/${BINARY_NAME}"
        # Ensure binary has correct RPATH for embedded frameworks
        install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/${BINARY_NAME}" 2>/dev/null || true
        strip -x "${MACOS_DIR}/${BINARY_NAME}"
    else
        log_failure "Binary not found at ${BIN_PATH}/${SPM_BINARY_NAME}"
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
    
    copy_resources_safely "${RESOURCES_DIR}" "${SPM_BUNDLE_PATH}" "${PROJECT_DIR}/Resources" "${IMAGES_SRC}" "${PROJECT_DIR}/Sources/SortyLib/Resources"

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

    bundle_cli_tools "${RESOURCES_DIR}" "${BUILD_CONFIG}" "${BUILD_FLAGS_EXTRA}" ""

    # Embed Finder Sync extension
    bundle_finder_extension "${APP_PATH}" "${BUILD_CONFIG}"

    log_success "App bundle assembled ($(get_step_duration "assemble"))"
fi

# Step 4: Signing (common for both build methods)
print_step 4 $TOTAL_STEPS "Ad-hoc Signing"
start_step_timer "sign"

ENTITLEMENTS_FILE="${PROJECT_DIR}/Sorty.entitlements"
FINDER_SYNC_ENTITLEMENTS="${PROJECT_DIR}/SortyFinderSync/SortyFinderSync.entitlements"

# Sign the Finder Sync extension first (inner-to-outer signing order)
if [ -d "${APP_PATH}/Contents/PlugIns/SortyFinderSync.appex" ]; then
    if [ -f "${FINDER_SYNC_ENTITLEMENTS}" ]; then
        codesign --force --sign - --entitlements "${FINDER_SYNC_ENTITLEMENTS}" "${APP_PATH}/Contents/PlugIns/SortyFinderSync.appex" 2>/dev/null || true
    else
        codesign --force --sign - "${APP_PATH}/Contents/PlugIns/SortyFinderSync.appex" 2>/dev/null || true
    fi
    log_item "Signed SortyFinderSync.appex"
fi

if [ -f "${ENTITLEMENTS_FILE}" ]; then
    codesign --force --deep --sign - --entitlements "${ENTITLEMENTS_FILE}" "${APP_PATH}" 2>/dev/null || true
else
    codesign --force --deep --sign - "${APP_PATH}" 2>/dev/null || true
fi
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
