#!/bin/bash
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

BACKGROUND_AGENT_PLIST_NAME="com.sorty.app.background-agent.plist"
LEGACY_BACKGROUND_AGENT_PLIST_NAME="com.sorty.app.plist"
BACKGROUND_AGENT_SERVICE_LABEL="com.sorty.app.background-agent"
BACKGROUND_AGENT_BUNDLE_PROGRAM="Contents/MacOS/Sorty"
UNSUPPORTED_ADHOC_ENTITLEMENT="com.apple.developer.usernotifications.time-sensitive"

BUILD_LOG_DIR="${BUILD_LOG_DIR:-${WORKSPACE_BUILD_DIR}/logs}"
BUILD_TAIL_LINES="${BUILD_TAIL_LINES:-40}"
AUTO_CLOSE_SORTY_ON_BUILD="${AUTO_CLOSE_SORTY_ON_BUILD:-true}"
SORTY_QUIT_WAIT_SECONDS="${SORTY_QUIT_WAIT_SECONDS:-6}"
KEYCHAIN_UNLOCK_TIMEOUT_SECONDS="${KEYCHAIN_UNLOCK_TIMEOUT_SECONDS:-43200}"
AUTO_UNLOCK_SIGNING_KEYCHAIN="${AUTO_UNLOCK_SIGNING_KEYCHAIN:-true}"
BUILD_AUTO_CLOSE_REQUEST_KEY="buildAutoCloseRequest"
AUTO_PRUNE_BUILD_CACHE="${AUTO_PRUNE_BUILD_CACHE:-true}"
BUILD_CACHE_MAX_SIZE_MB="${BUILD_CACHE_MAX_SIZE_MB:-12288}"
BUILD_CACHE_TARGET_SIZE_MB="${BUILD_CACHE_TARGET_SIZE_MB:-8192}"
BUILD_CACHE_STALE_DAYS="${BUILD_CACHE_STALE_DAYS:-14}"

sorty_processes_are_running() {
    pgrep -x "Sorty" >/dev/null 2>&1
}

count_running_sorty_instances() {
    pgrep -x "Sorty" 2>/dev/null | wc -l | tr -d ' '
}

set_build_auto_close_request() {
    local enabled="$1"
    if is_truthy "${enabled}"; then
        defaults write "${APP_BUNDLE_ID}" "${BUILD_AUTO_CLOSE_REQUEST_KEY}" -bool true >/dev/null 2>&1 || true
    else
        defaults delete "${APP_BUNDLE_ID}" "${BUILD_AUTO_CLOSE_REQUEST_KEY}" >/dev/null 2>&1 || true
    fi
}

wait_for_sorty_exit() {
    local timeout_seconds="$1"
    local elapsed=0
    while [ "${elapsed}" -lt "${timeout_seconds}" ]; do
        if ! sorty_processes_are_running; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    ! sorty_processes_are_running
}

request_sorty_quit() {
    if command -v osascript >/dev/null 2>&1; then
        osascript -e 'tell application id "com.sorty.app" to quit' >/dev/null 2>&1 || true
    else
        pkill -TERM -x "Sorty" >/dev/null 2>&1 || true
    fi
}

terminate_running_sorty_if_safe() {
    if ! is_truthy "${AUTO_CLOSE_SORTY_ON_BUILD}"; then
        log_detail "Skipping Sorty auto-close (AUTO_CLOSE_SORTY_ON_BUILD=${AUTO_CLOSE_SORTY_ON_BUILD})"
        return
    fi

    if ! sorty_processes_are_running; then
        return
    fi

    local instance_count
    instance_count=$(count_running_sorty_instances)
    log_item "Closing ${instance_count} running Sorty instance(s) after build"

    set_build_auto_close_request true
    request_sorty_quit
    if wait_for_sorty_exit "${SORTY_QUIT_WAIT_SECONDS}"; then
        set_build_auto_close_request false
        log_detail "Sorty closed gracefully"
        return
    fi

    set_build_auto_close_request false
    log_warning "Sorty stayed open (likely active organization). Build continues without force-kill."
}

get_directory_size_mb() {
    local dir_path="$1"
    if [ ! -e "${dir_path}" ]; then
        echo "0"
        return
    fi

    du -sm "${dir_path}" 2>/dev/null | awk '{print $1+0}'
}

prune_path_if_exists() {
    local path="$1"
    [ -e "${path}" ] || return
    rm -rf "${path}"
}

manage_build_cache() {
    if ! is_truthy "${AUTO_PRUNE_BUILD_CACHE}"; then
        log_detail "Skipping build cache pruning (AUTO_PRUNE_BUILD_CACHE=${AUTO_PRUNE_BUILD_CACHE})"
        return
    fi

    local max_size_mb="${BUILD_CACHE_MAX_SIZE_MB}"
    local target_size_mb="${BUILD_CACHE_TARGET_SIZE_MB}"
    local stale_days="${BUILD_CACHE_STALE_DAYS}"

    if ! [[ "${max_size_mb}" =~ ^[0-9]+$ ]]; then
        max_size_mb=12288
    fi
    if ! [[ "${target_size_mb}" =~ ^[0-9]+$ ]]; then
        target_size_mb=8192
    fi
    if ! [[ "${stale_days}" =~ ^[0-9]+$ ]]; then
        stale_days=14
    fi
    if [ "${target_size_mb}" -gt "${max_size_mb}" ]; then
        target_size_mb="${max_size_mb}"
    fi

    mkdir -p "${BUILD_DIR}"

    if [ -d "${BUILD_LOG_DIR}" ]; then
        find "${BUILD_LOG_DIR}" -type f -mtime +"${stale_days}" -exec rm -f {} + 2>/dev/null || true
    fi

    local initial_size_mb
    initial_size_mb=$(get_directory_size_mb "${BUILD_DIR}")
    if [ "${initial_size_mb}" -le "${max_size_mb}" ]; then
        return
    fi

    log_item "Pruning .build cache (${initial_size_mb}MB > ${max_size_mb}MB)"

    find "${BUILD_DIR}" -mindepth 1 -maxdepth 1 -type d -mtime +"${stale_days}" \
        ! -name "artifacts" ! -name "checkouts" ! -name "repositories" \
        -exec rm -rf {} + 2>/dev/null || true

    local current_size_mb
    current_size_mb=$(get_directory_size_mb "${BUILD_DIR}")

    if [ "${current_size_mb}" -gt "${target_size_mb}" ]; then
        prune_path_if_exists "${BUILD_DIR}/DerivedData"
        prune_path_if_exists "${BUILD_DIR}/FinderSyncDerivedData"
        current_size_mb=$(get_directory_size_mb "${BUILD_DIR}")
    fi

    if [ "${current_size_mb}" -gt "${target_size_mb}" ]; then
        run_with_log --optional "swift_package_clean" swift package --package-path "${PROJECT_DIR}" --scratch-path "${BUILD_DIR}" clean
        current_size_mb=$(get_directory_size_mb "${BUILD_DIR}")
    fi

    if [ "${current_size_mb}" -gt "${target_size_mb}" ]; then
        if [ -d "${BUILD_DIR}/artifacts" ]; then
            find "${BUILD_DIR}/artifacts" -mindepth 1 -maxdepth 1 -mtime +"${stale_days}" -exec rm -rf {} + 2>/dev/null || true
        fi
        if [ -d "${BUILD_DIR}/repositories" ]; then
            find "${BUILD_DIR}/repositories" -mindepth 1 -maxdepth 1 -mtime +"${stale_days}" -exec rm -rf {} + 2>/dev/null || true
        fi
        current_size_mb=$(get_directory_size_mb "${BUILD_DIR}")
    fi

    local reclaimed_mb=$((initial_size_mb - current_size_mb))
    if [ "${reclaimed_mb}" -gt 0 ]; then
        log_item "Reclaimed ${reclaimed_mb}MB from .build cache (now ${current_size_mb}MB)"
    fi

    if [ "${current_size_mb}" -gt "${max_size_mb}" ]; then
        log_warning ".build remains large (${current_size_mb}MB). Lower BUILD_CACHE_STALE_DAYS or run make clean if needed."
    fi
}

