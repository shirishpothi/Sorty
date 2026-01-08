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
print_step 2 5 "Creating DMG Image"
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
        log_failure "DMG creation failed or was skipped."
    fi
fi

# 3. Create PKG
print_step 3 5 "Creating Installer Package (PKG)"
start_step_timer "pkg"
PKG_NAME="${PROJECT_NAME}.pkg"
PKG_PATH="${RELEASE_DIR}/${PKG_NAME}"

pkgbuild --root "${APP_PATH}" \
         --identifier "${APP_BUNDLE_ID}" \
         --version "$(get_version)" \
         --install-location "/Applications/${PROJECT_NAME}.app" \
         --component-plist "${PROJECT_DIR}/component.plist" \
         "${PKG_PATH}" 2>/dev/null || pkgbuild --root "${APP_PATH}" \
                                                --identifier "${APP_BUNDLE_ID}" \
                                                --version "$(get_version)" \
                                                --install-location "/Applications/${PROJECT_NAME}.app" \
                                                "${PKG_PATH}" > /dev/null

if [ -f "$PKG_PATH" ]; then
    log_success "Created $PKG_NAME ($(get_file_size "$PKG_PATH"))"
else
    log_failure "PKG creation failed"
fi

# 4. Create Source ZIP
print_step 4 5 "Creating Source Code Archive"
SRC_NAME="${PROJECT_NAME}-Source.zip"
SRC_PATH="${RELEASE_DIR}/${SRC_NAME}"

# Archive current HEAD
git archive -o "${SRC_PATH}" HEAD 2>/dev/null || true
if [ -f "$SRC_PATH" ]; then
    log_success "Created $SRC_NAME ($(get_file_size "$SRC_PATH"))"
else
    log_failure "Source archival failed"
fi

# 5. Create CLI Tools ZIP
print_step 5 5 "Creating CLI Tools Archive"
CLI_NAME="${PROJECT_NAME}-CLI.zip"
CLI_PATH="${RELEASE_DIR}/${CLI_NAME}"

# Gather CLI assets
CLI_TEMP="${RELEASE_DIR}/cli_temp"
mkdir -p "${CLI_TEMP}"
if [ -f "${PROJECT_DIR}/CLI/fileorg" ]; then
    cp "${PROJECT_DIR}/CLI/fileorg" "${CLI_TEMP}/"
fi
# Assuming we might want the swift tool binary if built?
# Since build.sh builds the app, we might need to explicitly build the tool or find it
# Let's try to grab it from .build if available, or just fileorg
# For now, just fileorg is key
pushd "${RELEASE_DIR}" >/dev/null
zip -r -y "${CLI_NAME}" "cli_temp" >/dev/null
popd >/dev/null
rm -rf "${CLI_TEMP}"

if [ -f "$CLI_PATH" ]; then
    log_success "Created $CLI_NAME ($(get_file_size "$CLI_PATH"))"
fi

print_summary "Package Complete" \
    "ZIP" "$ZIP_PATH" \
    "DMG" "$DMG_PATH" \
    "PKG" "$PKG_PATH" \
    "Src" "$SRC_PATH" \
    "CLI" "$CLI_PATH"
