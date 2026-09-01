#!/bin/bash
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

HOT_RELOAD_LOG_DIR="${BUILD_LOG_DIR:-${WORKSPACE_BUILD_DIR}/logs}"
HOT_RELOAD_COMMAND_DIR="${BUILD_DIR}/hot-reload/commands"
HOT_RELOAD_APP="${RELEASE_DIR}/${PROJECT_NAME}.app"
HOT_RELOAD_PREPARER="${BUILD_DIR}/debug/SortyHotReloadPreparer"
HOT_RELOAD_PLIST="/tmp/InjectionLite_Sorty_macOS_builds.plist"

run_hot_reload_build() {
    local log_name="$1"
    run_with_log "${log_name}" env \
        SORTY_HOT_RELOAD=true \
        SORTY_EMBEDDED_BUILD=true \
        APP_ICON_VARIANT=debug \
        SKIP_TESTS=true \
        BUILD_CONFIG=debug \
        "${SCRIPT_DIR}/build.sh"
}

print_header "${PROJECT_NAME} Hot Reload" 50
print_summary "Session" \
    "Version" "$(get_version) ($(get_build_number))" \
    "Config" "debug/spm" \
    "Output" "${HOT_RELOAD_APP}"

mkdir -p "${HOT_RELOAD_LOG_DIR}"

print_step 1 4 "Preparing Runtime"
if run_with_log "hot_reload_runtime" \
    swift build \
        --scratch-path "${BUILD_DIR}" \
        --disable-dependency-cache \
        -c debug \
        --product SortyHotReloadPreparer \
        --disable-sandbox; then
    log_success "Runtime ready"
fi

print_step 2 4 "Recording Compile Commands"
run_hot_reload_build "hot_reload_initial_build"
"${HOT_RELOAD_PREPARER}" "${BUILD_DIR}" >"${HOT_RELOAD_LOG_DIR}/hot_reload_objects.log"
log_success "Compile commands recorded"

print_step 3 4 "Relinking App"
run_hot_reload_build "hot_reload_relink"
swift "${SCRIPT_DIR}/prepare_hot_reload.swift" \
    "${PROJECT_DIR}" \
    "${HOT_RELOAD_COMMAND_DIR}" \
    "${HOT_RELOAD_PLIST}" \
    >"${HOT_RELOAD_LOG_DIR}/hot_reload_commands.log"
log_success "App ready for hot reload"

print_step 4 4 "Watching Source Files"
log_success "Hot reload active. Quit Sorty or press Control-C to stop."
echo ""

env INJECTION_PROJECT_ROOT="${PROJECT_DIR}" \
    "${HOT_RELOAD_APP}/Contents/MacOS/${PROJECT_NAME}"