resolve_signing_identity() {
    if [ -n "${SIGNING_IDENTITY:-}" ] && [ "${SIGNING_IDENTITY}" != "auto" ]; then
        echo "${SIGNING_IDENTITY}"
        return
    fi

    local detected_identity=""
    detected_identity=$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development:|Mac Developer:|Developer ID Application:/ { print $2; exit }')

    if [ -n "${detected_identity}" ]; then
        echo "${detected_identity}"
        return
    fi

    echo "-"
}

configure_keychain_session_for_signing() {
    if [ "${SIGNING_IDENTITY}" = "-" ]; then
        return
    fi

    if ! is_truthy "${AUTO_UNLOCK_SIGNING_KEYCHAIN}"; then
        log_detail "Skipping keychain auto-unlock (AUTO_UNLOCK_SIGNING_KEYCHAIN=${AUTO_UNLOCK_SIGNING_KEYCHAIN})"
        return
    fi

    local keychain_path="${SIGNING_KEYCHAIN_PATH:-}"
    if [ -z "${keychain_path}" ]; then
        keychain_path=$(security default-keychain -d user 2>/dev/null | tr -d '"' | xargs)
    fi

    if [ -z "${keychain_path}" ]; then
        log_warning "Unable to determine default keychain path"
        return
    fi

    security set-keychain-settings -lut "${KEYCHAIN_UNLOCK_TIMEOUT_SECONDS}" "${keychain_path}" >/dev/null 2>&1 || true

    if security show-keychain-info "${keychain_path}" >/dev/null 2>&1; then
        log_detail "Keychain already unlocked for signing"
    else
        if [ -n "${KEYCHAIN_PASSWORD:-}" ]; then
            log_item "Unlocking keychain for signing (${KEYCHAIN_UNLOCK_TIMEOUT_SECONDS}s timeout)"
            if security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${keychain_path}" >/dev/null 2>&1; then
                log_detail "Keychain unlocked"
            else
                log_warning "Keychain unlock failed. Signing may prompt."
            fi
        else
            log_detail "Keychain is locked; set KEYCHAIN_PASSWORD to unlock non-interactively"
        fi
    fi

    if [ -n "${KEYCHAIN_PASSWORD:-}" ]; then
        if security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${KEYCHAIN_PASSWORD}" "${keychain_path}" >/dev/null 2>&1; then
            log_detail "Updated keychain partition list for codesign"
        else
            log_warning "Could not update keychain partition list for codesign"
        fi
    else
        log_detail "Set KEYCHAIN_PASSWORD to avoid repeated key access prompts"
    fi
}

resolve_codesign_identity() {
    local requested_identity="$1"

    if [ -n "${requested_identity}" ] && [ "${requested_identity}" != "auto" ]; then
        echo "${requested_identity}"
        return
    fi

    resolve_signing_identity
}

codesign_cmd() {
    local -a cmd=(codesign --force --sign "${SIGNING_IDENTITY}")
    cmd+=("$@")
    "${cmd[@]}"
}

codesign_cmd_hardened_runtime() {
    local -a cmd=(codesign --force --options runtime --sign "${SIGNING_IDENTITY}")
    cmd+=("$@")
    "${cmd[@]}"
}

codesign_cmd_allow_failure() {
    local -a cmd=(codesign --force --sign "${SIGNING_IDENTITY}")
    cmd+=("$@")
    "${cmd[@]}" || true
}

run_with_log() {
    local mode="required"
    if [ "${1:-}" = "--optional" ]; then
        mode="optional"
        shift
    fi

    local log_name="$1"
    shift

    if is_truthy "${SORTY_VERBOSE}"; then
        "$@"
        return $?
    fi

    mkdir -p "${BUILD_LOG_DIR}"
    local log_file="${BUILD_LOG_DIR}/${log_name}.log"

    if "$@" >"${log_file}" 2>&1; then
        return 0
    fi

    if [ "${mode}" = "optional" ]; then
        log_warning "${log_name} failed (non-fatal)"
    else
        log_failure "${log_name} failed"
    fi
    log_item "Last ${BUILD_TAIL_LINES} log lines (${log_file}):"
    tail -n "${BUILD_TAIL_LINES}" "${log_file}" || true
    return 1
}

