#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: $0 --arm64 <path/to/Sorty-arm64.app> --x86_64 <path/to/Sorty-x86_64.app> --output <path/to/Sorty.app>"
}

ARM64_APP=""
X86_64_APP=""
OUTPUT_APP=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arm64)
            ARM64_APP="$2"
            shift 2
            ;;
        --x86_64)
            X86_64_APP="$2"
            shift 2
            ;;
        --output)
            OUTPUT_APP="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ -z "${ARM64_APP}" || -z "${X86_64_APP}" || -z "${OUTPUT_APP}" ]]; then
    usage
    exit 1
fi

if [ ! -d "${ARM64_APP}" ]; then
    echo "arm64 app not found at ${ARM64_APP}"
    exit 1
fi

if [ ! -d "${X86_64_APP}" ]; then
    echo "x86_64 app not found at ${X86_64_APP}"
    exit 1
fi

verify_universal_binary() {
    local bin_path="$1"
    local strict="${2:-true}"
    if [ ! -f "${bin_path}" ]; then
        return
    fi

    local archs
    archs=$(lipo -archs "${bin_path}" 2>/dev/null || true)
    if [[ "${archs}" != *"arm64"* || "${archs}" != *"x86_64"* ]]; then
        if [ "${strict}" = "true" ]; then
            echo "Expected universal binary but got '${archs}' at ${bin_path}"
            exit 1
        fi
        echo "Warning: non-universal binary at ${bin_path} (${archs})"
    fi
}

is_shebang_script() {
    local file_path="$1"
    if [ ! -s "${file_path}" ]; then
        return 1
    fi

    local prefix
    prefix=$(LC_ALL=C head -c 2 "${file_path}" 2>/dev/null || true)
    [ "${prefix}" = "#!" ]
}

restore_executable_permissions() {
    local app_path="$1"
    local macho_count=0
    local script_count=0

    while IFS= read -r -d '' candidate; do
        local candidate_desc
        candidate_desc=$(file -b "${candidate}" 2>/dev/null || true)
        if [[ "${candidate_desc}" == *"Mach-O"* ]]; then
            chmod 755 "${candidate}"
            macho_count=$((macho_count + 1))
            continue
        fi

        if is_shebang_script "${candidate}"; then
            chmod 755 "${candidate}"
            script_count=$((script_count + 1))
        fi
    done < <(find "${app_path}" -type f -print0)

    echo "Restored executable permissions on ${macho_count} Mach-O files and ${script_count} shebang scripts"
}

verify_executable_file() {
    local file_path="$1"
    if [ ! -f "${file_path}" ]; then
        echo "Expected executable file but it was missing: ${file_path}"
        exit 1
    fi
    if [ ! -x "${file_path}" ]; then
        echo "Expected executable permissions but found non-executable file: ${file_path}"
        exit 1
    fi
}

echo "Merging app bundles..."
rm -rf "${OUTPUT_APP}"
mkdir -p "$(dirname "${OUTPUT_APP}")"
rsync -a "${ARM64_APP}/" "${OUTPUT_APP}/"

MERGED_COUNT=0
while IFS= read -r -d '' ARM_FILE; do
    REL_PATH="${ARM_FILE#${ARM64_APP}/}"
    X86_FILE="${X86_64_APP}/${REL_PATH}"
    OUT_FILE="${OUTPUT_APP}/${REL_PATH}"

    if [ ! -f "${X86_FILE}" ]; then
        continue
    fi

    ARM_DESC=$(file -b "${ARM_FILE}")
    X86_DESC=$(file -b "${X86_FILE}")
    if [[ "${ARM_DESC}" == *"Mach-O"* && "${X86_DESC}" == *"Mach-O"* ]]; then
        ARM_ARCHS=$(lipo -archs "${ARM_FILE}" 2>/dev/null || true)
        X86_ARCHS=$(lipo -archs "${X86_FILE}" 2>/dev/null || true)

        if [ "${ARM_ARCHS}" = "${X86_ARCHS}" ]; then
            continue
        fi

        lipo -create "${ARM_FILE}" "${X86_FILE}" -output "${OUT_FILE}"
        chmod 755 "${OUT_FILE}"
        MERGED_COUNT=$((MERGED_COUNT + 1))
    fi
done < <(find "${ARM64_APP}" -type f -print0)

echo "Merged ${MERGED_COUNT} Mach-O files"

# Artifact upload/download in GitHub Actions strips executable bits (files become 0644).
# Ensure all Mach-O files in the merged app are executable before packaging/signing.
restore_executable_permissions "${OUTPUT_APP}"
codesign --force --deep --sign - "${OUTPUT_APP}" >/dev/null 2>&1 || true

MAIN_BIN="${OUTPUT_APP}/Contents/MacOS/SortyApp"
verify_executable_file "${MAIN_BIN}"
verify_executable_file "${OUTPUT_APP}/Contents/Resources/CLI/sorty"
verify_executable_file "${OUTPUT_APP}/Contents/Resources/CLI/learnings"
verify_universal_binary "${MAIN_BIN}"
verify_universal_binary "${OUTPUT_APP}/Contents/Resources/CLI/learnings"

if [ -d "${OUTPUT_APP}/Contents/Frameworks" ]; then
    while IFS= read -r -d '' FRAMEWORK_DIR; do
        FRAMEWORK_NAME="$(basename "${FRAMEWORK_DIR}" .framework)"
        FRAMEWORK_BIN="${FRAMEWORK_DIR}/${FRAMEWORK_NAME}"
        verify_universal_binary "${FRAMEWORK_BIN}" "false"
    done < <(find "${OUTPUT_APP}/Contents/Frameworks" -maxdepth 1 -type d -name "*.framework" -print0)
fi

echo "Universal app created at ${OUTPUT_APP}"
