#!/bin/bash

# Project Settings
PROJECT_NAME="Sorty"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="FileOrganiser"

# Build Paths
BUILD_DIR="${PROJECT_DIR}/.build"
RELEASE_DIR="${PROJECT_DIR}/releases"
ARCHIVE_PATH="${BUILD_DIR}/${PROJECT_NAME}.xcarchive"
APP_PATH="${RELEASE_DIR}/${PROJECT_NAME}.app"

# Signing & Notarization
APP_BUNDLE_ID="com.shirishpothi.Sorty"
TEAM_ID="XXXXXXXXXX" # Replace with actual Team ID
NOTARIZATION_USERNAME="" # Optional: Set in env or Keychain
NOTARIZATION_PASSWORD="" # Optional: Set in env or Keychain
KEYCHAIN_PROFILE=""      # Optional: For xcrun notarytool --keychain-profile

# Import utilities
source "${PROJECT_DIR}/scripts/utils.sh"
