#!/bin/bash
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

APPCAST_PATH=""
PLIST_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --appcast)
            APPCAST_PATH="$2"
            shift 2
            ;;
        --plist)
            PLIST_PATH="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--appcast <path>] [--plist <path>]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ -z "$APPCAST_PATH" ]; then
    APPCAST_PATH="${PROJECT_DIR}/releases/appcast.xml"
fi
if [ -z "$PLIST_PATH" ]; then
    BUILT_APP_PLIST="${PROJECT_DIR}/releases/Sorty.app/Contents/Info.plist"
    if [ -f "$BUILT_APP_PLIST" ]; then
        PLIST_PATH="$BUILT_APP_PLIST"
    else
        PLIST_PATH="${PROJECT_DIR}/Info.plist"
    fi
fi

ERRORS=0

fail() {
    echo "ERROR: $1"
    ERRORS=$((ERRORS + 1))
}

sparkle_resources_dir() {
    local framework_path="$1"
    local current_resources="${framework_path}/Versions/Current/Resources"
    if [ -d "${current_resources}" ]; then
        echo "${current_resources}"
        return 0
    fi

    find "${framework_path}/Versions" -mindepth 2 -maxdepth 2 -type d -name Resources 2>/dev/null | head -1
}

sparkle_current_version_dir() {
    local framework_path="$1"
    local current_version="${framework_path}/Versions/Current"
    if [ -e "${current_version}" ]; then
        cd "${current_version}" 2>/dev/null && pwd -P
        return 0
    fi

    find "${framework_path}/Versions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1
}

require_hardened_runtime() {
    local bundle_path="$1"
    local description="$2"

    local signature
    signature=$(codesign -dv --verbose=4 "$bundle_path" 2>&1 || true)
    if ! echo "$signature" | grep -q 'runtime'; then
        fail "${description} must be signed with hardened runtime"
    fi
}

require_entitlement() {
    local bundle_path="$1"
    local entitlement_key="$2"
    local description="$3"
    local entitlements_file
    entitlements_file="$(mktemp)"

    codesign -d --entitlements :- "$bundle_path" >"${entitlements_file}" 2>/dev/null || true

    if ! /usr/libexec/PlistBuddy -c "Print :${entitlement_key}" "${entitlements_file}" >/dev/null 2>&1; then
        fail "${description} missing ${entitlement_key}"
    fi

    rm -f "${entitlements_file}"
}

check_tool() {
    local tool="$1"
    if ! command -v "$tool" >/dev/null 2>&1; then
        fail "Required tool not found: $tool"
    fi
}

check_tool xmllint
check_tool openssl

if [ ! -x /usr/libexec/PlistBuddy ]; then
    fail "Required tool not found: /usr/libexec/PlistBuddy"
fi

if [ ! -f "$PLIST_PATH" ]; then
    fail "Info.plist not found at $PLIST_PATH"
fi

APP_PATH="$(dirname "$(dirname "$PLIST_PATH")")"

PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST_PATH" 2>/dev/null || echo "")
PLIST_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST_PATH" 2>/dev/null || echo "")
FEED_URL=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$PLIST_PATH" 2>/dev/null || echo "")
PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$PLIST_PATH" 2>/dev/null || echo "")

if [ -z "$PLIST_VERSION" ]; then
    fail "CFBundleShortVersionString missing"
fi
if [ -z "$PLIST_BUILD" ]; then
    fail "CFBundleVersion missing"
fi

if [ -z "$FEED_URL" ]; then
    fail "SUFeedURL not set"
