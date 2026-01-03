#!/bin/bash

# FileOrganizer Build Script
# This script compiles the app and updates the macOS App Bundle.

# Exit on error
set -e

APP_NAME="FileOrganizer"
BINARY_NAME="FileOrganizerApp"
APP_BUNDLE="$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🚀 Building $APP_NAME..."

# 0. Auto-generate commit.txt from git
COMMIT_FILE="Resources/commit.txt"
if [ -d ".git" ]; then
    COMMIT_HASH=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    echo "$COMMIT_HASH" > "$COMMIT_FILE"
    echo "📝 Commit hash written to $COMMIT_FILE: ${COMMIT_HASH:0:9}"
elif [ -f "$COMMIT_FILE" ]; then
    echo "📝 Using existing commit.txt"
else
    echo "unknown" > "$COMMIT_FILE"
    echo "⚠️ Warning: Not a git repository, commit set to 'unknown'"
fi

# 1. Compile the project
if ! swift build; then
    echo "❌ Error: Build failed!"
    exit 1
fi

# 2. Get the binary path
BIN_PATH=$(swift build --show-bin-path)

# 3. Create bundle structure if missing
echo "📦 Updating $APP_BUNDLE content..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 4. Copy the fresh binary into the bundle
if [ -f "$BIN_PATH/$BINARY_NAME" ]; then
    cp "$BIN_PATH/$BINARY_NAME" "$MACOS_DIR/"
    echo "✅ Binary copied to $MACOS_DIR"
else
    echo "❌ Error: Binary not found at $BIN_PATH/$BINARY_NAME"
    exit 1
fi

# 5. Copy Info.plist
if [ -f "Info.plist" ]; then
    cp "Info.plist" "$CONTENTS_DIR/"
    echo "📄 Info.plist updated"
else
    echo "⚠️ Warning: Info.plist not found in project root"
fi

# 6. Copy commit.txt to Resources if it exists
if [ -f "$COMMIT_FILE" ]; then
    cp "$COMMIT_FILE" "$RESOURCES_DIR/"
    echo "📄 commit.txt copied to Resources"
fi

# 7. Sign the app (Ad-hoc) to prevent launch errors
echo "🔏 Signing $APP_BUNDLE..."
if codesign --force --deep --sign - "$APP_BUNDLE"; then
    echo "✅ Signing successful"
else
    echo "⚠️ Warning: Signing failed (this is common on some systems but may cause launch issues)"
fi

echo "✨ Build complete! Run with: make run"
