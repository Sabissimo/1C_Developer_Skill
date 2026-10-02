#!/usr/bin/env bash
# check-config.sh — run the configuration check the project chose (checkMode) on the
# main configuration, between load-from-xml and commit-to-repo.
# Contract: references/script-contract.md #check-config  (exit 5 when the check finds errors)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"
. "$SCRIPT_DIR/mapping.sh"
. "$SCRIPT_DIR/checking.sh"

CHECK_LOG_NAME="check-config"
CHECK_OPERATION="Configuration check"

skipped_result() {
    # skipped_result <mode> <reason>
    info "check skipped: $2"
    printf '{"ok":true,"mode":"%s","skipped":true,"reason":"%s"}\n' "$1" "$(json_escape "$2")"
    exit "$EXIT_OK"
}

project_dir=""
files=""
list_file=""
mode=""
while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir) project_dir="$2"; shift 2 ;;
        --files) files="$2"; shift 2 ;;
        --list-file) list_file="$2"; shift 2 ;;
        --mode) mode="$2"; shift 2 ;;
        *) die "$EXIT_USAGE" "Unknown argument: $1" ;;
    esac
done

load_context "$project_dir"

check_mode="$CHECK_MODE"
if [ -n "$mode" ]; then
    is_check_mode "$mode" || die "$EXIT_USAGE" "Unknown mode: $mode (expected one of $CHECK_MODES)"
    check_mode="$mode"
fi
[ "$check_mode" != "$CHECK_MODE_UNSET" ] || skipped_result "$check_mode" "checkMode is not set in 1c-project.json"
[ "$check_mode" != "$CHECK_MODE_NONE" ]  || skipped_result "$check_mode" "checkMode is none"

module_ids=""
if [ "$check_mode" = "$CHECK_MODE_MODULES" ]; then
    paths=()
    if [ -n "$files" ]; then
        while IFS= read -r path; do
            [ -n "$path" ] && paths+=("$path")
        done < <(printf '%s\n' "$files" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
    fi
    if [ -n "$list_file" ]; then
        [ -f "$list_file" ] || die "$EXIT_USAGE" "List file not found: $list_file"
        while IFS= read -r path; do
            path="$(printf '%s' "$path" | tr -d '\r' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
            [ -n "$path" ] && paths+=("$path")
        done < "$list_file"
    fi
    [ ${#paths[@]} -gt 0 ] || die "$EXIT_USAGE" "modules mode needs the edited files: pass --files or --list-file"
    module_ids_for_paths "${paths[@]}"
    module_ids="$MODULE_IDS"
    [ -n "$module_ids" ] || skipped_result "$check_mode" "no module among the edited files"
fi

check_args=("${CHECK_CONFIG_ARGS[@]}")
if [ "$check_mode" = "$CHECK_MODE_MODULES" ]; then
    check_args=("${CHECK_MODULES_ARGS[@]}")
fi

info "checking the main configuration (mode: $check_mode)"
run_designer "$CHECK_LOG_NAME" no "${check_args[@]}"
check_exit="$DESIGNER_EXIT"
check_log_file="$DESIGNER_LOG_FILE"

# Anything but "clean" (0) and "found errors" (101) means the check itself did not run.
if [ "$check_exit" -ne 0 ] && [ "$check_exit" -ne "$DESIGNER_EXIT_CHECK_ERRORS" ]; then
    assert_designer_success "$CHECK_OPERATION"
fi

findings="$(check_findings "$DESIGNER_LOG_TEXT")"
structured="$(printf '%s\n' "$findings" | grep -E -- "$CHECK_FINDING_PATTERN" || true)"

if [ "$check_exit" -eq 0 ] && [ -z "$structured" ]; then
    # The designer sometimes exits 0 on failure: scan what is left once the "no errors"
    # lines are gone — those would trip the error pattern by themselves.
    DESIGNER_LOG_TEXT="$findings"
    assert_designer_success "$CHECK_OPERATION"
    printf '{"ok":true,"mode":"%s","skipped":false,"errorCount":0,"otherErrorCount":0,"otherErrors":[],"logFile":"%s"}\n' \
        "$check_mode" "$(json_escape "$check_log_file")"
    exit "$EXIT_OK"
fi

errors="$findings"
other_errors=""
if [ "$check_mode" = "$CHECK_MODE_MODULES" ]; then
    errors="$(split_check_findings "$findings" "$module_ids" edited)"
    other_errors="$(split_check_findings "$findings" "$module_ids" other)"
fi
error_count="$(count_lines "$errors")"
other_error_count="$(count_lines "$other_errors")"

other_report="\"otherErrorCount\":$other_error_count,\"otherErrors\":[$(json_string_list "$other_errors")],\"logFile\":\"$(json_escape "$check_log_file")\""
failure_report="\"mode\":\"$check_mode\",\"errorCount\":$error_count,\"errors\":[$(json_string_list "$errors")],$other_report"

if [ "$error_count" -gt 0 ]; then
    die "$EXIT_CHECK_FAILED" "$CHECK_OPERATION found errors" "$failure_report"
fi
if [ "$other_error_count" -eq 0 ]; then
    # Exit 101 with nothing recognisable in the log: refuse to call that clean.
    die "$EXIT_CHECK_FAILED" "$CHECK_OPERATION reported errors (exit $check_exit) but the log holds no finding lines" "$failure_report"
fi

info "no findings in the edited modules; $other_error_count elsewhere"
printf '{"ok":true,"mode":"%s","skipped":false,"errorCount":0,%s}\n' "$check_mode" "$other_report"
exit "$EXIT_OK"
