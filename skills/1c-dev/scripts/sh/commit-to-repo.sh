#!/usr/bin/env bash
# commit-to-repo.sh — commit locked objects to the repository (releases the locks).
# Contract: references/script-contract.md #commit-to-repo
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"
. "$SCRIPT_DIR/mapping.sh"

project_dir=""
comment=""
keep_locked="no"
while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir) project_dir="$2"; shift 2 ;;
        --comment) comment="$2"; shift 2 ;;
        --keep-locked) keep_locked="yes"; shift ;;
        *) die "$EXIT_USAGE" "Unknown argument: $1" ;;
    esac
done

load_context "$project_dir"

[ -n "$comment" ] || die "$EXIT_USAGE" 'Commit comment is required: pass --comment "<task summary>"'
locked=()
while IFS= read -r name; do
    [ -n "$name" ] && locked+=("$name")
done < <(get_locked_objects)
[ ${#locked[@]} -gt 0 ] || die "$EXIT_USAGE" "No locked objects recorded (.1c-work/locked-objects.json) — lock before committing"

last_synced="$(state_get lastRepoVersion)"
[ -n "$last_synced" ] || last_synced=0

write_objects_xml "$OBJECTS_FILE" "${locked[@]}"

info "committing ${#locked[@]} object(s): $comment"
commit_args=(/ConfigurationRepositoryCommit -Objects "$(to_win "$OBJECTS_FILE")" -comment "$comment")
[ "$keep_locked" = "yes" ] && commit_args+=(-keepLocked)
run_designer commit-to-repo yes "${commit_args[@]}"
assert_designer_success "Repository commit"

# Learn the new repository version created by this commit.
report_file="$WORK_DIR/commit-report.txt"
rm -f "$report_file"
begin=$((last_synced + 1))
[ "$last_synced" -eq 0 ] && begin=1
run_designer commit-report yes /ConfigurationRepositoryReport "$(to_win "$report_file")" -NBegin "$begin"
assert_designer_success "Repository report after commit"

latest="$last_synced"
for version in $(repo_versions_from_report "$report_file"); do
    [ "$version" -gt "$latest" ] && latest="$version"
done

state_set "$latest" "$(now_iso)"

[ "$keep_locked" = "yes" ] || set_locked_objects

json_list=""
for name in "${locked[@]}"; do
    [ -n "$json_list" ] && json_list="$json_list,"
    json_list="$json_list\"$(json_escape "$name")\""
done
printf '{"ok":true,"repoVersion":%s,"objects":[%s]}\n' "$latest" "$json_list"
exit "$EXIT_OK"
