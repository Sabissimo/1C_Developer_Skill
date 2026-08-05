#!/usr/bin/env bash
# lock-objects.sh — map changed files to metadata objects and lock them in the repository.
# Contract: references/script-contract.md #lock-objects  (exit 3 on lock conflict)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"
. "$SCRIPT_DIR/mapping.sh"

project_dir=""
files=""
list_file=""
objects=""
while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir) project_dir="$2"; shift 2 ;;
        --files) files="$2"; shift 2 ;;
        --list-file) list_file="$2"; shift 2 ;;
        --objects) objects="$2"; shift 2 ;;
        *) die "$EXIT_USAGE" "Unknown argument: $1" ;;
    esac
done

load_context "$project_dir"

object_names=()
if [ -n "$objects" ]; then
    while IFS= read -r name; do
        [ -n "$name" ] && object_names+=("$name")
    done < <(printf '%s' "$objects" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
else
    paths=()
    if [ -n "$files" ]; then
        while IFS= read -r path; do
            [ -n "$path" ] && paths+=("$path")
        done < <(printf '%s' "$files" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
    fi
    if [ -n "$list_file" ]; then
        [ -f "$list_file" ] || die "$EXIT_USAGE" "List file not found: $list_file"
        while IFS= read -r path; do
            path="$(printf '%s' "$path" | tr -d '\r' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
            [ -n "$path" ] && paths+=("$path")
        done < "$list_file"
    fi
    [ ${#paths[@]} -gt 0 ] || die "$EXIT_USAGE" "Nothing to lock: pass --files, --list-file or --objects"
    while IFS= read -r name; do
        [ -n "$name" ] && object_names+=("$name")
    done < <(map_paths_to_objects "${paths[@]}")
fi
[ ${#object_names[@]} -gt 0 ] || die "$EXIT_USAGE" "The given files map to no lockable objects"

info "locking: ${object_names[*]}"
write_objects_xml "$OBJECTS_FILE" "${object_names[@]}"

run_designer lock-objects yes /ConfigurationRepositoryLock -Objects "$(to_win "$OBJECTS_FILE")"
errors="$(designer_errors)"
if [ "$DESIGNER_EXIT" -ne 0 ] || [ -n "$errors" ]; then
    conflict="$(printf '%s\n' "$DESIGNER_LOG_TEXT" | grep -E "$LOCK_CONFLICT_PATTERN" || true)"
    if [ -n "$conflict" ]; then
        die "$EXIT_LOCK_CONFLICT" "Lock conflict: object(s) already locked by another repository user" \
            "\"conflict\":\"$(json_escape "$conflict")\",\"logFile\":\"$(json_escape "$DESIGNER_LOG_FILE")\""
    fi
    [ -n "$errors" ] || errors="designer exit code $DESIGNER_EXIT"
    die "$EXIT_DESIGNER" "Repository lock failed" \
        "\"exitCode\":$DESIGNER_EXIT,\"log\":\"$(json_escape "$errors")\",\"logFile\":\"$(json_escape "$DESIGNER_LOG_FILE")\""
fi

# Remember the full locked set so commit/unlock cover everything across multiple lock calls.
all_locked=()
while IFS= read -r name; do
    [ -n "$name" ] && all_locked+=("$name")
done < <( { get_locked_objects; printf '%s\n' "${object_names[@]}"; } | sort -u )
set_locked_objects "${all_locked[@]}"

json_list=""
for name in "${object_names[@]}"; do
    [ -n "$json_list" ] && json_list="$json_list,"
    json_list="$json_list\"$(json_escape "$name")\""
done
printf '{"ok":true,"objects":[%s]}\n' "$json_list"
exit "$EXIT_OK"
