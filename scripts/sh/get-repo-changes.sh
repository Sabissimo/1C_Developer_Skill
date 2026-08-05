#!/usr/bin/env bash
# get-repo-changes.sh — detect repository versions newer than the last synced one.
# Contract: references/script-contract.md #get-repo-changes  (never modifies state)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"

project_dir=""
full="no"
while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir) project_dir="$2"; shift 2 ;;
        --full) full="yes"; shift ;;
        *) die "$EXIT_USAGE" "Unknown argument: $1" ;;
    esac
done

load_context "$project_dir"
last_synced="$(state_get lastRepoVersion)"
[ -n "$last_synced" ] || last_synced=0

begin=$((last_synced + 1))
if [ "$full" = "yes" ] || [ "$last_synced" -eq 0 ]; then begin=1; fi

report_file="$WORK_DIR/repo-report.txt"
rm -f "$report_file"

info "repository report from version $begin"
run_designer get-repo-changes yes /ConfigurationRepositoryReport "$(to_win "$report_file")" -NBegin "$begin"
assert_designer_success "Repository report"

new_versions=0
latest="$last_synced"
for version in $(repo_versions_from_report "$report_file"); do
    if [ "$version" -gt "$last_synced" ]; then
        new_versions=$((new_versions + 1))
        [ "$version" -gt "$latest" ] && latest="$version"
    fi
done

has_changes=false
[ "$new_versions" -gt 0 ] && has_changes=true

printf '{"ok":true,"hasChanges":%s,"lastSyncedVersion":%s,"latestVersion":%s,"newVersions":%s}\n' \
    "$has_changes" "$last_synced" "$latest" "$new_versions"
exit "$EXIT_OK"
