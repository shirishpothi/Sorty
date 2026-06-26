#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Symbols
SYM_CHECK="✔"
SYM_CROSS="✘"
SYM_WARN="⚠"
SYM_SPARKLE="✨"

is_truthy() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

SORTY_VERBOSE="${SORTY_VERBOSE:-false}"

# Timer functions
# Timer variables
ARCHIVE_START=0
BUILD_START=0
EXTRACT_START=0
ASSEMBLE_START=0
SIGN_START=0
TEST_START=0
FINDER_EXT_START=0

start_step_timer() {
    local step_name=$1
    local now=$(date +%s)
    case "$step_name" in
        archive) ARCHIVE_START=$now ;;
        build) BUILD_START=$now ;;
        extract) EXTRACT_START=$now ;;
        assemble) ASSEMBLE_START=$now ;;
        sign) SIGN_START=$now ;;
        test) TEST_START=$now ;;
        finder_ext) FINDER_EXT_START=$now ;;
    esac
}

get_step_duration() {
    local step_name=$1
    local start_time=0
    case "$step_name" in
        archive) start_time=$ARCHIVE_START ;;
        build) start_time=$BUILD_START ;;
        extract) start_time=$EXTRACT_START ;;
        assemble) start_time=$ASSEMBLE_START ;;
        sign) start_time=$SIGN_START ;;
        test) start_time=$TEST_START ;;
        finder_ext) start_time=$FINDER_EXT_START ;;
    esac
    
    if [[ $start_time -eq 0 ]]; then
        echo "0s"
        return
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    echo "${duration}s"
}

START_TIME=$(date +%s)
get_total_duration() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    echo "${duration}s"
}

# Info extraction
get_version() {
    # 1. Try Git Tag (Latest)
    local git_tag=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
    if [ -n "$git_tag" ]; then
        echo "$git_tag"
        return
    fi

    # 2. Fallback to Info.plist (Source of Truth for Dev/No Tag)
    /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${PROJECT_DIR}/Info.plist" 2>/dev/null || echo "1.0.0"
}

get_build_number() {
    # 1. Allow CI/manual overrides when a release pipeline wants an explicit build.
    if [ -n "${BUILD_NUMBER_OVERRIDE:-}" ]; then
        echo "${BUILD_NUMBER_OVERRIDE}"
        return
    fi

    # 2. Use Git commit count only when the repository is not shallow.
    # In shallow CI checkouts this frequently collapses to "1", which breaks
    # Sparkle version ordering in the published appcast.
    local is_shallow=$(git rev-parse --is-shallow-repository 2>/dev/null || echo "false")
    if [ "$is_shallow" != "true" ]; then
        local commit_count=$(git rev-list --count HEAD 2>/dev/null)
        if [ -n "$commit_count" ] && [ "$commit_count" -gt 0 ]; then
            echo "$commit_count"
            return
        fi
    fi

    # 3. Fallback to Info.plist
    /usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${PROJECT_DIR}/Info.plist" 2>/dev/null || echo "1"
}

get_file_size() {
    local file_path=$1
    local size_mb
    size_mb=$(du -sm "$file_path" | cut -f1)
    echo "${size_mb}MB"
}

# Logging functions
print_header() {
    local text=$1
    local width=$2
    echo ""
    print_divider "═" "$width"
    echo -e "${BLUE}  $text${NC}"
    print_divider "═" "$width"
    echo ""
}

print_divider() {
    local char=$1
    local width=$2
    printf -v line "%${width}s" ""
    echo "${line// /$char}"
}

print_step() {
    local step_num=$1
    local total_steps=$2
    local text=$3
    echo -e "${BLUE}[$step_num/$total_steps]${NC} $text..."
}

print_summary() {
    local title=$1
    shift
    echo -e "${BLUE}--- $title ---${NC}"
    while [ "$#" -gt 0 ]; do
        printf "  %-15s : %s\n" "$1" "$2"
        shift 2
    done
    echo ""
}

log_success() {
    echo -e "  ${GREEN}${SYM_CHECK} $1${NC}"
}

log_failure() {
    echo -e "  ${RED}${SYM_CROSS} $1${NC}"
}

log_warning() {
    echo -e "  ${YELLOW}${SYM_WARN} $1${NC}"
}

log_item() {
    echo -e "  • $1"
}

log_detail() {
    if is_truthy "${SORTY_VERBOSE}"; then
        echo -e "  • $1"
    fi
}

validate_sorty_app_linkage() {
    local app_path="$1"

    if [ ! -d "${app_path}" ]; then
        log_failure "App bundle not found at ${app_path}"
        return 1
    fi

    local info_plist="${app_path}/Contents/Info.plist"
    if [ ! -f "${info_plist}" ]; then
        log_failure "Info.plist missing from ${app_path}"
        return 1
    fi

    local executable_name
    executable_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "${info_plist}" 2>/dev/null || true)
    if [ -z "${executable_name}" ]; then
        log_failure "CFBundleExecutable missing from ${info_plist}"
        return 1
    fi

    local executable_path="${app_path}/Contents/MacOS/${executable_name}"
    if [ ! -x "${executable_path}" ]; then
        log_failure "Executable missing or not executable at ${executable_path}"
        return 1
    fi

    local sparkle_install_name
    sparkle_install_name=$(otool -L "${executable_path}" | awk '/Sparkle.framework\/Versions\/B\/Sparkle/ { print $1; exit }')
    if [ -z "${sparkle_install_name}" ]; then
        log_failure "${executable_name} is not linked against Sparkle.framework"
        return 1
    fi

    local sparkle_relative_path=""
    case "${sparkle_install_name}" in
        @executable_path/../Frameworks/*)
            sparkle_relative_path="${sparkle_install_name#@executable_path/../Frameworks/}"
            ;;
        @rpath/*)
            sparkle_relative_path="${sparkle_install_name#@rpath/}"
            ;;
        *)
            log_failure "${executable_name} links Sparkle from unexpected path: ${sparkle_install_name}"
            return 1
            ;;
    esac

    if [ "${sparkle_install_name}" = "@rpath/${sparkle_relative_path}" ] && ! otool -l "${executable_path}" | grep -F "@executable_path/../Frameworks" >/dev/null; then
        log_failure "${executable_name} is missing @executable_path/../Frameworks runpath for embedded frameworks"
        return 1
    fi

    local sparkle_binary="${app_path}/Contents/Frameworks/${sparkle_relative_path}"
    if [ ! -f "${sparkle_binary}" ]; then
        log_failure "Sparkle binary missing at ${sparkle_binary}"
        return 1
    fi

    if ! otool -D "${sparkle_binary}" | grep -F "Sparkle.framework/Versions/B/Sparkle" >/dev/null; then
        log_failure "Embedded Sparkle install name is invalid"
        return 1
    fi

    log_detail "App linkage verified"
}
