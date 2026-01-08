#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

print_header "Notarizing Application" 50

# Check inputs
if [ -z "$NOTARIZATION_USERNAME" ] || [ -z "$NOTARIZATION_PASSWORD" ] && [ -z "$KEYCHAIN_PROFILE" ]; then
    log_failure "Missing notarization credentials."
    log_item "Set NOTARIZATION_USERNAME and NOTARIZATION_PASSWORD in config or env."
    log_item "Or set KEYCHAIN_PROFILE."
    exit 1
fi

ZIP_NAME="${PROJECT_NAME}.zip"
ZIP_PATH="${RELEASE_DIR}/${ZIP_NAME}"
DMG_NAME="${PROJECT_NAME}.dmg"
DMG_PATH="${RELEASE_DIR}/${DMG_NAME}"

# Prefer DMG if it exists, otherwise ZIP
TARGET_PATH=""
if [ -f "$DMG_PATH" ]; then
    TARGET_PATH="$DMG_PATH"
elif [ -f "$ZIP_PATH" ]; then
    TARGET_PATH="$ZIP_PATH"
else
    log_failure "No artifact found to notarize (checked $DMG_NAME and $ZIP_NAME)"
    exit 1
fi

print_step 1 2 "Submitting to Apple Notary Service"
start_step_timer "notarize"

log_item "Target: $(basename "$TARGET_PATH")"
log_item "Bundle ID: $APP_BUNDLE_ID"

if [ -n "$KEYCHAIN_PROFILE" ]; then
    xcrun notarytool submit "$TARGET_PATH" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait 2>&1 | tee "${RELEASE_DIR}/notarization_log.txt"
else
    xcrun notarytool submit "$TARGET_PATH" \
        --apple-id "$NOTARIZATION_USERNAME" \
        --password "$NOTARIZATION_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait 2>&1 | tee "${RELEASE_DIR}/notarization_log.txt"
fi

# Check success
if grep -q "Accepted" "${RELEASE_DIR}/notarization_log.txt"; then
    log_success "Notarization accepted ($(get_step_duration "notarize"))"
else
    log_failure "Notarization failed. Check log at ${RELEASE_DIR}/notarization_log.txt"
    exit 1
fi

print_step 2 2 "Stapling Ticket"
start_step_timer "staple"

if [[ "$TARGET_PATH" == *".dmg" ]]; then
    xcrun stapler staple "$TARGET_PATH"
    log_success "Stapled to DMG"
else
    # For ZIP, strictly speaking we staple the app then re-zip, but notarytool workflow often implies just checking validity.
    # Stapling to ZIP isn't possible directly. One must staple the app bundle.
    # If we are notarizing ZIP of app, successful notarization is enough for distribution often, 
    # but Gatekeeper likes stapled apps. 
    # Logic: If ZIP, we assume the user might unzip and run. If we want staple, we should have stapled the APP before zipping.
    # But we notarize the archive.
    # Correct flow: Build -> Sign -> Zip -> Notarize Zip (Wait) -> (Cannot staple zip).
    # If we want stapling, we generally notarize the .dmg.
    log_item "Skipping staple for ZIP file (not supported directly on ZIP)."
fi

log_success "Notarization complete"