run_quiet() {
    if is_truthy "${SORTY_VERBOSE}"; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

run_quiet_allow_failure() {
    if is_truthy "${SORTY_VERBOSE}"; then
        "$@" || true
    else
        "$@" >/dev/null 2>&1 || true
    fi
}

normalize_app_executable_linkage() {
    local executable_path="$1"
    local sparkle_rpath_load="@rpath/Sparkle.framework/Versions/B/Sparkle"
    local sparkle_embedded_load="@executable_path/../Frameworks/Sparkle.framework/Versions/B/Sparkle"

    run_quiet_allow_failure install_name_tool -add_rpath "@executable_path/../Frameworks" "${executable_path}"

    if otool -L "${executable_path}" | grep -F "${sparkle_rpath_load}" >/dev/null; then
        run_quiet install_name_tool -change "${sparkle_rpath_load}" "${sparkle_embedded_load}" "${executable_path}"
    fi
}

swiftpm_build_db_error_detected() {
    local log_name="$1"
    local log_file="${BUILD_LOG_DIR}/${log_name}.log"

    if [ ! -f "${log_file}" ]; then
        return 1
    fi

    grep -Eiq 'accessing build database .* (disk I/O error|database disk image is malformed|readonly database|unable to open database file)' "${log_file}"
}

reset_swiftpm_build_database() {
    log_item "Resetting SwiftPM build database"
    rm -f \
        "${BUILD_DIR}/.lock" \
        "${BUILD_DIR}/build.db" \
        "${BUILD_DIR}/build.db-journal" \
        "${BUILD_DIR}/build.db-shm" \
        "${BUILD_DIR}/build.db-wal"
}

run_with_swiftpm_db_recovery() {
    local log_name="$1"
    shift

    if run_with_log "${log_name}" "$@"; then
        return 0
    fi

    if ! swiftpm_build_db_error_detected "${log_name}"; then
        return 1
    fi

    log_warning "SwiftPM build database hit a transient SQLite error; retrying once with a fresh database."
    reset_swiftpm_build_database
    run_with_log "${log_name}_retry" "$@"
}

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
            log_detail "Syncing resources from SPM bundle"
            rsync -a \
                --exclude ".DS_Store" \
                --exclude "CLI/" \
                --exclude "AppIcons/" \
                "${spm_bundle}/" "${dest_dir}/"
        else
            log_warning "SPM bundle is empty"
        fi
    fi
    
    # Priority 2: Resources folder (sync updates from source)
    if [ -d "${resources_dir}" ]; then
        log_detail "Syncing additional resources from Resources folder"
        rsync -a \
            --exclude ".DS_Store" \
            --exclude "CLI/" \
            --exclude "AppIcons/" \
            --exclude "backgroundImage.png" \
            --exclude "dmg-background.png" \
            --exclude "dmg-background-with-toolbar.png" \
            --exclude "dmg-layout.json" \
            "${resources_dir}/" "${dest_dir}/"
    fi

    # Priority 2b: SortyLib source resources (audio/svg not in top-level Resources)
    if [ -d "${source_resources_dir}" ]; then
        log_detail "Syncing additional resources from SortyLib source resources"
        rsync -a \
            --exclude ".DS_Store" \
            --exclude "Images/" \
            "${source_resources_dir}/" "${dest_dir}/"
    fi
    
    # Priority 3: Fallback images (only if Images folder doesn't exist yet)
    if [ -d "${fallback_images}" ]; then
        local images_dest="${dest_dir}/Images"
        if [ ! -d "${images_dest}" ]; then
            log_detail "Syncing fallback images"
            rsync -a "${fallback_images}/" "${images_dest}/"
        else
            log_detail "Images folder already present from higher priority source, skipping fallback"
        fi
    fi
    
    # Report integrity: verify Resources directory has content
    local total_resources
    total_resources=$(find "${dest_dir}" -type f | wc -l)
    if [ "${total_resources}" -eq 0 ]; then
        log_warning "No resources copied to app bundle"
    else
        log_detail "Total resources in app bundle: ${total_resources}"
    fi
}

copy_swiftpm_dependency_resource_bundles() {
    local resources_dir="$1"
    local build_dir="$2"

    if [ ! -d "${build_dir}" ]; then
        return 0
    fi

    while IFS= read -r bundle_path; do
        local bundle_name
        bundle_name="$(basename "${bundle_path}")"

        case "${bundle_name}" in
            Sorty_SortyLib.bundle)
                # SortyLib resources are intentionally flattened into
                # Contents/Resources by copy_resources_safely.
                continue
                ;;
        esac

        log_detail "Embedding SwiftPM resource bundle ${bundle_name}"
        rm -rf "${resources_dir}/${bundle_name}"
        rsync -a "${bundle_path}/" "${resources_dir}/${bundle_name}/"
    done < <(find "${build_dir}" -path "*/${BUILD_CONFIG}/*.bundle" -type d | sort)
}

compile_asset_catalog() {
    local resources_dir="$1"
    local app_path="$2"
    local xcassets_path="${resources_dir}/Assets.xcassets"

    if [ ! -d "${xcassets_path}" ]; then
        log_detail "No Assets.xcassets found, skipping asset catalog compilation"
        return
    fi

    log_detail "Compiling Assets.xcassets with actool..."
    if xcrun actool "${xcassets_path}" \
        --compile "${resources_dir}" \
        --platform macosx \
        --minimum-deployment-target 15.0 \
        --app-icon AppIcon \
        --accent-color AccentColor \
        --output-partial-info-plist /dev/null >/dev/null 2>&1; then
        # Remove the raw xcassets directory now that it's compiled
        rm -rf "${xcassets_path}"
        log_detail "Asset catalog compiled to Assets.car"
    else
        log_warning "actool compilation failed, falling back to raw xcassets"
    fi
}

bundle_cli_tools() {
    local resources_dir="$1"

    if [ "${ENABLE_CLI_BUNDLE}" != "true" ]; then
        log_detail "Skipping CLI bundle (ENABLE_CLI_BUNDLE=${ENABLE_CLI_BUNDLE})"
        return
    fi

    rm -rf "${resources_dir}/CLI"
    rm -rf "${resources_dir}/AppIcons"
    log_detail "Sorty CLI tools are deprecated and are no longer bundled"
}

prune_nonshipping_resources() {
    local resources_dir="$1"

    rm -rf "${resources_dir}/CLI" "${resources_dir}/AppIcons"
    rm -f \
        "${resources_dir}/.DS_Store" \
        "${resources_dir}/.png" \
        "${resources_dir}/backgroundImage.png" \
        "${resources_dir}/dmg-background.png" \
        "${resources_dir}/dmg-background-with-toolbar.png" \
        "${resources_dir}/dmg-layout.json" \
        "${resources_dir}/whats-new-mid-generation.png" \
        "${resources_dir}/whats-new-rename-only.png"
}

