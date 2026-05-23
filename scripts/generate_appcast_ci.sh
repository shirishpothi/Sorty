#!/bin/bash
# Generate signed appcast.xml for Sparkle auto-updates in CI
# Usage: ./scripts/generate_appcast_ci.sh
# Requires: SPARKLE_PRIVATE_KEY environment variable (Sparkle private key from generate_keys)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

print_header "Generating Signed Appcast" 50

APPCAST_FILE="${APPCAST_FILE_OVERRIDE:-${RELEASE_DIR}/appcast.xml}"
ZIP_NAME="${ZIP_NAME_OVERRIDE:-${PROJECT_NAME}.zip}"
ZIP_PATH="${RELEASE_DIR}/${ZIP_NAME}"

if [ ! -f "$ZIP_PATH" ]; then
    log_failure "ZIP file not found at $ZIP_PATH"
    exit 1
fi

APP_PLIST="${RELEASE_DIR}/${PROJECT_NAME}.app/Contents/Info.plist"

# Prefer the merged release app's version/build so appcast metadata matches
# what validate_sparkle.sh reads from releases/Sorty.app.
if [ -f "${APP_PLIST}" ]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PLIST}" 2>/dev/null || true)
    BUILD_NUM=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${APP_PLIST}" 2>/dev/null || true)
fi

VERSION="${APPCAST_VERSION:-${VERSION:-$(get_version)}}"
BUILD_NUM="${APPCAST_BUILD_NUM:-${BUILD_NUM:-$(get_build_number)}}"
DATE=$(date -R)
SIZE=$(stat -f%z "$ZIP_PATH")

# Get download URL from GitHub releases
REPOSITORY="${APPCAST_REPOSITORY:-${GITHUB_REPOSITORY:-shirishpothi/${PROJECT_NAME}}}"
RELEASE_TAG="${APPCAST_RELEASE_TAG:-v${VERSION}}"
RELEASE_URL="https://github.com/${REPOSITORY}/releases/download/${RELEASE_TAG}/${ZIP_NAME}"
RELEASE_NOTES_URL="${APPCAST_RELEASE_NOTES_URL:-https://github.com/${REPOSITORY}/releases/tag/${RELEASE_TAG}}"
APPCAST_ITEM_TITLE="${APPCAST_ITEM_TITLE:-Version ${VERSION}}"
APPCAST_CHANNEL="${APPCAST_CHANNEL:-}"
APPCAST_LINK="${APPCAST_LINK:-https://github.com/${REPOSITORY}}"

# Generate Ed25519 signature using Sparkle's sign_update tool
ENCLOSURE_EXTRA_ATTR="length=\"${SIZE}\""
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
    log_item "Signing update with Sparkle sign_update..."

    PRIVATE_KEY_FILE="${RELEASE_DIR}/sparkle_private_key.tmp"
    printf '%s' "$SPARKLE_PRIVATE_KEY" > "$PRIVATE_KEY_FILE"
    chmod 600 "$PRIVATE_KEY_FILE"

    SIGN_UPDATE_TOOL=$(find "${BUILD_DIR}/artifacts" -name "sign_update" -type f -not -path "*/old_dsa_scripts/*" | head -1)

    if [ -n "$SIGN_UPDATE_TOOL" ] && [ -x "$SIGN_UPDATE_TOOL" ]; then
        SIGNATURE_OUTPUT=$("$SIGN_UPDATE_TOOL" -f "$PRIVATE_KEY_FILE" "$ZIP_PATH" 2>/dev/null || true)
        if echo "$SIGNATURE_OUTPUT" | grep -q 'sparkle:edSignature='; then
            ENCLOSURE_EXTRA_ATTR=$(echo "$SIGNATURE_OUTPUT" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')
            log_success "Ed25519 signature generated successfully"
        else
            log_warning "Could not generate signature. Update will not be signed."
            log_item "Check that SPARKLE_PRIVATE_KEY matches Info.plist SUPublicEDKey"
        fi
    else
        log_warning "Sparkle sign_update tool not found. Update will not be signed."
        log_item "Build artifacts must include Sparkle tools under .build/artifacts"
    fi

    rm -f "$PRIVATE_KEY_FILE"
else
    log_warning "No SPARKLE_PRIVATE_KEY found. Generating unsigned appcast."
    log_item "Set SPARKLE_PRIVATE_KEY in GitHub Secrets to enable signed updates"
fi

# Generate the appcast XML
cat > "$APPCAST_FILE" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>${PROJECT_NAME} Changelog</title>
    <link>${APPCAST_LINK}</link>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
    <item>
      <title>${APPCAST_ITEM_TITLE}</title>
$(if [ -n "${APPCAST_CHANNEL}" ]; then printf '      <sparkle:channel>%s</sparkle:channel>\n' "${APPCAST_CHANNEL}"; fi)
      <sparkle:releaseNotesLink>${RELEASE_NOTES_URL}</sparkle:releaseNotesLink>
      <pubDate>${DATE}</pubDate>
      <enclosure url="${RELEASE_URL}"
                 sparkle:version="${BUILD_NUM}"
                 sparkle:shortVersionString="${VERSION}"
                 type="application/octet-stream"
                 ${ENCLOSURE_EXTRA_ATTR}/>
    </item>
  </channel>
</rss>
EOF

log_success "Generated appcast.xml at ${APPCAST_FILE}"

# Validate the generated appcast
if echo "$ENCLOSURE_EXTRA_ATTR" | grep -q 'sparkle:edSignature='; then
    log_success "✓ Appcast is SIGNED with Ed25519"
else
    log_warning "⚠ Appcast is UNSIGNED - updates may fail signature verification"
fi

# Display info for debugging
log_item "Version: ${VERSION} (${BUILD_NUM})"
log_item "Download URL: ${RELEASE_URL}"
log_item "Size: ${SIZE} bytes"
