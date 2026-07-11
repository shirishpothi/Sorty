#!/bin/bash
set -euo pipefail

APP_PATH="$(cd "$(dirname "${1:-releases/Sorty.app}")" && pwd)/$(basename "${1:-releases/Sorty.app}")"
EXECUTABLE_PATH="${APP_PATH}/Contents/MacOS/Sorty"
TIMEOUT_SECONDS="${SORTY_LAUNCH_SMOKE_TIMEOUT:-30}"

if [ ! -x "${EXECUTABLE_PATH}" ]; then
    echo "Sorty executable not found at ${EXECUTABLE_PATH}" >&2
    exit 1
fi

PROCESS_PATTERN="^${EXECUTABLE_PATH}( |$)"

pkill -f "${PROCESS_PATTERN}" >/dev/null 2>&1 || true
for _ in {1..20}; do
    if ! pgrep -f "${PROCESS_PATTERN}" >/dev/null 2>&1; then
        break
    fi
    sleep 0.25
done
open -n "${APP_PATH}" --args --release-launch-smoke-test

deadline=$((SECONDS + TIMEOUT_SECONDS))
while (( SECONDS < deadline )); do
    pid=$(pgrep -f "${PROCESS_PATTERN}" | head -1 || true)
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
        kill "${pid}" >/dev/null 2>&1 || true
        exit 0
    fi
    sleep 1
done

pid=$(pgrep -f "${PROCESS_PATTERN}" | head -1 || true)
if [ -n "${pid}" ]; then
    kill "${pid}" >/dev/null 2>&1 || true
    echo "Sorty launched as process ${pid}, but no visible application window appeared." >&2
else
    echo "Sorty did not remain running after launch." >&2
fi
exit 1
