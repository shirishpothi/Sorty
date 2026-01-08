#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

NEW_VERSION=$1

if [ -z "$NEW_VERSION" ]; then
    log_failure "Usage: $0 <version>"
    exit 1
fi

print_header "Bumping Version to ${NEW_VERSION}" 50

# 1. Update Info.plist
INFOPLIST="${PROJECT_DIR}/Info.plist"

if [ -f "$INFOPLIST" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${NEW_VERSION}" "$INFOPLIST"
    # Increment build number (assuming it's an integer)
    CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFOPLIST")
    if [[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
        NEW_BUILD=$((CURRENT_BUILD + 1))
    else
        NEW_BUILD=1
    fi
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEW_BUILD}" "$INFOPLIST"
    
    # Inject Git Commit Hash
    COMMIT_HASH=$(git rev-parse --short HEAD)
    /usr/libexec/PlistBuddy -c "Add :GitCommitHash string ${COMMIT_HASH}" "$INFOPLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :GitCommitHash ${COMMIT_HASH}" "$INFOPLIST"
    
    log_success "Updated Info.plist to Version ${NEW_VERSION} (Build ${NEW_BUILD}, Commit ${COMMIT_HASH})"
else
    log_failure "Info.plist not found at $INFOPLIST"
    exit 1
fi

# 2. Update Xcode Project (project.pbxproj)
# This is a bit more manual without agvtool, but sed works for simple cases
PROJECT_FILE="${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj/project.pbxproj"

if [ -f "$PROJECT_FILE" ]; then
    # Update MARKETING_VERSION
    sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = ${NEW_VERSION};/g" "$PROJECT_FILE"
    # Update CURRENT_PROJECT_VERSION
    sed -i '' "s/CURRENT_PROJECT_VERSION = .*;/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g" "$PROJECT_FILE"
    log_success "Updated project.pbxproj to Version ${NEW_VERSION} (Build ${NEW_BUILD})"
else
    log_failure "project.pbxproj not found at $PROJECT_FILE"
fi
