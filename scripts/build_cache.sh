#!/bin/bash
set -e
set -o pipefail

if [ -z "${PROJECT_DIR:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    # shellcheck source=scripts/config.sh
    source "${SCRIPT_DIR}/config.sh"
elif ! declare -f is_truthy >/dev/null 2>&1; then
    # shellcheck source=scripts/utils.sh
    source "${PROJECT_DIR}/scripts/utils.sh"
fi

BUILD_LOG_DIR="${BUILD_LOG_DIR:-${WORKSPACE_BUILD_DIR:-${PROJECT_DIR}/.build}/logs}"
AUTO_PRUNE_BUILD_CACHE="${AUTO_PRUNE_BUILD_CACHE:-true}"
BUILD_CACHE_VALIDATE_INPUTS="${BUILD_CACHE_VALIDATE_INPUTS:-true}"
BUILD_CACHE_MAX_SIZE_MB="${BUILD_CACHE_MAX_SIZE_MB:-8192}"
BUILD_CACHE_TARGET_SIZE_MB="${BUILD_CACHE_TARGET_SIZE_MB:-6144}"
BUILD_CACHE_STALE_DAYS="${BUILD_CACHE_STALE_DAYS:-7}"
BUILD_CACHE_PRUNE_INTERVAL_SECONDS="${BUILD_CACHE_PRUNE_INTERVAL_SECONDS:-86400}"
BUILD_CACHE_FORCE_PRUNE="${BUILD_CACHE_FORCE_PRUNE:-false}"
BUILD_CACHE_RESET_DEPENDENCIES_ON_PACKAGE_CHANGE="${BUILD_CACHE_RESET_DEPENDENCIES_ON_PACKAGE_CHANGE:-true}"
BUILD_CACHE_PRUNE_DEPENDENCIES_WHEN_OVERSIZED="${BUILD_CACHE_PRUNE_DEPENDENCIES_WHEN_OVERSIZED:-true}"
BUILD_CACHE_FINGERPRINT_VERSION="${BUILD_CACHE_FINGERPRINT_VERSION:-2}"
BUILD_CACHE_LOCK_STALE_SECONDS="${BUILD_CACHE_LOCK_STALE_SECONDS:-3600}"

BUILD_CACHE_STATE_DIR="${BUILD_DIR}/.sorty-cache"
BUILD_CACHE_STATE_FILE="${BUILD_CACHE_STATE_DIR}/state"
BUILD_CACHE_LAST_PRUNE_FILE="${BUILD_CACHE_STATE_DIR}/last-prune"
BUILD_CACHE_LOCK_DIR="${BUILD_CACHE_STATE_DIR}/maintenance.lock"

build_cache_now() {
    date +%s
}

build_cache_path_mtime() {
    local path="$1"
    stat -f %m "${path}" 2>/dev/null || stat -c %Y "${path}" 2>/dev/null || echo 0
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
    [ -e "${path}" ] || return 0
    rm -rf "${path}"
}

build_cache_hash_stream() {
    shasum -a 256 | awk '{print $1}'
}

build_cache_hash_files() {
    local rel_path
    for rel_path in "$@"; do
        local abs_path="${PROJECT_DIR}/${rel_path}"
        if [ -f "${abs_path}" ]; then
            printf '%s ' "${rel_path}"
            shasum -a 256 "${abs_path}" | awk '{print $1}'
        else
            printf '%s missing\n' "${rel_path}"
        fi
    done | build_cache_hash_stream
}

build_cache_dependency_hash() {
    local dependency_files=("Package.swift" "Package.resolved")

    if [ -d "${PROJECT_DIR}/Packages" ]; then
        while IFS= read -r package_file; do
            dependency_files+=("${package_file#${PROJECT_DIR}/}")
        done < <(find "${PROJECT_DIR}/Packages" -name "Package.swift" -type f | sort)
    fi

    build_cache_hash_files "${dependency_files[@]}"
}

build_cache_input_hash() {
    build_cache_hash_files \
        "Package.swift" \
        "Package.resolved" \
        "BuildConfig.xcconfig" \
        "Sorty.xcodeproj/project.pbxproj" \
        "Info.plist" \
        "Sorty.entitlements" \
        "SortyFinderSync/Info.plist" \
        "SortyFinderSync/SortyFinderSync.entitlements" \
        "scripts/build.sh" \
        "scripts/build_cache.sh" \
        "scripts/config.sh" \
        "scripts/utils.sh"
}

build_cache_toolchain_hash() {
    {
        printf 'fingerprint-version=%s\n' "${BUILD_CACHE_FINGERPRINT_VERSION}"
        printf 'swiftc='
        xcrun --find swiftc 2>/dev/null || command -v swiftc 2>/dev/null || printf 'unavailable\n'
        printf 'swift-version='
        xcrun swiftc -version 2>/dev/null || swiftc -version 2>/dev/null || printf 'unavailable\n'
        printf 'xcode-version='
        xcodebuild -version 2>/dev/null || printf 'unavailable\n'
        printf 'macos-sdk='
        xcrun --sdk macosx --show-sdk-path 2>/dev/null || printf 'unavailable\n'
    } | build_cache_hash_stream
}

build_cache_state_value() {
    local key="$1"
    [ -f "${BUILD_CACHE_STATE_FILE}" ] || return 0
    sed -n "s/^${key}=//p" "${BUILD_CACHE_STATE_FILE}" | head -1
}

build_cache_write_state() {
    local fingerprint="$1"
    local input_hash="$2"
    local dependency_hash="$3"
    local toolchain_hash="$4"

    mkdir -p "${BUILD_CACHE_STATE_DIR}"
    {
        printf 'fingerprint=%s\n' "${fingerprint}"
        printf 'input_hash=%s\n' "${input_hash}"
        printf 'dependency_hash=%s\n' "${dependency_hash}"
        printf 'toolchain_hash=%s\n' "${toolchain_hash}"
        printf 'build_method=%s\n' "${BUILD_METHOD:-spm}"
        printf 'build_config=%s\n' "${BUILD_CONFIG:-release}"
        printf 'build_archs=%s\n' "$(build_cache_fingerprint_archs)"
        printf 'updated_at=%s\n' "$(build_cache_now)"
    } > "${BUILD_CACHE_STATE_FILE}"
}

build_cache_fingerprint_archs() {
    if [ "${BUILD_METHOD:-spm}" = "xcodebuild" ]; then
        echo "${BUILD_ARCHS:-native}"
    else
        echo "spm-native"
    fi
}

build_cache_compiled_output_paths() {
    printf '%s\n' \
        "${BUILD_DIR}/DerivedData" \
        "${BUILD_DIR}/FinderSyncDerivedData" \
        "${BUILD_DIR}/debug" \
        "${BUILD_DIR}/release"

    if [ -d "${BUILD_DIR}" ]; then
        find "${BUILD_DIR}" -mindepth 1 -maxdepth 1 -type d -name '*-apple-macosx' -print 2>/dev/null || true
    fi
}

reset_cached_build_products() {
    local path
    while IFS= read -r path; do
        [ -n "${path}" ] || continue
        prune_path_if_exists "${path}"
    done < <(build_cache_compiled_output_paths)

    rm -f \
        "${BUILD_DIR}/.lock" \
        "${BUILD_DIR}/build.db" \
        "${BUILD_DIR}/build.db-journal" \
        "${BUILD_DIR}/build.db-shm" \
        "${BUILD_DIR}/build.db-wal"
}

reset_cached_dependency_products() {
    prune_path_if_exists "${BUILD_DIR}/checkouts"
    prune_path_if_exists "${BUILD_DIR}/repositories"
    prune_path_if_exists "${BUILD_DIR}/artifacts"
}

validate_build_cache_fingerprint() {
    if ! is_truthy "${BUILD_CACHE_VALIDATE_INPUTS}"; then
        log_detail "Skipping build cache validation (BUILD_CACHE_VALIDATE_INPUTS=${BUILD_CACHE_VALIDATE_INPUTS})"
        return 0
    fi

    local input_hash dependency_hash toolchain_hash fingerprint
    input_hash="$(build_cache_input_hash)"
    dependency_hash="$(build_cache_dependency_hash)"
    toolchain_hash="$(build_cache_toolchain_hash)"
    fingerprint="${BUILD_CACHE_FINGERPRINT_VERSION}:${toolchain_hash}:${input_hash}:${dependency_hash}:${BUILD_METHOD:-spm}:$(build_cache_fingerprint_archs)"

    local previous_fingerprint previous_dependency_hash
    previous_fingerprint="$(build_cache_state_value "fingerprint")"
    previous_dependency_hash="$(build_cache_state_value "dependency_hash")"

    if [ -z "${previous_fingerprint}" ]; then
        build_cache_write_state "${fingerprint}" "${input_hash}" "${dependency_hash}" "${toolchain_hash}"
        log_detail "Initialized build cache fingerprint"
        return 0
    fi

    if [ "${previous_fingerprint}" = "${fingerprint}" ]; then
        return 0
    fi

    log_item "Build cache inputs changed; clearing stale compiled outputs"
    reset_cached_build_products

    if [ "${previous_dependency_hash}" != "${dependency_hash}" ] && is_truthy "${BUILD_CACHE_RESET_DEPENDENCIES_ON_PACKAGE_CHANGE}"; then
        log_item "Package inputs changed; clearing SwiftPM dependency cache"
        reset_cached_dependency_products
    fi

    build_cache_write_state "${fingerprint}" "${input_hash}" "${dependency_hash}" "${toolchain_hash}"
}

build_cache_acquire_lock() {
    mkdir -p "${BUILD_CACHE_STATE_DIR}"
    if mkdir "${BUILD_CACHE_LOCK_DIR}" 2>/dev/null; then
        return 0
    fi

    local stale_seconds lock_mtime now
    stale_seconds="${BUILD_CACHE_LOCK_STALE_SECONDS}"
    if ! [[ "${stale_seconds}" =~ ^[0-9]+$ ]]; then
        stale_seconds=3600
    fi
    lock_mtime="$(build_cache_path_mtime "${BUILD_CACHE_LOCK_DIR}")"
    now="$(build_cache_now)"
    if [[ "${lock_mtime}" =~ ^[0-9]+$ ]] && [ $((now - lock_mtime)) -gt "${stale_seconds}" ]; then
        rm -rf "${BUILD_CACHE_LOCK_DIR}"
        if mkdir "${BUILD_CACHE_LOCK_DIR}" 2>/dev/null; then
            return 0
        fi
    fi

    log_detail "Another build cache maintenance pass is running; skipping this pass"
    return 1
}

build_cache_release_lock() {
    rmdir "${BUILD_CACHE_LOCK_DIR}" 2>/dev/null || true
}

build_cache_should_prune() {
    if is_truthy "${BUILD_CACHE_FORCE_PRUNE}"; then
        return 0
    fi

    local interval="${BUILD_CACHE_PRUNE_INTERVAL_SECONDS}"
    if ! [[ "${interval}" =~ ^[0-9]+$ ]]; then
        interval=86400
    fi
    if [ "${interval}" -eq 0 ]; then
        return 0
    fi
    if [ ! -f "${BUILD_CACHE_LAST_PRUNE_FILE}" ]; then
        return 0
    fi

    local last_prune now
    last_prune="$(cat "${BUILD_CACHE_LAST_PRUNE_FILE}" 2>/dev/null || echo 0)"
    now="$(build_cache_now)"
    if ! [[ "${last_prune}" =~ ^[0-9]+$ ]]; then
        return 0
    fi

    [ $((now - last_prune)) -ge "${interval}" ]
}

build_cache_record_prune() {
    mkdir -p "${BUILD_CACHE_STATE_DIR}"
    build_cache_now > "${BUILD_CACHE_LAST_PRUNE_FILE}"
}

prune_stale_build_cache_paths() {
    local stale_days="$1"
    [ -d "${BUILD_DIR}" ] || return 0

    find "${BUILD_DIR}" -mindepth 1 -maxdepth 1 -type d \
        \( -name "DerivedData" -o -name "FinderSyncDerivedData" -o -name "*-apple-macosx" -o -name "debug" -o -name "release" \) \
        -mtime +"${stale_days}" -exec rm -rf {} + 2>/dev/null || true

    find "${BUILD_DIR}/artifacts" -mindepth 1 -maxdepth 2 -type d \
        -mtime +"${stale_days}" -exec rm -rf {} + 2>/dev/null || true

    if [ -d "${BUILD_LOG_DIR}" ]; then
        find "${BUILD_LOG_DIR}" -type f -mtime +"${stale_days}" -exec rm -f {} + 2>/dev/null || true
    fi
}

run_optional_swift_package_clean() {
    if declare -f run_with_log >/dev/null 2>&1; then
        run_with_log --optional "swift_package_clean" swift package --package-path "${PROJECT_DIR}" --scratch-path "${BUILD_DIR}" clean || true
    else
        swift package --package-path "${PROJECT_DIR}" --scratch-path "${BUILD_DIR}" clean >/dev/null 2>&1 || true
    fi
}

prune_oversized_build_cache() {
    if ! is_truthy "${AUTO_PRUNE_BUILD_CACHE}"; then
        log_detail "Skipping build cache pruning (AUTO_PRUNE_BUILD_CACHE=${AUTO_PRUNE_BUILD_CACHE})"
        return 0
    fi

    if ! build_cache_should_prune; then
        return 0
    fi

    local max_size_mb="${BUILD_CACHE_MAX_SIZE_MB}"
    local target_size_mb="${BUILD_CACHE_TARGET_SIZE_MB}"
    local stale_days="${BUILD_CACHE_STALE_DAYS}"

    if ! [[ "${max_size_mb}" =~ ^[0-9]+$ ]]; then
        max_size_mb=8192
    fi
    if ! [[ "${target_size_mb}" =~ ^[0-9]+$ ]]; then
        target_size_mb=6144
    fi
    if ! [[ "${stale_days}" =~ ^[0-9]+$ ]]; then
        stale_days=7
    fi
    if [ "${target_size_mb}" -gt "${max_size_mb}" ]; then
        target_size_mb="${max_size_mb}"
    fi

    mkdir -p "${BUILD_DIR}"
    prune_stale_build_cache_paths "${stale_days}"

    local initial_size_mb
    initial_size_mb=$(get_directory_size_mb "${BUILD_DIR}")
    if [ "${initial_size_mb}" -le "${max_size_mb}" ]; then
        build_cache_record_prune
        log_detail "Build cache size ${initial_size_mb}MB is under ${max_size_mb}MB"
        return 0
    fi

    log_item "Pruning build cache (${initial_size_mb}MB > ${max_size_mb}MB)"

    reset_cached_build_products
    local current_size_mb
    current_size_mb=$(get_directory_size_mb "${BUILD_DIR}")

    if [ "${current_size_mb}" -gt "${target_size_mb}" ]; then
        run_optional_swift_package_clean
        current_size_mb=$(get_directory_size_mb "${BUILD_DIR}")
    fi

    if [ "${current_size_mb}" -gt "${target_size_mb}" ] && is_truthy "${BUILD_CACHE_PRUNE_DEPENDENCIES_WHEN_OVERSIZED}"; then
        reset_cached_dependency_products
        current_size_mb=$(get_directory_size_mb "${BUILD_DIR}")
    fi

    local reclaimed_mb=$((initial_size_mb - current_size_mb))
    if [ "${reclaimed_mb}" -gt 0 ]; then
        log_item "Reclaimed ${reclaimed_mb}MB from build cache (now ${current_size_mb}MB)"
    fi

    if [ "${current_size_mb}" -gt "${max_size_mb}" ]; then
        log_warning "Build cache remains large (${current_size_mb}MB). Lower BUILD_CACHE_STALE_DAYS or run make clean if needed."
    fi

    build_cache_record_prune
}

manage_build_cache() {
    mkdir -p "${BUILD_DIR}"

    if ! build_cache_acquire_lock; then
        return 0
    fi

    validate_build_cache_fingerprint || true
    prune_oversized_build_cache || true
    build_cache_release_lock
}

print_build_cache_status() {
    local size_mb
    size_mb=$(get_directory_size_mb "${BUILD_DIR}")
    local input_hash dependency_hash toolchain_hash current_fingerprint stored_fingerprint
    input_hash="$(build_cache_input_hash)"
    dependency_hash="$(build_cache_dependency_hash)"
    toolchain_hash="$(build_cache_toolchain_hash)"
    current_fingerprint="${BUILD_CACHE_FINGERPRINT_VERSION}:${toolchain_hash}:${input_hash}:${dependency_hash}:${BUILD_METHOD:-spm}:$(build_cache_fingerprint_archs)"
    stored_fingerprint="$(build_cache_state_value "fingerprint")"

    echo "Build cache"
    echo "  Path: ${BUILD_DIR}"
    echo "  Size: ${size_mb}MB"
    echo "  Max: ${BUILD_CACHE_MAX_SIZE_MB}MB"
    echo "  Target: ${BUILD_CACHE_TARGET_SIZE_MB}MB"
    echo "  Stale days: ${BUILD_CACHE_STALE_DAYS}"
    echo "  Prune interval: ${BUILD_CACHE_PRUNE_INTERVAL_SECONDS}s"
    echo "  Stored fingerprint: ${stored_fingerprint}"
    echo "  Current fingerprint: ${current_fingerprint}"
    echo "  Fresh: $([ "${stored_fingerprint}" = "${current_fingerprint}" ] && echo "yes" || echo "no")"
    echo "  Last prune: $(cat "${BUILD_CACHE_LAST_PRUNE_FILE}" 2>/dev/null || echo "never")"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-prune}" in
        prune)
            BUILD_CACHE_FORCE_PRUNE="${BUILD_CACHE_FORCE_PRUNE:-true}"
            manage_build_cache
            ;;
        status)
            print_build_cache_status
            ;;
        *)
            echo "Usage: $0 [prune|status]"
            exit 1
            ;;
    esac
fi