bundle_background_agent_plist() {
    local app_path="$1"
    local launch_agents_dir="${app_path}/Contents/Library/LaunchAgents"
    local source_plist="${PROJECT_DIR}/Resources/${BACKGROUND_AGENT_PLIST_NAME}"
    local bundled_plist="${launch_agents_dir}/${BACKGROUND_AGENT_PLIST_NAME}"
    local legacy_plist="${launch_agents_dir}/${LEGACY_BACKGROUND_AGENT_PLIST_NAME}"

    mkdir -p "${launch_agents_dir}"
    rm -f "${legacy_plist}" "${bundled_plist}"

    if [ ! -f "${source_plist}" ]; then
        log_warning "Background agent plist not found at ${source_plist}"
        return
    fi

    cp "${source_plist}" "${bundled_plist}"

    local label
    label=$(/usr/libexec/PlistBuddy -c "Print :Label" "${bundled_plist}" 2>/dev/null || true)
    local bundle_program
    bundle_program=$(/usr/libexec/PlistBuddy -c "Print :BundleProgram" "${bundled_plist}" 2>/dev/null || true)

    if [ -z "${label}" ]; then
        log_failure "Background agent plist is missing Label"
        exit 1
    fi

    if [ "${label}" = "${APP_BUNDLE_ID}" ]; then
        log_failure "Background agent Label (${label}) must not match the app bundle identifier (${APP_BUNDLE_ID})"
        exit 1
    fi

    if [ "${label}" != "${BACKGROUND_AGENT_SERVICE_LABEL}" ]; then
        log_failure "Background agent Label must remain ${BACKGROUND_AGENT_SERVICE_LABEL} (found ${label})"
        exit 1
    fi

    if [ "${bundle_program}" != "${BACKGROUND_AGENT_BUNDLE_PROGRAM}" ]; then
        log_failure "Background agent BundleProgram must remain ${BACKGROUND_AGENT_BUNDLE_PROGRAM} (found ${bundle_program:-<missing>})"
        exit 1
    fi

    log_detail "Copied background agent plist"
}

validate_adhoc_entitlements() {
    local entitlements_path="$1"
    local description="$2"

    if /usr/libexec/PlistBuddy -c "Print :${UNSUPPORTED_ADHOC_ENTITLEMENT}" "${entitlements_path}" >/dev/null 2>&1; then
        log_failure "${description} cannot request ${UNSUPPORTED_ADHOC_ENTITLEMENT} when Sorty is ad-hoc signed."
        exit 1
    fi
}

sparkle_resources_dir() {
    local framework_path="$1"
    local current_resources="${framework_path}/Versions/Current/Resources"
    if [ -d "${current_resources}" ]; then
        echo "${current_resources}"
        return 0
    fi

    local fallback_resources
    fallback_resources=$(find "${framework_path}/Versions" -mindepth 2 -maxdepth 2 -type d -name Resources 2>/dev/null | head -1)
    if [ -n "${fallback_resources}" ]; then
        echo "${fallback_resources}"
        return 0
    fi

    return 1
}

sparkle_framework_has_valid_layout() {
    local framework_path="$1"
    [ -d "${framework_path}" ] || return 1
    [ -L "${framework_path}/Versions/Current" ] || return 1
    sparkle_resources_dir "${framework_path}" >/dev/null 2>&1
}

embed_sparkle_framework() {
    local source_framework="$1"
    local target_framework="$2"
    local preserve_existing="$3"

    if [ ! -d "${source_framework}" ]; then
        return 1
    fi

    if [ "${preserve_existing}" = "true" ] && sparkle_framework_has_valid_layout "${target_framework}"; then
        log_detail "Sparkle.framework already present, preserving valid bundle"
        return 0
    fi

    rm -rf "${target_framework}"
    ditto "${source_framework}" "${target_framework}"
    log_detail "Embedded Sparkle.framework"
}

sign_sparkle_framework() {
    local framework_path="$1"
    [ -d "${framework_path}" ] || return 0

    local resources_dir=""
    resources_dir=$(sparkle_resources_dir "${framework_path}" || true)

    if [ -n "${resources_dir}" ]; then
        for helper in "Autoupdate.app" "Updater.app"; do
            local helper_path="${resources_dir}/${helper}"
            if [ -d "${helper_path}" ]; then
                run_quiet codesign_cmd_hardened_runtime "${helper_path}"
            fi
        done
    fi

    find "${framework_path}" -path "*/XPCServices/*.xpc" -type d -print0 2>/dev/null | while IFS= read -r -d '' xpc_service; do
        run_quiet codesign_cmd_hardened_runtime "${xpc_service}"
    done

    run_quiet codesign_cmd_hardened_runtime "${framework_path}"
}

