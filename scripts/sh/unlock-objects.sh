#!/usr/bin/env bash
# unlock-objects.sh — abort path: release repository locks without committing.
# Contract: references/script-contract.md #unlock-objects
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"
. "$SCRIPT_DIR/mapping.sh"

project_dir=""
objects=""
while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir) project_dir="$2"; shift 2 ;;
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
    while IFS= read -r name; do
        [ -n "$name" ] && object_names+=("$name")
    done < <(get_locked_objects)
fi
[ ${#object_names[@]} -gt 0 ] || die "$EXIT_USAGE" "No locked objects recorded and none passed via --objects"

write_objects_xml "$OBJECTS_FILE" "${object_names[@]}"

info "unlocking: ${object_names[*]}"
run_designer unlock-objects yes /ConfigurationRepositoryUnlock -Objects "$(to_win "$OBJECTS_FILE")" -force
assert_designer_success "Repository unlock"

if [ -z "$objects" ]; then
    set_locked_objects
else
    # Partial unlock: drop only the released objects from the recorded list.
    remaining=()
    while IFS= read -r name; do
        keep="yes"
        for released in "${object_names[@]}"; do
            [ "$name" = "$released" ] && keep="no" && break
        done
        [ "$keep" = "yes" ] && [ -n "$name" ] && remaining+=("$name")
    done < <(get_locked_objects)
    if [ ${#remaining[@]} -gt 0 ]; then
        set_locked_objects "${remaining[@]}"
    else
        set_locked_objects
    fi
fi

json_list=""
for name in "${object_names[@]}"; do
    [ -n "$json_list" ] && json_list="$json_list,"
    json_list="$json_list\"$(json_escape "$name")\""
done
printf '{"ok":true,"objects":[%s]}\n' "$json_list"
exit "$EXIT_OK"
