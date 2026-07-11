#!/bin/bash
set -euo pipefail

INPUT_PATH="$(cd "$(dirname "${1:-releases/Sorty.app}")" && pwd)/$(basename "${1:-releases/Sorty.app}")"
TEMP_DIR=""

if [[ "${INPUT_PATH}" == *.zip ]]; then
    TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sorty-launch-smoke.XXXXXX")
    trap 'rm -rf "${TEMP_DIR}"' EXIT
    ditto -x -k "${INPUT_PATH}" "${TEMP_DIR}"
    APP_PATH="${TEMP_DIR}/Sorty.app"
else
    APP_PATH="${INPUT_PATH}"
fi
EXECUTABLE_PATH="${APP_PATH}/Contents/MacOS/Sorty"
TIMEOUT_SECONDS="${SORTY_LAUNCH_SMOKE_TIMEOUT:-30}"

if [ ! -x "${EXECUTABLE_PATH}" ]; then
    echo "Sorty executable not found at ${EXECUTABLE_PATH}" >&2
    exit 1
fi

xattr -dr com.apple.quarantine "${APP_PATH}" >/dev/null 2>&1 || true
pkill -9 -x Sorty >/dev/null 2>&1 || true
for _ in {1..20}; do
    if ! pgrep -x Sorty >/dev/null 2>&1; then
        break
    fi
    sleep 0.25
done

RESULT_PATH="${TEMP_DIR:-${TMPDIR:-/tmp}}/sorty-main-window-appeared"
rm -f "${RESULT_PATH}"

if [ "${CI:-false}" = "true" ]; then
    SORTY_LAUNCH_SMOKE_RESULT="${RESULT_PATH}" \
        "${EXECUTABLE_PATH}" --release-launch-smoke-test >/tmp/sorty-launch-smoke.log 2>&1 &
else
    open -n "${APP_PATH}" --args --release-launch-smoke-test
fi

deadline=$((SECONDS + TIMEOUT_SECONDS))
while (( SECONDS < deadline )); do
    pid=$(pgrep -x Sorty | head -1 || true)
    if [ "${CI:-false}" = "true" ] && [ -s "${RESULT_PATH}" ]; then
        echo "Sorty launch smoke test passed: main window root appeared."
        kill -9 "${pid}" >/dev/null 2>&1 || true
        exit 0
    fi
    if [ -n "${pid}" ] && swift - "${pid}" <<'SWIFT'
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2,
      let expectedPID = Int(CommandLine.arguments[1]) else {
    exit(2)
}

let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: Any]] ?? []

let hasVisibleApplicationWindow = windows.contains { window in
    guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
          let layer = window[kCGWindowLayer as String] as? Int,
          let alpha = window[kCGWindowAlpha as String] as? Double,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double else {
        return false
    }

    return ownerPID == expectedPID && layer == 0 && alpha > 0 && width > 100 && height > 100
}

exit(hasVisibleApplicationWindow ? 0 : 1)
SWIFT
    then
        echo "Sorty launch smoke test passed: visible application window detected."
        kill -9 "${pid}" >/dev/null 2>&1 || true
        exit 0
    fi
    sleep 1
done

pid=$(pgrep -x Sorty | head -1 || true)
if [ -n "${pid}" ]; then
    kill -9 "${pid}" >/dev/null 2>&1 || true
    echo "Sorty launched as process ${pid}, but no visible application window appeared." >&2
else
    echo "Sorty did not remain running after launch." >&2
fi
exit 1
