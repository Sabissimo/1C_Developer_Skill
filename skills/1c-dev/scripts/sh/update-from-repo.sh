#!/usr/bin/env bash
# update-from-repo.sh — pull latest repository version into the infobase and re-sync XML.
# Contract: references/script-contract.md #update-from-repo
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"

project_dir=""
mode="auto"
while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir) project_dir="$2"; shift 2 ;;
        --mode) mode="$2"; shift 2 ;;
        *) die "$EXIT_USAGE" "Unknown argument: $1" ;;
    esac
done
case "$mode" in auto|full) ;; *) die "$EXIT_USAGE" "Invalid --mode: $mode (auto|full)" ;; esac

load_context "$project_dir"
last_synced="$(state_get lastRepoVersion)"
[ -n "$last_synced" ] || last_synced=0

# Learn the current repository version first so state ends up accurate.
report_file="$WORK_DIR/repo-report.txt"
rm -f "$report_file"
begin=$((last_synced + 1))
[ "$last_synced" -eq 0 ] && begin=1
run_designer update-report yes /ConfigurationRepositoryReport "$(to_win "$report_file")" -NBegin "$begin"
assert_designer_success "Repository report"

latest="$last_synced"
for version in $(repo_versions_from_report "$report_file"); do
    [ "$version" -gt "$latest" ] && latest="$version"
done

info "updating configuration from repository"
run_designer update-cfg yes /ConfigurationRepositoryUpdateCfg -force
assert_designer_success "Update from repository"

info "updating database configuration"
run_designer update-dbcfg no /UpdateDBCfg
assert_designer_success "Database configuration update"

# Re-sync XML via the sync script; keep its stdout (its own result JSON) off our stdout.
set +e
sync_output="$("$SCRIPT_DIR/sync-xml.sh" --project-dir "$PROJECT_DIR" --mode "$mode")"
sync_exit=$?
set -e
sync_json="$(printf '%s\n' "$sync_output" | tail -n 1)"
if [ "$sync_exit" -ne 0 ]; then
    printf '%s\n' "$sync_json"   # surface the sync error result as ours
    exit "$sync_exit"
fi

sync_tmp="$WORK_DIR/sync-result.json"
printf '%s' "$sync_json" > "$sync_tmp"
sync_mode="$(json_get "$sync_tmp" mode)"
sync_changed="$(json_get "$sync_tmp" changed)"
sync_deleted="$(json_get "$sync_tmp" deleted)"

state_set "$latest" "$(now_iso)"

printf '{"ok":true,"repoVersion":%s,"syncMode":"%s","changed":%s,"deleted":%s}\n' \
    "$latest" "$sync_mode" "$sync_changed" "$sync_deleted"
exit "$EXIT_OK"
