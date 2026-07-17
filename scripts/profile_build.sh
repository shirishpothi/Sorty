#!/bin/bash
set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/config.sh
source "${SCRIPT_DIR}/config.sh"

PROFILE_TOP_COUNT="${PROFILE_TOP_COUNT:-25}"
PROFILE_JOBS="${PROFILE_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
PROFILE_SCRATCH_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sorty-build-profile.XXXXXX")"
PROFILE_LOG="${PROFILE_SCRATCH_DIR}/debug-time.log"

cleanup_profile_scratch() {
    rm -rf "${PROFILE_SCRATCH_DIR}"
}
trap cleanup_profile_scratch EXIT

echo "Profiling a clean debug build with ${PROFILE_JOBS} jobs..."
swift build \
    --package-path "${PROJECT_DIR}" \
    --scratch-path "${PROFILE_SCRATCH_DIR}/build" \
    --product SortyApp \
    -c debug \
    -j "${PROFILE_JOBS}" \
    --disable-sandbox \
    -Xswiftc -Xfrontend \
    -Xswiftc -debug-time-function-bodies \
    -Xswiftc -Xfrontend \
    -Xswiftc -debug-time-expression-type-checking \
    >"${PROFILE_LOG}" 2>&1

echo
echo "Slowest unique Sorty function bodies and expressions:"
awk -F '\t' \
    '$1 ~ /^[0-9]+\.[0-9]+ms$/ && $2 ~ /\/Sources\// {
        milliseconds=$1
        sub(/ms$/, "", milliseconds)
        print milliseconds "\t" $2 "\t" $3
    }' "${PROFILE_LOG}" \
    | sort -u \
    | sort -nr \
    | awk -v limit="${PROFILE_TOP_COUNT}" 'NR <= limit'