elif [[ ! "$FEED_URL" == https://* ]]; then
    fail "SUFeedURL must use https"
elif [[ ! "$(basename "$FEED_URL")" == appcast*.xml ]]; then
    fail "SUFeedURL must point to an appcast XML file"
fi

if [ -z "$PUBLIC_KEY" ]; then
    fail "SUPublicEDKey not set"
elif [ ${#PUBLIC_KEY} -ne 44 ]; then
    fail "SUPublicEDKey must be 44 characters (Ed25519 base64)"
fi

if [ ! -f "$APPCAST_PATH" ]; then
    fail "appcast.xml not found at $APPCAST_PATH"
else
    if ! xmllint --noout "$APPCAST_PATH" 2>/dev/null; then
        fail "appcast.xml is not valid XML"
    fi

    ITEM_COUNT=$(xmllint --xpath 'count(//item)' "$APPCAST_PATH" 2>/dev/null || echo "0")
    if [ "${ITEM_COUNT%.*}" -lt 1 ]; then
        fail "appcast.xml has no <item> entries"
    fi

    ENC_URL=$(xmllint --xpath 'string((//item)[1]/*[local-name()="enclosure"]/@url)' "$APPCAST_PATH" 2>/dev/null || echo "")
    ENC_TYPE=$(xmllint --xpath 'string((//item)[1]/*[local-name()="enclosure"]/@type)' "$APPCAST_PATH" 2>/dev/null || echo "")
    ENC_SIG=$(xmllint --xpath 'string((//item)[1]/*[local-name()="enclosure"]/@*[local-name()="edSignature"])' "$APPCAST_PATH" 2>/dev/null || echo "")
    ENC_SHORT=$(xmllint --xpath 'string((//item)[1]/*[local-name()="enclosure"]/@*[local-name()="shortVersionString"])' "$APPCAST_PATH" 2>/dev/null || echo "")
    ENC_VERSION=$(xmllint --xpath 'string((//item)[1]/*[local-name()="enclosure"]/@*[local-name()="version"])' "$APPCAST_PATH" 2>/dev/null || echo "")

    if [ -z "$ENC_URL" ]; then
        fail "Latest enclosure url missing"
    else
        if [[ ! "$ENC_URL" == https://* ]]; then
            fail "Enclosure url must use https"
        fi
        if [[ ! "$ENC_URL" == *"github.com"*"/releases/download/"* ]]; then
            fail "Enclosure url must point to GitHub releases download"
        fi
        if [[ ! "$ENC_URL" == *.zip ]]; then
            fail "Enclosure url must end with .zip"
        fi
    fi

    if [ "$ENC_TYPE" != "application/octet-stream" ]; then
        fail "Enclosure type must be application/octet-stream"
    fi

    if [ -z "$ENC_SIG" ]; then
        fail "Enclosure missing sparkle:edSignature"
    fi

    if [ -n "$ENC_SIG" ] && [ -n "$PUBLIC_KEY" ] && [ -n "$ENC_URL" ]; then
        ENC_FILE="${APPCAST_PATH%/*}/$(basename "$ENC_URL")"
        if [ ! -f "$ENC_FILE" ]; then
            fail "Enclosure ZIP not found next to appcast: $ENC_FILE"
        else
            PUBLIC_KEY_DER="$(mktemp)"
            SIGNATURE_FILE="$(mktemp)"
            if ! python3 - "$PUBLIC_KEY" "$ENC_SIG" "$PUBLIC_KEY_DER" "$SIGNATURE_FILE" <<'PY'
import base64
import pathlib
import sys

public_key, signature, public_key_der_path, signature_path = sys.argv[1:]
pathlib.Path(public_key_der_path).write_bytes(
    bytes.fromhex("302a300506032b6570032100") + base64.b64decode(public_key)
)
pathlib.Path(signature_path).write_bytes(base64.b64decode(signature))
PY
            then
                fail "Could not decode Sparkle public key or signature"
            elif ! openssl pkeyutl \
                -verify \
                -pubin \
                -inkey "$PUBLIC_KEY_DER" \
                -rawin \
                -in "$ENC_FILE" \
                -sigfile "$SIGNATURE_FILE" >/dev/null 2>&1; then
                PUBLIC_KEY_FINGERPRINT=$(printf '%s' "$PUBLIC_KEY" | shasum -a 256 | awk '{print substr($1, 1, 12)}')
                SIGNATURE_FINGERPRINT=$(printf '%s' "$ENC_SIG" | shasum -a 256 | awk '{print substr($1, 1, 12)}')
                echo "Sparkle public key fingerprint: ${PUBLIC_KEY_FINGERPRINT}"
                echo "Sparkle signature fingerprint: ${SIGNATURE_FINGERPRINT}"
                fail "Enclosure Sparkle signature does not verify with SUPublicEDKey"
            fi
            rm -f "$PUBLIC_KEY_DER" "$SIGNATURE_FILE"
        fi
    fi

    if [ -n "$PLIST_VERSION" ] && [ "$ENC_SHORT" != "$PLIST_VERSION" ]; then
        fail "Enclosure shortVersionString (${ENC_SHORT}) does not match Info.plist (${PLIST_VERSION})"
    fi

    if [ -n "$PLIST_BUILD" ] && [ "$ENC_VERSION" != "$PLIST_BUILD" ]; then
        fail "Enclosure version (${ENC_VERSION}) does not match Info.plist (${PLIST_BUILD})"
    fi
fi

if [ -d "$APP_PATH" ]; then
    require_hardened_runtime "$APP_PATH" "Sorty.app"
    require_entitlement \
        "$APP_PATH" \
        "com.apple.security.cs.disable-library-validation" \
        "Sorty.app"

    SPARKLE_FRAMEWORK="${APP_PATH}/Contents/Frameworks/Sparkle.framework"
    SPARKLE_RESOURCES="$(sparkle_resources_dir "$SPARKLE_FRAMEWORK")"
    SPARKLE_VERSION_DIR="$(sparkle_current_version_dir "$SPARKLE_FRAMEWORK")"
    UPDATER_PATH=""
    AUTOUPDATE_PATH=""

    for candidate in \
        "${SPARKLE_RESOURCES}/Updater.app" \
        "${SPARKLE_VERSION_DIR}/Updater.app"; do
        if [ -d "$candidate" ]; then
            UPDATER_PATH="$candidate"
            break
        fi
    done

    for candidate in \
        "${SPARKLE_RESOURCES}/Autoupdate.app" \
        "${SPARKLE_VERSION_DIR}/Autoupdate.app" \
        "${SPARKLE_VERSION_DIR}/Autoupdate"; do
        if [ -e "$candidate" ]; then
            AUTOUPDATE_PATH="$candidate"
            break
        fi
    done

    if [ -n "$UPDATER_PATH" ]; then
        require_hardened_runtime "$UPDATER_PATH" "Sparkle Updater.app"
    else
        fail "Sparkle Updater.app missing from embedded framework"
    fi

    if [ -n "$AUTOUPDATE_PATH" ]; then
        require_hardened_runtime "$AUTOUPDATE_PATH" "Sparkle Autoupdate"
    else
        fail "Sparkle Autoupdate missing from embedded framework"
    fi

    while IFS= read -r -d '' xpc_service; do
        require_hardened_runtime "$xpc_service" "Sparkle XPC service $(basename "$xpc_service")"
    done < <(find "$SPARKLE_FRAMEWORK" -path "*/XPCServices/*.xpc" -type d -print0 2>/dev/null)
fi

if [ $ERRORS -gt 0 ]; then
    echo "Sparkle validation failed with $ERRORS error(s)."
    exit 1
fi

echo "Sparkle validation passed."
