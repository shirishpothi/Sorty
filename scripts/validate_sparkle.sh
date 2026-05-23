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

check_tool() {
    local tool="$1"
    if ! command -v "$tool" >/dev/null 2>&1; then
        fail "Required tool not found: $tool"
    fi
}

check_tool xmllint

if [ ! -x /usr/libexec/PlistBuddy ]; then
    fail "Required tool not found: /usr/libexec/PlistBuddy"
fi

if [ ! -f "$PLIST_PATH" ]; then
    fail "Info.plist not found at $PLIST_PATH"
fi

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

    if [ -n "$PLIST_VERSION" ] && [ "$ENC_SHORT" != "$PLIST_VERSION" ]; then
        fail "Enclosure shortVersionString (${ENC_SHORT}) does not match Info.plist (${PLIST_VERSION})"
    fi

    if [ -n "$PLIST_BUILD" ] && [ "$ENC_VERSION" != "$PLIST_BUILD" ]; then
        fail "Enclosure version (${ENC_VERSION}) does not match Info.plist (${PLIST_BUILD})"
    fi
fi

if [ $ERRORS -gt 0 ]; then
    echo "Sparkle validation failed with $ERRORS error(s)."
    exit 1
fi

echo "Sparkle validation passed."
