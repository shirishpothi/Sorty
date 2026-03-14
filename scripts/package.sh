#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

print_header "Packaging Application" 50

# Ensure release directory exists
mkdir -p "${RELEASE_DIR}"

REQUIRE_BUNDLED_CLI="${REQUIRE_BUNDLED_CLI:-true}"
ZIP_NAME="${ZIP_NAME_OVERRIDE:-${PROJECT_NAME}.zip}"
ZIP_PATH="${RELEASE_DIR}/${ZIP_NAME}"
IAP_PATH="${APP_PATH}/Contents/Resources/InternetAccessPolicy.plist"

# 1. Validate bundled CLI tools exist in app bundle
print_step 1 3 "Validating Bundled CLI Tools"
CLI_DIR="${APP_PATH}/Contents/Resources/CLI"
if [ "${REQUIRE_BUNDLED_CLI}" = "true" ]; then
    if [ ! -x "${CLI_DIR}/sorty" ] || [ ! -x "${CLI_DIR}/learnings" ]; then
        log_failure "Bundled CLI tools missing in ${CLI_DIR}. Build must bundle CLI tools into Sorty.app."
        exit 1
    else
        log_success "Bundled CLI tools verified"
    fi
else
    log_item "Skipping bundled CLI validation (REQUIRE_BUNDLED_CLI=${REQUIRE_BUNDLED_CLI})"
fi

# 2. Validate Internet Access Policy is bundled
print_step 2 3 "Validating Internet Access Policy"
if [ ! -f "${IAP_PATH}" ]; then
    log_failure "Missing InternetAccessPolicy.plist in app bundle at ${IAP_PATH}"
    exit 1
fi

if /usr/bin/plutil -lint "${IAP_PATH}" >/dev/null 2>&1; then
    log_success "InternetAccessPolicy.plist is bundled and valid"
else
    log_failure "InternetAccessPolicy.plist exists but is invalid"
    exit 1
fi

# 3. Create ZIP
print_step 3 3 "Creating Application Archive (ZIP)"
start_step_timer "zip"
rm -f "${ZIP_PATH}"

if [ ! -d "${APP_PATH}" ]; then
    log_failure "App bundle not found at ${APP_PATH}"
    exit 1
fi

ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

if [ -f "${ZIP_PATH}" ]; then
    log_success "Created ${ZIP_NAME} ($(get_file_size "${ZIP_PATH}"))"
else
    log_failure "ZIP creation failed"
fi

print_summary "Package Complete" \
    "ZIP" "${ZIP_PATH}" \
    "CLI (Bundled)" "${CLI_DIR}" \
    "IAP" "${IAP_PATH}"
