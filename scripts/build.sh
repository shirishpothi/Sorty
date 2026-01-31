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
    
    # Track what we've copied to detect conflicts (Bash 3.2 compatible - no associative arrays)
    # Use pipe-delimited string list: "|path1=source1|path2=source2|"
    local copied_files=""
    local conflicts=0
    
    # Helper function to check if file was already copied
    _was_copied() {
        local path="$1"
        case "${copied_files}" in
            *"|${path}="*) return 0 ;;
            *) return 1 ;;
        esac
    }
    
    # Helper function to get the source of a copied file
    _get_source() {
        local path="$1"
        local match="${copied_files#*|${path}=}"
        echo "${match%%|*}"
    }
    
    # Helper function to add a copied file
    _add_copied() {
        local path="$1"
        local source="$2"
        copied_files="${copied_files}|${path}=${source}|"
    }
    
    # Priority 1: SPM bundle (if available)
    if [ -n "${spm_bundle}" ] && [ -d "${spm_bundle}" ]; then
        # Verify bundle is valid (has contents)
        if [ "$(find "${spm_bundle}" -type f | wc -l)" -gt 0 ]; then
            # Copy SPM bundle contents directly to Resources (flatten structure)
            if cp -R "${spm_bundle}/"* "${dest_dir}/" 2>/dev/null; then
                log_item "Copied resources from SPM bundle"
                # Track what we copied
                while IFS= read -r file; do
                    local rel_path="${file#${spm_bundle}/}"
                    _add_copied "${rel_path}" "SPM bundle"
                done < <(find "${spm_bundle}" -type f)
            else
                log_item "Warning: Failed to copy from SPM bundle"
            fi
        else
            log_item "Warning: SPM bundle is empty"
        fi
    fi
    
    # Priority 2: Resources folder (only copy files not already present)
    if [ -d "${resources_dir}" ]; then
        local resources_copied=0
        while IFS= read -r file; do
            local rel_path="${file#${resources_dir}/}"
            local dest_file="${dest_dir}/${rel_path}"
            
            # Check if already copied from higher priority source
            if _was_copied "${rel_path}"; then
                # Conflict detected - log it but keep existing (SPM wins)
                local existing_source=$(_get_source "${rel_path}")
                log_item "Conflict: '${rel_path}' exists in both ${existing_source} and Resources folder (keeping SPM version)"
                conflicts=$((conflicts + 1))
                continue
            fi
            
            # Copy file if not already present
            if [ ! -e "${dest_file}" ]; then
                mkdir -p "$(dirname "${dest_file}")"
                if cp "${file}" "${dest_file}"; then
                    _add_copied "${rel_path}" "Resources folder"
                    resources_copied=$((resources_copied + 1))
                fi
            fi
        done < <(find "${resources_dir}" -type f)
        
        if [ ${resources_copied} -gt 0 ]; then
            log_item "Copied ${resources_copied} additional resources from Resources folder"
        fi
    fi
    
    # Priority 3: Fallback images (only if Images folder doesn't exist yet)
    if [ -d "${fallback_images}" ]; then
        local images_dest="${dest_dir}/Images"
        if [ ! -d "${images_dest}" ]; then
            if cp -R "${fallback_images}" "${images_dest}"; then
                log_item "Copied fallback images"
            else
                log_item "Warning: Failed to copy fallback images"
            fi
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
        if [ ${conflicts} -gt 0 ]; then
            log_item "Note: ${conflicts} conflicts resolved (SPM bundle prioritized)"
        fi
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
        PRODUCT_NAME="${PROJECT_NAME}" \
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

    log_success "xcodebuild succeeded ($(get_step_duration "build"))"

    # Verify app bundle structure
    print_step 3 $TOTAL_STEPS "Verifying App Bundle"
    start_step_timer "assemble"
    
    if [ ! -d "${APP_PATH}" ]; then
        log_failure "App bundle not found at ${APP_PATH}"
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
    else
        log_failure "Binary not found at ${BIN_PATH}/${BINARY_NAME}"
        exit 1
    fi

    # Copy Info.plist
    if [ -f "${PROJECT_DIR}/Info.plist" ]; then
        cp "${PROJECT_DIR}/Info.plist" "${APP_PATH}/Contents/"
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
