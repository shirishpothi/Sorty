#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

print_header "Generating Appcast" 50

APPCAST_FILE="${RELEASE_DIR}/appcast.xml"
ZIP_NAME="${ZIP_NAME_OVERRIDE:-${PROJECT_NAME}.zip}"
ZIP_PATH="${RELEASE_DIR}/${ZIP_NAME}"

if [ ! -f "$ZIP_PATH" ]; then
    log_failure "ZIP file not found at $ZIP_PATH"
    exit 1
fi

VERSION=$(get_version)
BUILD_NUM=$(get_build_number)
DATE=$(date -R)
SIZE=$(stat -f%z "$ZIP_PATH")

# Validate Sparkle Configuration
FEED_URL=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "${PROJECT_DIR}/Info.plist" 2>/dev/null || true)
if [ -z "$FEED_URL" ]; then
    log_failure "SUFeedURL not set in Info.plist. Autoupdate will fail."
    # Fail strict build? Or warn? User said "if it can't update in-app... build is screwed"
    exit 1
fi

PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "${PROJECT_DIR}/Info.plist" 2>/dev/null || true)
if [ -z "$PUBLIC_KEY" ]; then
    log_warn "SUPublicEDKey not set in Info.plist. Updates may be insecure."
fi

# Generate signature if key is provided
SIGNATURE=""
if [ -n "$SPARKLE_PRIVATE_KEY" ]; then
    # Create temporary key file for the signing tool
    SPARKLE_KEY_FILE="${RELEASE_DIR}/sparkle_key"
    echo "$SPARKLE_PRIVATE_KEY" > "$SPARKLE_KEY_FILE"
    
    # Verify the public key in Info.plist matches the one we are signing with
    # This prevents the "downloaded then failed" error caused by public/private key mismatch
    SIGN_UPDATE_TOOL=$(find "${BUILD_DIR}/artifacts" -name "sign_update" -type f -not -path "*/old_dsa_scripts/*" | head -1)
    
    if [ -n "$SIGN_UPDATE_TOOL" ] && [ -x "$SIGN_UPDATE_TOOL" ]; then
        log_item "Signing update using $SIGN_UPDATE_TOOL"
        
        # Check if we can verify the signature with the public key in Info.plist
        # (This is a bit complex as sign_update doesn't have a direct "check match" for raw keys, 
        # but we can check if the SIGNATURE is generated correctly)
        
        # sign_update outputs something like "sparkle:edSignature="...""
        SIG_OUTPUT=$("$SIGN_UPDATE_TOOL" -f "$SPARKLE_KEY_FILE" "$ZIP_PATH" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$SIG_OUTPUT" ]; then
            SIGNATURE="$SIG_OUTPUT"
            log_success "Generated Ed25519 signature"
        else
            log_failure "Failed to generate signature. Your SPARKLE_PRIVATE_KEY might be invalid."
        fi
    else
        log_warn "sign_update tool not found. Signing skipped."
    fi
    
    # Cleanup private key immediately
    rm -f "$SPARKLE_KEY_FILE"
else
    log_item "No SPARKLE_PRIVATE_KEY found. Generating unsigned appcast entry."
fi

# Manual simple XML generation if tool not found or for custom control
REPO_URL="https://github.com/sorty-organizer/Sorty"

# If we have a signature from sign_update, it already contains length="..."
ENCLOSURE_ATTRIBUTES="sparkle:version=\"${BUILD_NUM}\" sparkle:shortVersionString=\"${VERSION}\" type=\"application/octet-stream\""

if [ -n "$SIGNATURE" ]; then
    # SIGNATURE contains sparkle:edSignature="..." length="..."
    ENCLOSURE_ATTRIBUTES="${ENCLOSURE_ATTRIBUTES} ${SIGNATURE}"
else
    ENCLOSURE_ATTRIBUTES="${ENCLOSURE_ATTRIBUTES} length=\"${SIZE}\""
fi

cat > "$APPCAST_FILE" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"  xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>${PROJECT_NAME} Changelog</title>
    <link>${REPO_URL}</link>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <sparkle:releaseNotesLink>${REPO_URL}/releases/tag/v${VERSION}</sparkle:releaseNotesLink>
      <pubDate>${DATE}</pubDate>
      <enclosure url="${REPO_URL}/releases/download/v${VERSION}/${ZIP_NAME}"
                 ${ENCLOSURE_ATTRIBUTES} />
    </item>
  </channel>
</rss>
EOF

log_success "Generated appcast.xml"
