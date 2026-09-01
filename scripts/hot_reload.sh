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

run_hot_reload_command() {
    local log_name="$1"
    shift

    local log_file="${HOT_RELOAD_LOG_DIR}/${log_name}.log"
    if "$@" >"${log_file}" 2>&1; then
        return 0
    fi

    log_failure "${log_name} failed"
    log_item "Last 40 log lines (${log_file}):"
    tail -n 40 "${log_file}" || true
    return 1
}

run_hot_reload_build() {
    local log_name="$1"
    run_hot_reload_command "${log_name}" env \
        SORTY_HOT_RELOAD=true \
        SORTY_EMBEDDED_BUILD=true \
        APP_ICON_VARIANT=debug \
        SKIP_TESTS=true \
        BUILD_CONFIG=debug \
        "${SCRIPT_DIR}/build.sh"
}

format_hot_reload_runtime_output() {
    local skips_spotlight_continuation=false
    local line

    while IFS= read -r line || [ -n "${line}" ]; do
        line="${line%$'\r'}"
        case "${line}" in
            *"InjectionLite: Watching for source changes"*)
                log_success "Watching Sorty and ~/Library for source changes"
                ;;
            "NotificationManager: Using native macOS notifications")
                log_success "Native notifications ready"
                ;;
            *"failed to scan "*"Watch with Sorty.workflow: -10811"*)
                log_warning "Spotlight could not index Watch with Sorty.workflow (-10811)"
                skips_spotlight_continuation=true
                ;;
            *"from spotlight"*)
                if [ "${skips_spotlight_continuation}" = "true" ]; then
                    skips_spotlight_continuation=false
                else
                    printf '%s\n' "${line}"
                fi
                ;;
            *)
                skips_spotlight_continuation=false
                printf '%s\n' "${line}"
                ;;
        esac
    done
}

print_header "${PROJECT_NAME} Hot Reload" 50
print_summary "Session" \
    "Version" "$(get_version) ($(get_build_number))" \
    "Config" "debug/spm" \
    "Output" "${HOT_RELOAD_APP}"

mkdir -p "${HOT_RELOAD_LOG_DIR}"

print_step 1 4 "Preparing Runtime"
if run_hot_reload_command "hot_reload_runtime" \
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

script -q /dev/null env \
    INJECTION_DIRECTORIES="${PROJECT_DIR},${HOME}/Library" \
    "${HOT_RELOAD_APP}/Contents/MacOS/${PROJECT_NAME}" 2>&1 |
    format_hot_reload_runtime_output