# Build and embed the SortyFinderSync Finder extension (.appex)
bundle_finder_extension() {
    local app_path="$1"
    local build_config="$2"

    local plugins_dir="${app_path}/Contents/PlugIns"
    local appex_name="SortyFinderSync.appex"
    local xcode_config="Release"
    local arch_setting="ONLY_ACTIVE_ARCH=NO"
    if [ "$build_config" = "debug" ]; then
        xcode_config="Debug"
        arch_setting="ONLY_ACTIVE_ARCH=YES"
    fi

    local derived_data="${BUILD_DIR}/FinderSyncDerivedData"
    local cached_appex="${derived_data}/Build/Products/${xcode_config}/${appex_name}"

    # Skip rebuild if cached appex is newer than all source files
    if [ -d "${cached_appex}" ]; then
        local needs_rebuild=false
        for src_file in \
            "${PROJECT_DIR}/Sources/SortyFinderSync/SortyFinderSync.swift" \
            "${PROJECT_DIR}/SortyFinderSync/Info.plist" \
            "${PROJECT_DIR}/SortyFinderSync/SortyFinderSync.entitlements"; do
            if [ -f "${src_file}" ] && [ "${src_file}" -nt "${cached_appex}" ]; then
                needs_rebuild=true
                break
            fi
        done
        if [ "${needs_rebuild}" = "false" ]; then
            mkdir -p "${plugins_dir}"
            rm -rf "${plugins_dir}/${appex_name}"
            cp -R "${cached_appex}" "${plugins_dir}/${appex_name}"
            if [ "${ENABLE_ADHOC_SIGNING}" = "true" ]; then
                run_quiet_allow_failure codesign_cmd_allow_failure "${plugins_dir}/${appex_name}"
            fi
            log_detail "SortyFinderSync.appex unchanged, using cache"
            return
        fi
    fi

    log_detail "Building SortyFinderSync extension..."
    start_step_timer "finder_ext"

    if run_with_log --optional "finder_extension" xcodebuild -project "${PROJECT_DIR}/Sorty.xcodeproj" \
        -target "SortyFinderSync" \
        -configuration "${xcode_config}" \
        -parallelizeTargets \
        -jobs "${XCODE_BUILD_JOBS}" \
        SYMROOT="${derived_data}/Build/Products" \
        OBJROOT="${derived_data}/Build/Intermediates" \
        PRODUCT_BUNDLE_IDENTIFIER="${APP_BUNDLE_ID}.SortyFinderSync" \
        COMPILER_INDEX_STORE_ENABLE=NO \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        ENABLE_APP_SANDBOX=NO \
        ${arch_setting} \
        build; then

        local built_appex
        built_appex=$(find "${derived_data}/Build/Products/${xcode_config}" -name "${appex_name}" -type d 2>/dev/null | head -1)
        if [ -z "${built_appex}" ]; then
            built_appex=$(find "${derived_data}/Build/Products" -name "${appex_name}" -type d | head -1)
        fi

        if [ -n "${built_appex}" ] && [ -d "${built_appex}" ]; then
            mkdir -p "${plugins_dir}"
            rm -rf "${plugins_dir}/${appex_name}"
            cp -R "${built_appex}" "${plugins_dir}/${appex_name}"
            if [ "${ENABLE_ADHOC_SIGNING}" = "true" ]; then
                run_quiet_allow_failure codesign_cmd_allow_failure "${plugins_dir}/${appex_name}"
            fi
            log_detail "Embedded SortyFinderSync.appex in PlugIns ($(get_step_duration "finder_ext"))"
        else
            log_warning "SortyFinderSync.appex not found after build"
        fi
    else
        log_detail "Continuing without Finder extension ($(get_step_duration "finder_ext"))"
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
ENABLE_CLI_BUNDLE="${ENABLE_CLI_BUNDLE:-false}"
ENABLE_FINDER_EXTENSION="${ENABLE_FINDER_EXTENSION:-true}"
ENABLE_ADHOC_SIGNING="${ENABLE_ADHOC_SIGNING:-true}"
ENABLE_SPARKLE_SIGNING="${ENABLE_SPARKLE_SIGNING:-true}"
PRESERVE_APP_BUNDLE="${PRESERVE_APP_BUNDLE:-false}"
SORTY_VERBOSE="${SORTY_VERBOSE:-${VERBOSE:-false}}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-auto}"
if [ "${ENABLE_ADHOC_SIGNING}" = "true" ] || [ "${ENABLE_SPARKLE_SIGNING}" = "true" ]; then
    SIGNING_IDENTITY=$(resolve_codesign_identity "${SIGNING_IDENTITY}")
else
    SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
fi

if [ "${SIGNING_IDENTITY}" = "-" ]; then
    log_detail "Using ad-hoc code signing identity"
    log_warning "No certificate signing identity found; keychain access prompts may repeat between builds"
fi

if [ "${ENABLE_ADHOC_SIGNING}" = "true" ] || [ "${ENABLE_SPARKLE_SIGNING}" = "true" ]; then
    configure_keychain_session_for_signing
fi

if is_truthy "${SORTY_VERBOSE}"; then
    print_summary "Build Configuration" \
        "Version" "${VERSION}" \
        "Build" "${BUILD_NUM}" \
        "Scheme" "${SCHEME}" \
        "Method" "${BUILD_METHOD}" \
        "Archs" "${BUILD_ARCHS}" \
        "Xcode Jobs" "${XCODE_BUILD_JOBS}" \
        "Signing Identity" "${SIGNING_IDENTITY}" \
        "Bundle CLI" "${ENABLE_CLI_BUNDLE}" \
        "Finder Extension" "${ENABLE_FINDER_EXTENSION}" \
        "Code Signing" "${ENABLE_ADHOC_SIGNING}" \
        "Sparkle Signing" "${ENABLE_SPARKLE_SIGNING}" \
        "Preserve Bundle" "${PRESERVE_APP_BUNDLE}" \
        "Output" "${BUILD_DIR}"
else
    print_summary "Build" \
        "Version" "${VERSION} (${BUILD_NUM})" \
        "Config" "${BUILD_CONFIG:-release}/${BUILD_METHOD}" \
        "Signing" "${SIGNING_IDENTITY}" \
        "Output" "${APP_PATH}"
fi

if [ "${BUILD_METHOD}" = "xcodebuild" ]; then
    log_detail "xcodebuild flags: ${XCODE_EXTRA_FLAGS}"
fi

# Cleanup and setup
mkdir -p "${BUILD_DIR}"
mkdir -p "${RELEASE_DIR}"
manage_build_cache

# Binary and App names from config if needed, or hardcoded for reliability
BINARY_NAME="Sorty"
SPM_BINARY_NAME="SortyApp"
APP_BUNDLE="Sorty.app"

TOTAL_STEPS=4

# Build configuration
BUILD_CONFIG="${BUILD_CONFIG:-release}"
log_detail "Configuration: ${BUILD_CONFIG}"

if [ "$SKIP_TESTS" != "true" ]; then
    print_step 1 $TOTAL_STEPS "Running Unit Tests"
    start_step_timer "test"
    TEST_FLAGS="${BUILD_FLAGS:-}"
    TEST_FLAGS_ARRAY=()
    if [ -n "${TEST_FLAGS}" ]; then
        # shellcheck disable=SC2206
        TEST_FLAGS_ARRAY=( ${TEST_FLAGS} )
    fi
    if ! run_with_swiftpm_db_recovery "unit_tests" swift test --scratch-path "${BUILD_DIR}" "${TEST_FLAGS_ARRAY[@]}" --disable-sandbox; then
        log_failure "Tests failed ($(get_step_duration "test")). Set SKIP_TESTS=true to bypass."
        exit 1
    fi
    log_success "Tests passed ($(get_step_duration "test"))"
else
    print_step 1 $TOTAL_STEPS "Skipping Unit Tests"
    log_detail "SKIP_TESTS is set."
fi

# Inject Git Info (skippable for fast dev loops)
if [ "${SKIP_GIT_INJECT}" != "true" ]; then
    if is_truthy "${SORTY_VERBOSE}"; then
        "${SCRIPT_DIR}/inject_git_info.sh" "${PROJECT_DIR}/Resources"
    else
        "${SCRIPT_DIR}/inject_git_info.sh" "${PROJECT_DIR}/Resources" >/dev/null
    fi
else
    log_detail "Skipping git info injection (SKIP_GIT_INJECT=true)"
fi

print_step 2 $TOTAL_STEPS "Compiling Project"
start_step_timer "build"

if [ "$BUILD_METHOD" = "xcodebuild" ]; then
    # Use xcodebuild for CI releases - ensures proper SDK targeting and deployment target
    XCODE_CONFIG="Release"
    if [ "$BUILD_CONFIG" = "debug" ]; then
        XCODE_CONFIG="Debug"
    fi
    
    log_detail "Using xcodebuild with configuration: ${XCODE_CONFIG}"

    # shellcheck disable=SC2206
    BUILD_ARCH_ARRAY=( ${BUILD_ARCHS} )
    # shellcheck disable=SC2206
    XCODE_EXTRA_FLAGS_ARRAY=( ${XCODE_EXTRA_FLAGS} )
    
    # Build with xcodebuild using the Xcode project
    # -destination ensures we build for macOS with proper SDK
    if ! run_with_log "xcodebuild_compile" xcodebuild -project "${PROJECT_DIR}/Sorty.xcodeproj" \
        -scheme "${SCHEME}" \
        -configuration "${XCODE_CONFIG}" \
        -destination "generic/platform=macOS" \
        -derivedDataPath "${BUILD_DIR}/DerivedData" \
        -parallelizeTargets \
        -jobs "${XCODE_BUILD_JOBS}" \
        -skipPackagePluginValidation \
        -showBuildTimingSummary \
        INFOPLIST_FILE="${PROJECT_DIR}/Info.plist" \
        PRODUCT_BUNDLE_IDENTIFIER="${APP_BUNDLE_ID}" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        ARCHS="${BUILD_ARCHS}" \
        "${XCODE_EXTRA_FLAGS_ARRAY[@]}" \
        build; then
        exit 1
    fi
    
    # Find the built app in DerivedData (match exact name to avoid picking up
    # Sparkle's Updater.app or Autoupdate.app which are also .app bundles)
    BUILT_APP=$(find "${BUILD_DIR}/DerivedData" -name "${APP_BUNDLE}" -type d | head -1)
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
        chmod +x "${MACOS_BIN}"
        normalize_app_executable_linkage "${MACOS_BIN}"
        if [ "${BUILD_CONFIG}" != "debug" ]; then
            run_quiet strip -x "${MACOS_BIN}"
        fi
        chmod +x "${MACOS_BIN}"
    fi

    # Inject Sparkle keys and version into built Info.plist (xcodebuild may drop custom keys)
    BUILT_PLIST="${APP_PATH}/Contents/Info.plist"
    ROOT_PLIST="${PROJECT_DIR}/Info.plist"
    if [ -f "${BUILT_PLIST}" ] && [ -f "${ROOT_PLIST}" ]; then
        for key in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks; do
            VAL=$(/usr/libexec/PlistBuddy -c "Print :${key}" "${ROOT_PLIST}" 2>/dev/null || true)
            if [ -n "${VAL}" ]; then
                /usr/libexec/PlistBuddy -c "Delete :${key}" "${BUILT_PLIST}" 2>/dev/null || true
                # Detect type: SUEnableAutomaticChecks is bool, rest are strings
                if [ "${key}" = "SUEnableAutomaticChecks" ]; then
                    /usr/libexec/PlistBuddy -c "Add :${key} bool ${VAL}" "${BUILT_PLIST}"
                else
                    /usr/libexec/PlistBuddy -c "Add :${key} string ${VAL}" "${BUILT_PLIST}"
                fi
            fi
        done
        # Also inject version/build from root plist
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${BUILT_PLIST}" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUM}" "${BUILT_PLIST}" 2>/dev/null || true
        log_detail "Injected Sparkle keys and version into bundle Info.plist"
    fi

    # Copy Resources with integrity checks and conflict detection
    RESOURCES_DIR="${APP_PATH}/Contents/Resources"
    SPM_BUNDLE=$(find "${BUILD_DIR}/DerivedData" -name "Sorty_SortyLib.bundle" -type d | head -1)
    IMAGES_SRC="${PROJECT_DIR}/Sources/SortyLib/Resources/Images"
    
    copy_resources_safely "${RESOURCES_DIR}" "${SPM_BUNDLE}" "${PROJECT_DIR}/Resources" "${IMAGES_SRC}" "${PROJECT_DIR}/Sources/SortyLib/Resources"

    # Compile Assets.xcassets into Assets.car (xcodebuild may have already done this)
    compile_asset_catalog "${RESOURCES_DIR}" "${APP_PATH}"
    prune_nonshipping_resources "${RESOURCES_DIR}"

    # Remove stale entitlements file from bundle (entitlements are applied via --entitlements flag during signing)
    rm -f "${APP_PATH}/Contents/Sorty.entitlements"

    # Copy LaunchAgent plist for Background Activity
    bundle_background_agent_plist "${APP_PATH}"

    bundle_cli_tools "${RESOURCES_DIR}"

    # Embed Finder Sync extension
    if [ "${ENABLE_FINDER_EXTENSION}" = "true" ]; then
        bundle_finder_extension "${APP_PATH}" "${BUILD_CONFIG}"
    else
        rm -rf "${APP_PATH}/Contents/PlugIns/SortyFinderSync.appex"
        log_detail "Skipping Finder extension bundle (ENABLE_FINDER_EXTENSION=${ENABLE_FINDER_EXTENSION})"
    fi

    log_success "xcodebuild succeeded ($(get_step_duration "build"))"

    # Embed Sparkle framework for xcodebuild (if not already embedded)
    FRAMEWORKS_DIR="${APP_PATH}/Contents/Frameworks"
    if [ ! -d "${FRAMEWORKS_DIR}/Sparkle.framework" ]; then
        mkdir -p "${FRAMEWORKS_DIR}"
        # Search in DerivedData (xcodebuild) or .build/artifacts (SPM fallback)
        SPARKLE_FRAMEWORK=$(find "${BUILD_DIR}/DerivedData" -name "Sparkle.framework" -type d 2>/dev/null | head -1)
        if [ -z "${SPARKLE_FRAMEWORK}" ]; then
            SPARKLE_FRAMEWORK=$(find "${BUILD_DIR}/artifacts" -name "Sparkle.framework" -type d 2>/dev/null | head -1)
        fi
        
        if [ -n "${SPARKLE_FRAMEWORK}" ] && [ -d "${SPARKLE_FRAMEWORK}" ]; then
            embed_sparkle_framework "${SPARKLE_FRAMEWORK}" "${FRAMEWORKS_DIR}/Sparkle.framework" "false"
            
            if [ "${ENABLE_SPARKLE_SIGNING}" = "true" ]; then
                # Deep sign the framework and its internal helpers for Sandbox compatibility
                log_detail "Signing Sparkle.framework for Sandbox compatibility"
                sign_sparkle_framework "${FRAMEWORKS_DIR}/Sparkle.framework"
                log_detail "Embedded and signed Sparkle.framework"
            else
                log_detail "Embedded Sparkle.framework without signing"
            fi
        else
            log_warning "Sparkle.framework not found, skipping embed"
        fi
    else
        log_detail "Sparkle.framework already embedded"
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
    validate_sorty_app_linkage "${APP_PATH}"
    
    log_success "App bundle verified ($(get_step_duration "assemble"))"
else
    # Use swift build (SPM) for local development
    # BUILD_FLAGS can be set from Makefile for parallel compilation
    BUILD_FLAGS_EXTRA="${BUILD_FLAGS:-}"
    log_detail "Build flags: ${BUILD_FLAGS_EXTRA}"
    BUILD_FLAGS_ARRAY=()
    if [ -n "${BUILD_FLAGS_EXTRA}" ]; then
        # shellcheck disable=SC2206
        BUILD_FLAGS_ARRAY=( ${BUILD_FLAGS_EXTRA} )
    fi
    if ! run_with_swiftpm_db_recovery "swift_build" swift build --scratch-path "${BUILD_DIR}" -c "${BUILD_CONFIG}" --product "${SPM_BINARY_NAME}" "${BUILD_FLAGS_ARRAY[@]}"; then
        log_failure "Compilation failed"
        exit 1
    fi
    BIN_PATH="${BUILD_DIR}/${BUILD_CONFIG}"
    log_success "Compilation succeeded ($(get_step_duration "build"))"

    print_step 3 $TOTAL_STEPS "Assembling App Bundle"
    start_step_timer "assemble"

    # Build structure
    MACOS_DIR="${APP_PATH}/Contents/MacOS"
    RESOURCES_DIR="${APP_PATH}/Contents/Resources"

    if [ "${PRESERVE_APP_BUNDLE}" != "true" ]; then
        rm -rf "${APP_PATH}"
    fi
    mkdir -p "${MACOS_DIR}"
    mkdir -p "${RESOURCES_DIR}"

    # Copy binary (SPM output target remains SortyApp; bundled executable is Sorty)
    if [ -f "${BIN_PATH}/${SPM_BINARY_NAME}" ]; then
        cp "${BIN_PATH}/${SPM_BINARY_NAME}" "${MACOS_DIR}/${BINARY_NAME}"
        chmod +x "${MACOS_DIR}/${BINARY_NAME}"
        normalize_app_executable_linkage "${MACOS_DIR}/${BINARY_NAME}"
        if [ "${BUILD_CONFIG}" != "debug" ]; then
            run_quiet strip -x "${MACOS_DIR}/${BINARY_NAME}"
        fi
        chmod +x "${MACOS_DIR}/${BINARY_NAME}"
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
        
        log_detail "Injected Version ${VERSION} (Build ${BUILD_NUM}) into bundle Info.plist"
    fi

    # Copy Resources with integrity checks and conflict detection
    SPM_BUNDLE_PATH="${BIN_PATH}/Sorty_SortyLib.bundle"
    IMAGES_SRC="${PROJECT_DIR}/Sources/SortyLib/Resources/Images"
    
    copy_resources_safely "${RESOURCES_DIR}" "${SPM_BUNDLE_PATH}" "${PROJECT_DIR}/Resources" "${IMAGES_SRC}" "${PROJECT_DIR}/Sources/SortyLib/Resources"
    copy_swiftpm_dependency_resource_bundles "${RESOURCES_DIR}" "${BUILD_DIR}"

    # Compile Assets.xcassets into Assets.car
    compile_asset_catalog "${RESOURCES_DIR}" "${APP_PATH}"
    prune_nonshipping_resources "${RESOURCES_DIR}"

    # Remove stale entitlements file from bundle (entitlements are applied via --entitlements flag during signing)
    rm -f "${APP_PATH}/Contents/Sorty.entitlements"

    # Copy LaunchAgent plist for Background Activity
    bundle_background_agent_plist "${APP_PATH}"

    # Embed Sparkle framework for SPM builds
    FRAMEWORKS_DIR="${APP_PATH}/Contents/Frameworks"
    mkdir -p "${FRAMEWORKS_DIR}"
    
    # Find Sparkle.framework in SPM build artifacts
    SPARKLE_FRAMEWORK=""
    if [ -d "${BIN_PATH}/Sparkle.framework" ]; then
        SPARKLE_FRAMEWORK="${BIN_PATH}/Sparkle.framework"
    else
        # Search in .build/artifacts for any architecture-specific Sparkle.framework
        SPARKLE_FRAMEWORK=$(find "${BUILD_DIR}/artifacts" -name "Sparkle.framework" -type d 2>/dev/null | head -1)
    fi
    
    if [ -n "${SPARKLE_FRAMEWORK}" ] && [ -d "${SPARKLE_FRAMEWORK}" ]; then
        TARGET_SPARKLE_FRAMEWORK="${FRAMEWORKS_DIR}/Sparkle.framework"
        embed_sparkle_framework "${SPARKLE_FRAMEWORK}" "${TARGET_SPARKLE_FRAMEWORK}" "${PRESERVE_APP_BUNDLE}"

        if [ "${ENABLE_SPARKLE_SIGNING}" = "true" ]; then
            log_detail "Signing Sparkle.framework for Sandbox compatibility"
            sign_sparkle_framework "${FRAMEWORKS_DIR}/Sparkle.framework"
            log_detail "Signed Sparkle.framework"
        else
            log_detail "Skipping Sparkle.framework signing (ENABLE_SPARKLE_SIGNING=${ENABLE_SPARKLE_SIGNING})"
        fi
    else
        log_failure "Required Sparkle.framework not found!"
        exit 1
    fi

    # Final check for Sparkle.framework in bundle
    if [ ! -d "${APP_PATH}/Contents/Frameworks/Sparkle.framework" ]; then
        log_failure "Sparkle.framework missing after assembly!"
        exit 1
    fi
    validate_sorty_app_linkage "${APP_PATH}"

    bundle_cli_tools "${RESOURCES_DIR}" "${BUILD_CONFIG}" "${BUILD_FLAGS_EXTRA}" ""

    # Embed Finder Sync extension
    if [ "${ENABLE_FINDER_EXTENSION}" = "true" ]; then
        bundle_finder_extension "${APP_PATH}" "${BUILD_CONFIG}"
    else
        rm -rf "${APP_PATH}/Contents/PlugIns/SortyFinderSync.appex"
        log_detail "Skipping Finder extension bundle (ENABLE_FINDER_EXTENSION=${ENABLE_FINDER_EXTENSION})"
    fi

    log_success "App bundle assembled ($(get_step_duration "assemble"))"
fi

# Icon variant selection — swap AppIcon.icns in the bundle based on context.
# APP_ICON_VARIANT accepts:
# - release/prod/production -> AppIcon-Release.icns
# - debug/dev/local        -> AppIcon-Debug.icns for local builds
# - anything else          -> AppIcon-CI.icns for CI builds
RAW_APP_ICON_VARIANT="${APP_ICON_VARIANT:-ci}"
APP_ICON_VARIANT_NORMALIZED="$(echo "${RAW_APP_ICON_VARIANT}" | tr '[:upper:]' '[:lower:]')"

case "${APP_ICON_VARIANT_NORMALIZED}" in
    release|prod|production)
        APP_ICON_VARIANT_KEY="release"
        ICON_VARIANT_SUFFIX="Release"
        ;;
    debug|dev|local)
        APP_ICON_VARIANT_KEY="debug"
        ICON_VARIANT_SUFFIX="Debug"
        ;;
    *)
        APP_ICON_VARIANT_KEY="ci"
        ICON_VARIANT_SUFFIX="CI"
        ;;
