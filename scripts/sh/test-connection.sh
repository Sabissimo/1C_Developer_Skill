#!/usr/bin/env bash
# test-connection.sh — validate platform, infobase and repository access in one call.
# Contract: references/script-contract.md #test-connection
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"

project_dir=""
while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir) project_dir="$2"; shift 2 ;;
        *) die "$EXIT_USAGE" "Unknown argument: $1" ;;
    esac
done

load_context "$project_dir"
resolve_1cv8
info "1cv8.exe: $ONEC_EXE"

report_file="$WORK_DIR/connection-report.txt"
rm -f "$report_file"

# A version-bounded repository report is the cheapest call that exercises the platform,
# the infobase credentials and the repository credentials at once.
run_designer test-connection yes /ConfigurationRepositoryReport "$(to_win "$report_file")" -NBegin 1 -NEnd 1
assert_designer_success "Connection test"

[ -f "$report_file" ] || die "$EXIT_DESIGNER" "Connection test failed: repository report was not produced" \
    "\"logFile\":\"$(json_escape "$DESIGNER_LOG_FILE")\""

printf '{"ok":true,"exe":"%s","repoReachable":true}\n' "$(json_escape "$(to_win "$ONEC_EXE")")"
exit "$EXIT_OK"
