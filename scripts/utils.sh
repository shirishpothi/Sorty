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

# Timer functions
# Timer variables
ARCHIVE_START=0
BUILD_START=0
EXTRACT_START=0
ASSEMBLE_START=0
SIGN_START=0

start_step_timer() {
    local step_name=$1
    if [[ "$step_name" == "archive" ]]; then ARCHIVE_START=$(date +%s); fi
    if [[ "$step_name" == "build" ]]; then BUILD_START=$(date +%s); fi
    if [[ "$step_name" == "extract" ]]; then EXTRACT_START=$(date +%s); fi
    if [[ "$step_name" == "assemble" ]]; then ASSEMBLE_START=$(date +%s); fi
    if [[ "$step_name" == "sign" ]]; then SIGN_START=$(date +%s); fi
}

get_step_duration() {
    local step_name=$1
    local start_time=0
    if [[ "$step_name" == "archive" ]]; then start_time=$ARCHIVE_START; fi
    if [[ "$step_name" == "build" ]]; then start_time=$BUILD_START; fi
    if [[ "$step_name" == "extract" ]]; then start_time=$EXTRACT_START; fi
    if [[ "$step_name" == "assemble" ]]; then start_time=$ASSEMBLE_START; fi
    if [[ "$step_name" == "sign" ]]; then start_time=$SIGN_START; fi
    
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
    # Extract version from Info.plist
    /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${PROJECT_DIR}/Info.plist"
}

get_build_number() {
    # Extract build number from Info.plist
    /usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${PROJECT_DIR}/Info.plist"
}

get_file_size() {
    local file_path=$1
    du -sh "$file_path" | cut -f1
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

log_item() {
    echo -e "  • $1"
}
