#!/usr/bin/env bash
# load-from-xml.sh — partial load of edited XML files into the main configuration + DB update.
# Contract: references/script-contract.md #load-from-xml
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"

project_dir=""
files=""
list_file=""
while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir) project_dir="$2"; shift 2 ;;
        --files) files="$2"; shift 2 ;;
        --list-file) list_file="$2"; shift 2 ;;
        *) die "$EXIT_USAGE" "Unknown argument: $1" ;;
    esac
done

load_context "$project_dir"

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
[ ${#paths[@]} -gt 0 ] || die "$EXIT_USAGE" "Nothing to load: pass --files or --list-file"

# The designer reads the list file: absolute Windows paths, one per line, UTF-8 with BOM.
absolute_lines=""
count=0
for relative in "${paths[@]}"; do
    unix_path="$XML_DIR/$(printf '%s' "$relative" | tr '\\' '/')"
    [ -f "$unix_path" ] || die "$EXIT_USAGE" "File not found under xmlDir: $relative"
    absolute_lines="$absolute_lines$(to_win "$unix_path")
"
    count=$((count + 1))
done
designer_list_file="$WORK_DIR/load-list.txt"
write_utf8_bom "$designer_list_file" "$absolute_lines"

info "loading $count file(s) into the main configuration"
run_designer load-from-xml no /LoadConfigFromFiles "$(to_win "$XML_DIR")" -listFile "$(to_win "$designer_list_file")" -updateConfigDumpInfo
assert_designer_success "Partial load from XML"

info "updating database configuration"
run_designer load-update-dbcfg no /UpdateDBCfg
assert_designer_success "Database configuration update"

printf '{"ok":true,"loaded":%s}\n' "$count"
exit "$EXIT_OK"
