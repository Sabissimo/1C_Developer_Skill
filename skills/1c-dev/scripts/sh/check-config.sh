#!/usr/bin/env bash
# check-config.sh — run the configuration check the project chose (checkMode) on the
# main configuration, between load-from-xml and commit-to-repo. checkMode says which
# checks are allowed; the files edited in the task say which of those are needed.
# Contract: references/script-contract.md #check-config  (exit 5 when the check finds errors)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"
. "$SCRIPT_DIR/mapping.sh"
. "$SCRIPT_DIR/checking.sh"

CHECK_LOG_NAME="check-config"
CHECK_OPERATION="Configuration check"

nothing_to_check_reason() {
    # nothing_to_check_reason <mode> -> why nothing was checked although a check is configured
    case "$1" in
        "$CHECK_MODE_AUTO") echo "no .xml file and no module among the edited files" ;;
        "$CHECK_MODE_MODULES") echo "no module among the edited files" ;;
        "$CHECK_MODE_INTEGRITY") echo "no .xml file among the edited files" ;;
    esac
}

skipped_result() {
    # skipped_result <mode> <reason>
    info "check skipped: $2"
    printf '{"ok":true,"mode":"%s","skipped":true,"reason":"%s"}\n' "$1" "$(json_escape "$2")"
    exit "$EXIT_OK"
}

append_lines() {
    # append_lines <lines> <more-lines> -> both, without blank lines
    printf '%s\n%s\n' "$1" "$2" | sed '/^$/d'
}

run_check() {
    # run_check <designer-arg>...
    # The designer check run. Sets CHECK_FINDINGS (its finding lines), CHECK_LOG_FILE and
    # CHECK_UNRECOGNISED (yes when the designer reported errors that the log parser could
    # not find). Call directly, never inside $(...).
    local exit_code findings structured
    run_designer "$CHECK_LOG_NAME" no "$@"
    exit_code="$DESIGNER_EXIT"
    CHECK_LOG_FILE="$DESIGNER_LOG_FILE"

    # Anything but "clean" (0) and "found errors" (101) means the check itself did not run.
    if [ "$exit_code" -ne 0 ] && [ "$exit_code" -ne "$DESIGNER_EXIT_CHECK_ERRORS" ]; then
        assert_designer_success "$CHECK_OPERATION"
    fi

    findings="$(check_findings "$DESIGNER_LOG_TEXT")"
    if [ "$exit_code" -eq 0 ]; then
        structured="$(printf '%s\n' "$findings" | grep -E -- "$CHECK_FINDING_PATTERN" || true)"
        if [ -z "$structured" ]; then
            # The designer sometimes exits 0 on failure: scan what is left once the "no
            # errors" lines are gone — those would trip the error pattern by themselves.
            DESIGNER_LOG_TEXT="$findings"
            assert_designer_success "$CHECK_OPERATION"
            findings=""
        fi
    fi
    CHECK_FINDINGS="$findings"
    CHECK_UNRECOGNISED="no"
    if [ "$exit_code" -eq "$DESIGNER_EXIT_CHECK_ERRORS" ] && [ -z "$findings" ]; then
        CHECK_UNRECOGNISED="yes"
    fi
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
[ ${#paths[@]} -gt 0 ] || die "$EXIT_USAGE" "Nothing to check: pass the edited files via --files or --list-file"

# The mode allows checks; the edited files decide which of the allowed ones are needed:
# metadata (.xml) -> integrity, modules -> syntax. "always" needs both whatever was edited.
check_always="no"
integrity_allowed="no"
modules_allowed="no"
case "$check_mode" in
    "$CHECK_MODE_ALWAYS") check_always="yes"; integrity_allowed="yes"; modules_allowed="yes" ;;
    "$CHECK_MODE_AUTO") integrity_allowed="yes"; modules_allowed="yes" ;;
    "$CHECK_MODE_INTEGRITY") integrity_allowed="yes" ;;
    "$CHECK_MODE_MODULES") modules_allowed="yes" ;;
esac

module_ids=""
if [ "$modules_allowed" = "yes" ]; then
    module_ids_for_paths "${paths[@]}"
    module_ids="$MODULE_IDS"
fi
check_integrity="no"
if [ "$integrity_allowed" = "yes" ]; then
    if [ "$check_always" = "yes" ] || is_metadata_edited "${paths[@]}"; then
        check_integrity="yes"
    fi
fi
check_modules="no"
if [ "$modules_allowed" = "yes" ]; then
    if [ "$check_always" = "yes" ] || [ -n "$module_ids" ]; then
        check_modules="yes"
    fi
fi
if [ "$check_integrity" = "no" ] && [ "$check_modules" = "no" ]; then
    skipped_result "$check_mode" "$(nothing_to_check_reason "$check_mode")"
fi

checks=""
if [ "$check_integrity" = "yes" ]; then checks="$(append_lines "$checks" "$CHECK_KIND_INTEGRITY")"; fi
if [ "$check_modules" = "yes" ]; then checks="$(append_lines "$checks" "$CHECK_KIND_MODULES")"; fi
check_args=("${CHECK_MODULES_ARGS[@]}")
if [ "$check_integrity" = "yes" ] && [ "$check_modules" = "yes" ]; then
    check_args=("${CHECK_BOTH_ARGS[@]}")
elif [ "$check_integrity" = "yes" ]; then
    check_args=("${CHECK_INTEGRITY_ARGS[@]}")
fi

info "checking the main configuration: $(printf '%s' "$checks" | tr '\n' ' ' | sed 's/ / + /g')"
run_check "${check_args[@]}"

errors="$(split_check_findings "$CHECK_FINDINGS" "$module_ids" edited)"
other_errors="$(split_check_findings "$CHECK_FINDINGS" "$module_ids" elsewhere)"
unattributed="$(split_check_findings "$CHECK_FINDINGS" "$module_ids" unattributed)"
if [ "$check_integrity" = "yes" ]; then
    # Integrity findings name a metadata object, not a file: every one of them counts.
    errors="$(append_lines "$unattributed" "$errors")"
else
    other_errors="$(append_lines "$other_errors" "$unattributed")"
fi
error_count="$(count_lines "$errors")"
other_error_count="$(count_lines "$other_errors")"

mode_report="\"mode\":\"$check_mode\",\"checks\":[$(json_string_list "$checks")]"
other_report="\"otherErrorCount\":$other_error_count,\"otherErrors\":[$(json_string_list "$other_errors")],\"logFile\":\"$(json_escape "$CHECK_LOG_FILE")\""
failure_report="$mode_report,\"errorCount\":$error_count,\"errors\":[$(json_string_list "$errors")],$other_report"

if [ "$error_count" -gt 0 ]; then
    die "$EXIT_CHECK_FAILED" "$CHECK_OPERATION found errors" "$failure_report"
fi
if [ "$CHECK_UNRECOGNISED" = "yes" ]; then
    # Designer exit 101 with nothing recognisable in the log: refuse to call that clean.
    die "$EXIT_CHECK_FAILED" "$CHECK_OPERATION reported errors (designer exit $DESIGNER_EXIT_CHECK_ERRORS) but the log holds no finding lines" "$failure_report"
fi

if [ "$other_error_count" -gt 0 ]; then
    info "no findings in the edited modules; $other_error_count elsewhere"
fi
printf '{"ok":true,%s,"skipped":false,"errorCount":0,%s}\n' "$mode_report" "$other_report"
exit "$EXIT_OK"
