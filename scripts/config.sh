#!/bin/bash

# Project Settings
PROJECT_NAME="FileOrganiser"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="FileOrganiser"

# Build Paths
BUILD_DIR="${PROJECT_DIR}/.build"
RELEASE_DIR="${PROJECT_DIR}/releases"
ARCHIVE_PATH="${BUILD_DIR}/${PROJECT_NAME}.xcarchive"
APP_PATH="${RELEASE_DIR}/${PROJECT_NAME}.app"

# Import utilities
source "${PROJECT_DIR}/scripts/utils.sh"
