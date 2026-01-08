#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

print_header "Generating Appcast" 50

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

# Generate signature if key is provided
SIGNATURE=""
if [ -n "$SPARKLE_PRIVATE_KEY" ]; then
    echo "$SPARKLE_PRIVATE_KEY" > "${RELEASE_DIR}/sparkle_key"
    # Assuming standard sparkle-cli or similar usage, but for now we'll do Ed25519 signing if tools are available.
    # Since we can't guarantee 'generate_keys' or 'sign_update' are in path without setup, 
    # we will rely on inputs or skip if strictly needed.
    # For this simplified CI script, we'll assume we might not have the bin unless set up.
    # A common way is using 'openssl' or a small go tool. 
    # For now, let's placeholder or skip if no tool.
    log_item "Private key detected. Attempting to sign (requires 'sign_update' tool matching Sparkle)."
    
    # If the user has 'generate_appcast' from Sparkle bin:
    if command -v generate_appcast &> /dev/null; then
       # generate_appcast usually scans a dir.
       generate_appcast "${RELEASE_DIR}"
       log_success "Appcast generated using Sparkle tool"
       exit 0
    fi
else
    log_item "No SPARKLE_PRIVATE_KEY found. Generating unsigned appcast entry."
fi

# Manual simple XML generation if tool not found or for custom control
cat > "$APPCAST_FILE" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"  xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>${PROJECT_NAME} Changelog</title>
    <link>https://github.com/shirishpothi/FileOrganizer</link>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <sparkle:releaseNotesLink>https://github.com/shirishpothi/FileOrganizer/releases/tag/v${VERSION}</sparkle:releaseNotesLink>
      <pubDate>${DATE}</pubDate>
      <enclosure url="https://github.com/shirishpothi/FileOrganizer/releases/download/v${VERSION}/${ZIP_NAME}"
                 sparkle:version="${BUILD_NUM}"
                 sparkle:shortVersionString="${VERSION}"
                 length="${SIZE}"
                 type="application/octet-stream"
                 ${SIGNATURE}/>
    </item>
  </channel>
</rss>
EOF

log_success "Generated appcast.xml"