esac

ICON_SRC="${PROJECT_DIR}/Assets/AppIcon/AppIcon-${ICON_VARIANT_SUFFIX}.icns"
if [ ! -f "${ICON_SRC}" ]; then
    # Fallback: case-insensitive match
    for variant_file in "${PROJECT_DIR}/Assets/AppIcon/AppIcon-"*.icns; do
        base=$(basename "$variant_file" .icns)
        suffix="${base#AppIcon-}"
        if [ "$(echo "$suffix" | tr '[:upper:]' '[:lower:]')" = "$(echo "${APP_ICON_VARIANT_KEY}" | tr '[:upper:]' '[:lower:]')" ]; then
            ICON_SRC="$variant_file"
            break
        fi
    done
fi
if [ -f "${ICON_SRC}" ]; then
    cp "${ICON_SRC}" "${APP_PATH}/Contents/Resources/AppIcon.icns"
    rm -rf "${APP_PATH}/Contents/Resources/AppIcons"
    log_detail "App icon set to ${APP_ICON_VARIANT_KEY} variant"
else
    log_warning "Icon variant '${RAW_APP_ICON_VARIANT}' not found, using default"
fi

# Step 4: Signing (common for both build methods)
if [ "${ENABLE_ADHOC_SIGNING}" = "true" ]; then
    SIGNING_STEP_LABEL="Ad-hoc Signing"
    if [ "${SIGNING_IDENTITY}" != "-" ]; then
        SIGNING_STEP_LABEL="Code Signing"
    fi
    print_step 4 $TOTAL_STEPS "${SIGNING_STEP_LABEL}"
    start_step_timer "sign"

    ENTITLEMENTS_FILE="${PROJECT_DIR}/Sorty.entitlements"
    FINDER_SYNC_ENTITLEMENTS="${PROJECT_DIR}/SortyFinderSync/SortyFinderSync.entitlements"
    REPAIR_ENTITLEMENTS_FILE="${PROJECT_DIR}/Sources/SortyLib/Resources/SortyAppRepair.entitlements"

    validate_adhoc_entitlements "${ENTITLEMENTS_FILE}" "Sorty.entitlements"
    validate_adhoc_entitlements "${REPAIR_ENTITLEMENTS_FILE}" "SortyAppRepair.entitlements"

    # Sign inside-out: innermost components first, then the main app.
    # Do NOT use --deep as it re-signs inner components with wrong entitlements
    # and can produce invalid signatures on macOS 15+.

    # 1. Sign Sparkle framework helpers (innermost)
    FRAMEWORKS_DIR="${APP_PATH}/Contents/Frameworks"
    if [ -d "${FRAMEWORKS_DIR}/Sparkle.framework" ]; then
        sign_sparkle_framework "${FRAMEWORKS_DIR}/Sparkle.framework"
        log_detail "Signed Sparkle.framework"
    fi

    # 2. Sign the Finder Sync extension
    if [ -d "${APP_PATH}/Contents/PlugIns/SortyFinderSync.appex" ]; then
        if [ -f "${FINDER_SYNC_ENTITLEMENTS}" ]; then
            run_quiet_allow_failure codesign_cmd_allow_failure --entitlements "${FINDER_SYNC_ENTITLEMENTS}" "${APP_PATH}/Contents/PlugIns/SortyFinderSync.appex"
        else
            run_quiet_allow_failure codesign_cmd_allow_failure "${APP_PATH}/Contents/PlugIns/SortyFinderSync.appex"
        fi
        log_detail "Signed SortyFinderSync.appex"
    fi

    # 3. Sign the main app bundle (outermost — must be last)
    # Finder Sync depends on the containing app carrying the same sandbox/app-group
    # entitlements as the embedded extension. Do not silently strip them.
    if [ -f "${ENTITLEMENTS_FILE}" ]; then
        run_quiet codesign_cmd --entitlements "${ENTITLEMENTS_FILE}" "${APP_PATH}"
    else
        run_quiet codesign_cmd "${APP_PATH}"
    fi
    log_success "App signed ($(get_step_duration "sign"))"
else
    print_step 4 $TOTAL_STEPS "Skipping Code Signing"
    log_detail "ENABLE_ADHOC_SIGNING is set to false."
fi

# Close existing Sorty app instances unless an organization is active.
# Do this after build/sign so active work is interrupted only at handoff time.
terminate_running_sorty_if_safe

APP_SIZE=$(get_file_size "${APP_PATH}")

echo ""
print_divider "═" 50
echo ""

print_summary "Build Complete ${SYM_SPARKLE}" \
    "App" "${APP_PATH}" \
    "Size" "${APP_SIZE}" \
    "Version" "${VERSION} (build ${BUILD_NUM})" \
    "Duration" "$(get_total_duration)"
