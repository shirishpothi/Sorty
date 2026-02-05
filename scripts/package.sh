#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

print_header "Packaging Application" 50

# Ensure release directory exists
mkdir -p "${RELEASE_DIR}"

# 1. Validate bundled CLI tools exist in app bundle
print_step 1 2 "Validating Bundled CLI Tools"
CLI_DIR="${APP_PATH}/Contents/Resources/CLI"
if [ ! -x "${CLI_DIR}/sorty" ] || [ ! -x "${CLI_DIR}/learnings" ]; then
    log_failure "Bundled CLI tools missing in ${CLI_DIR}. Build must bundle CLI tools into Sorty.app."
    exit 1
else
    log_success "Bundled CLI tools verified"
fi

# 2. Create PKG
print_step 2 2 "Creating Installer Package (PKG)"
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

print_summary "Package Complete" \
    "PKG" "$PKG_PATH" \
    "CLI (Bundled)" "$CLI_DIR"
