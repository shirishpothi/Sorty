#!/bin/zsh
set -eu

if [[ -z "${SORTY_HOT_COMMAND_DIR:-}" || -z "${SORTY_REAL_SWIFT_FRONTEND:-}" ]]; then
    print -u2 "Sorty hot reload frontend is missing its build environment."
    exit 1
fi

original_arguments=("$@")
captured_arguments=()
while (( $# > 0 )); do
    if [[ "$1" == "-filelist" && $# -gt 1 ]]; then
        while IFS= read -r source; do
            [[ -n "$source" ]] && captured_arguments+=("$source")
        done < "$2"
        shift 2
    else
        captured_arguments+=("$1")
        shift
    fi
done

record="$(mktemp "${SORTY_HOT_COMMAND_DIR}/frontend.XXXXXX")"
{
    printf '%s\0' "$PWD"
    printf '%s\0' "$SORTY_REAL_SWIFT_FRONTEND"
    printf '%s\0' "${captured_arguments[@]}"
} > "$record"

exec "$SORTY_REAL_SWIFT_FRONTEND" "${original_arguments[@]}"
