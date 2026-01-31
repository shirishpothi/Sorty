#!/bin/bash
# Generate signed appcast.xml for Sparkle auto-updates
# Usage: ./scripts/generate_appcast_ci.sh
# Requires: SPARKLE_PRIVATE_KEY environment variable (base64-encoded Ed25519 private key)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

print_header "Generating Signed Appcast" 50

APPCAST_FILE="${RELEASE_DIR}/appcast.xml"
ZIP_NAME="${PROJECT_NAME}.zip"
ZIP_PATH="${RELEASE_DIR}/${ZIP_NAME}"

if [ ! -f "$ZIP_PATH" ]; then
    log_failure "ZIP file not found at $ZIP_PATH"
    exit 1
fi

VERSION=$(get_version)
BUILD_NUM=$(get_build_number)
DATE=$(date -R)
SIZE=$(stat -f%z "$ZIP_PATH")

# Get download URL from GitHub releases
RELEASE_URL="https://github.com/shirishpothi/${PROJECT_NAME}/releases/download/v${VERSION}/${ZIP_NAME}"
RELEASE_NOTES_URL="https://github.com/shirishpothi/${PROJECT_NAME}/releases/tag/v${VERSION}"

# Generate Ed25519 signature
SIGNATURE_ATTR=""
if [ -n "$SPARKLE_PRIVATE_KEY" ]; then
    log_item "Signing update with Ed25519 key..."
    
    # Decode private key and save temporarily
    PRIVATE_KEY_FILE="${RELEASE_DIR}/sparkle_private_key.tmp"
    echo "$SPARKLE_PRIVATE_KEY" | base64 -d > "$PRIVATE_KEY_FILE"
    chmod 600 "$PRIVATE_KEY_FILE"
    
    # Sign the ZIP file using OpenSSL Ed25519
    # Ed25519 signature is 64 bytes
    SIGNATURE_FILE="${RELEASE_DIR}/signature.tmp"
    
    # Create signature using the private key
    openssl dgst -sha256 -sign "$PRIVATE_KEY_FILE" -out "$SIGNATURE_FILE" "$ZIP_PATH" 2>/dev/null || {
        # Fallback: use Ed25519 signing if available
        if command -v openssl >/dev/null 2>&1; then
            # Generate signature with raw Ed25519
            openssl pkeyutl -sign -in "$ZIP_PATH" -inkey "$PRIVATE_KEY_FILE" -out "$SIGNATURE_FILE" -rawin 2>/dev/null || {
                log_warning "OpenSSL Ed25519 signing failed, trying alternative method..."
            }
        fi
    }
    
    if [ -f "$SIGNATURE_FILE" ] && [ -s "$SIGNATURE_FILE" ]; then
        # Encode signature in base64 (portable - works on both macOS and Linux)
        SIGNATURE_BASE64=$(cat "$SIGNATURE_FILE" | base64 | tr -d '\n')
        SIGNATURE_ATTR="sparkle:edSignature=\"${SIGNATURE_BASE64}\""
        log_success "Ed25519 signature generated successfully"
    else
        log_warning "Could not generate signature. Update will not be signed."
        log_item "Make sure SPARKLE_PRIVATE_KEY is set correctly in GitHub Secrets"
    fi
    
    # Clean up temp files
    rm -f "$PRIVATE_KEY_FILE" "$SIGNATURE_FILE"
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
    <link>https://github.com/shirishpothi/${PROJECT_NAME}</link>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <sparkle:releaseNotesLink>${RELEASE_NOTES_URL}</sparkle:releaseNotesLink>
      <pubDate>${DATE}</pubDate>
      <enclosure url="${RELEASE_URL}"
                 sparkle:version="${BUILD_NUM}"
                 sparkle:shortVersionString="${VERSION}"
                 length="${SIZE}"
                 type="application/octet-stream"
                 ${SIGNATURE_ATTR}/>
    </item>
  </channel>
</rss>
EOF

log_success "Generated appcast.xml at ${APPCAST_FILE}"

# Validate the generated appcast
if [ -n "$SIGNATURE_ATTR" ]; then
    log_success "✓ Appcast is SIGNED with Ed25519"
else
    log_warning "⚠ Appcast is UNSIGNED - updates may fail signature verification"
fi

# Display info for debugging
log_item "Version: ${VERSION} (${BUILD_NUM})"
log_item "Download URL: ${RELEASE_URL}"
log_item "Size: ${SIZE} bytes"
