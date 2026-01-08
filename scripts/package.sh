#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

print_header "Packaging Application" 50

# Ensure release directory exists
mkdir -p "${RELEASE_DIR}"

# 1. Create ZIP
print_step 1 2 "Creating ZIP Archive"
start_step_timer "zip"

ZIP_NAME="${PROJECT_NAME}.zip"
ZIP_PATH="${RELEASE_DIR}/${ZIP_NAME}"

if [ -d "${APP_PATH}" ]; then
    parent_dir=$(dirname "${APP_PATH}")
    app_name=$(basename "${APP_PATH}")
    
    pushd "$parent_dir" > /dev/null
    zip -r -y "$ZIP_PATH" "$app_name" > /dev/null
    popd > /dev/null
    
    if [ -f "$ZIP_PATH" ]; then
        log_success "Created $ZIP_NAME ($(get_file_size "$ZIP_PATH"))"
    else
        log_failure "Failed to create ZIP"
        exit 1
    fi
else
    log_failure "App not found at $APP_PATH"
    exit 1
fi

# 2. Create DMG
print_step 2 2 "Creating DMG Image"
start_step_timer "dmg"

DMG_NAME="${PROJECT_NAME}.dmg"
DMG_PATH="${RELEASE_DIR}/${DMG_NAME}"

# Check if create-dmg is installed
if ! command -v create-dmg &> /dev/null; then
    log_failure "create-dmg is not installed. Skipping DMG creation."
    log_item "Install with: brew install create-dmg"
else
    # Remove existing DMG
    rm -f "${DMG_PATH}"

    create-dmg \
      --volname "${PROJECT_NAME} Installer" \
      --volicon "${PROJECT_DIR}/Sorty app icon.png" \
      --window-pos 200 120 \
      --window-size 800 400 \
      --icon-size 100 \
      --icon "${PROJECT_NAME}.app" 200 190 \
      --hide-extension "${PROJECT_NAME}.app" \
      --app-drop-link 600 185 \
      "${DMG_PATH}" \
      "${APP_PATH}" 2>/dev/null >/dev/null || true

    if [ -f "${DMG_PATH}" ]; then
        log_success "Created $DMG_NAME ($(get_file_size "$DMG_PATH"))"
    else
        # If create-dmg fails (sometimes it does in CI/headless), warn but don't fail build if ZIP exists
        log_failure "DMG creation failed or was skipped."
    fi
fi

print_summary "Package Complete" \
    "ZIP" "$ZIP_PATH" \
    "DMG" "$DMG_PATH"
