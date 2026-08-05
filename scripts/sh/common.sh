#!/usr/bin/env bash
# common.sh — shared core for all 1c-dev skill scripts (Git Bash variant).
# Source from every script:  . "$(dirname "$0")/common.sh"
# Contract: references/script-contract.md — keep in sync with scripts/ps/Common.ps1.

# ---- Contract constants ----
EXIT_OK=0
EXIT_DESIGNER=1        # designer/batch operation failed
EXIT_CONFIG=2          # missing/invalid 1c-project.json or environment
EXIT_LOCK_CONFLICT=3   # object already locked by another repository user
EXIT_USAGE=4           # bad script arguments

CONFIG_FILE_NAME="1c-project.json"
STATE_FILE_NAME=".1c-state.json"
WORK_DIR_NAME=".1c-work"
OBJECTS_FILE_NAME="objects.xml"
LOCKED_LIST_NAME="locked-objects.json"

# Designer log lines matching this mean failure even when the exit code is 0.
DESIGNER_ERROR_PATTERN='(ошибк|Ошибк|ОШИБК|error|Error|ERROR|не удалось|Не удалось|не обнаружен|failed|Failed|failure|отказано|access denied|исключительн|Исключительн|нет доступа)'
LOCK_CONFLICT_PATTERN='(захвачен|Захвачен|заблокирован|locked by|already locked|не может быть захвачен)'

# ---- Output helpers ----
info() { printf '%s\n' "$*" >&2; }

json_escape() {
    # Escape a string for embedding in a JSON string value.
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' | tr -d '\r' | awk '{printf "%s\\n", $0}' | sed -e 's/\\n$//'
}

die() {
    # die <exit-code> <message> [extra-json-fields]
    local code="$1" msg="$2" extra="${3:-}"
    if [ -n "$extra" ]; then
        printf '{"ok":false,"error":"%s",%s}\n' "$(json_escape "$msg")" "$extra"
    else
        printf '{"ok":false,"error":"%s"}\n' "$(json_escape "$msg")"
    fi
    exit "$code"
}

# ---- Path conversion (Git Bash /c/... -> C:\...) ----
to_win() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
    else
        printf '%s' "$1"
    fi
}

to_unix() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$1"
    else
        printf '%s' "$1"
    fi
}

# ---- JSON parsing: jq -> python -> powershell fallback chain ----
json_get() {
    # json_get <file> <dotted.path>  -> value or empty string
    local file="$1" path="$2"
    if command -v jq >/dev/null 2>&1; then
        jq -r ".${path} // empty" "$file"
        return
    fi
    if command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
        local py; py=$(command -v python3 || command -v python)
        "$py" -c "
import json, sys
obj = json.load(open(sys.argv[1], 'r'))
for key in sys.argv[2].split('.'):
    if not isinstance(obj, dict) or key not in obj:
        sys.exit(0)
    obj = obj[key]
if obj is not None:
    sys.stdout.write('%s' % obj)
" "$file" "$path"
        return
    fi
    # Last resort: PowerShell is always present on Windows.
    powershell.exe -NoProfile -NonInteractive -Command \
        "\$o = Get-Content -Raw -LiteralPath '$(to_win "$file")' | ConvertFrom-Json; \$v = \$o; foreach (\$k in '$path'.Split('.')) { if (\$null -eq \$v) { break }; \$v = \$v.\$k }; if (\$null -ne \$v) { Write-Output \$v }" 2>/dev/null | tr -d '\r'
}

# ---- Project context (sets globals) ----
load_context() {
    # load_context [project-dir]
    PROJECT_DIR="${1:-$(pwd)}"
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    local config="$PROJECT_DIR/$CONFIG_FILE_NAME"
    [ -f "$config" ] || die "$EXIT_CONFIG" "Config not found: $config. Run the 1c-dev setup first."
    CONFIG_FILE="$config"

    IB_SERVER="$(json_get "$config" infobase.server)"
    IB_BASE="$(json_get "$config" infobase.base)"
    IB_USER="$(json_get "$config" infobase.user)"
    IB_PASS="$(json_get "$config" infobase.password)"
    REPO_PATH="$(json_get "$config" repository.path)"
    REPO_USER="$(json_get "$config" repository.user)"
    REPO_PASS="$(json_get "$config" repository.password)"
    PLATFORM_VERSION="$(json_get "$config" platformVersion)"
    local xml_dir temp_dir
    xml_dir="$(json_get "$config" xmlDir)"
    temp_dir="$(json_get "$config" tempXmlDir)"

    [ -n "$IB_SERVER" ] || die "$EXIT_CONFIG" "Config field missing: infobase.server"
    [ -n "$IB_BASE" ]   || die "$EXIT_CONFIG" "Config field missing: infobase.base"
    [ -n "$REPO_PATH" ] || die "$EXIT_CONFIG" "Config field missing: repository.path"
    [ -n "$xml_dir" ]   || die "$EXIT_CONFIG" "Config field missing: xmlDir"
    [ -n "$temp_dir" ]  || die "$EXIT_CONFIG" "Config field missing: tempXmlDir"

    CONNECTION="${IB_SERVER}\\${IB_BASE}"
    case "$xml_dir" in
        /*|[A-Za-z]:*) XML_DIR="$(to_unix "$xml_dir")" ;;
        *) XML_DIR="$PROJECT_DIR/$xml_dir" ;;
    esac
    case "$temp_dir" in
        /*|[A-Za-z]:*) TEMP_XML_DIR="$(to_unix "$temp_dir")" ;;
        *) TEMP_XML_DIR="$PROJECT_DIR/$temp_dir" ;;
    esac
    WORK_DIR="$PROJECT_DIR/$WORK_DIR_NAME"
    mkdir -p "$WORK_DIR"
    STATE_FILE="$PROJECT_DIR/$STATE_FILE_NAME"
    OBJECTS_FILE="$WORK_DIR/$OBJECTS_FILE_NAME"
    LOCKED_LIST="$WORK_DIR/$LOCKED_LIST_NAME"
}

# ---- State ----
state_get() {
    # state_get <field> -> value ("" if no state file)
    if [ -f "$STATE_FILE" ]; then
        json_get "$STATE_FILE" "$1"
    fi
}

state_set() {
    # state_set <lastRepoVersion> <lastSyncIso>
    printf '{\n  "lastRepoVersion": %s,\n  "lastSync": "%s"\n}\n' "$1" "$2" > "$STATE_FILE"
}

now_iso() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

# ---- Platform resolution ----
resolve_1cv8() {
    # Sets ONEC_EXE (unix path). Honors PLATFORM_VERSION (exact or prefix), else highest installed.
    local roots=() root dir version best=""
    for root in "/c/Program Files/1cv8" "/c/Program Files (x86)/1cv8"; do
        [ -d "$root" ] && roots+=("$root")
    done
    [ ${#roots[@]} -gt 0 ] || die "$EXIT_CONFIG" "No 1C platform installation found under Program Files/1cv8"

    local candidates=""
    for root in "${roots[@]}"; do
        for dir in "$root"/*/; do
            version="$(basename "$dir")"
            case "$version" in
                *[!0-9.]*) continue ;;
            esac
            echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || continue
            [ -f "$dir/bin/1cv8.exe" ] && candidates="$candidates$version $dir/bin/1cv8.exe
"
        done
    done
    [ -n "$candidates" ] || die "$EXIT_CONFIG" "No 1cv8.exe found in any Program Files/1cv8/<version>/bin"

    if [ -n "$PLATFORM_VERSION" ]; then
        best="$(printf '%s' "$candidates" | awk -v want="$PLATFORM_VERSION" '$1 == want || index($1, want ".") == 1 {print}' | sort -V | tail -n 1)"
        [ -n "$best" ] || die "$EXIT_CONFIG" "Configured platformVersion '$PLATFORM_VERSION' not installed"
    else
        best="$(printf '%s' "$candidates" | sort -V | tail -n 1)"
    fi
    ONEC_EXE="${best#* }"
}

# ---- Encoding-tolerant text reading (designer logs/reports: UTF-16, UTF-8 or CP1251) ----
read_text_smart() {
    local file="$1"
    [ -f "$file" ] || return 0
    local sig
    sig="$(head -c 3 "$file" | od -An -tx1 | tr -d ' \n')"
    case "$sig" in
        fffe*)   iconv -f UTF-16LE -t UTF-8 "$file" 2>/dev/null || true ;;
        feff*)   iconv -f UTF-16BE -t UTF-8 "$file" 2>/dev/null || true ;;
        efbbbf)  tail -c +4 "$file" ;;
        *)
            if iconv -f UTF-8 -t UTF-8 "$file" >/dev/null 2>&1; then
                cat "$file"
            else
                iconv -f CP1251 -t UTF-8 "$file" 2>/dev/null || cat "$file"
            fi
            ;;
    esac
}

write_utf8_bom() {
    # write_utf8_bom <file> <content>
    printf '\xEF\xBB\xBF%s' "$2" > "$1"
}

# ---- Designer invocation ----
# run_designer <log-name> <use-repo:yes|no> <operation-args...>
# Sets: DESIGNER_EXIT, DESIGNER_LOG_TEXT, DESIGNER_LOG_FILE
run_designer() {
    local log_name="$1" use_repo="$2"
    shift 2
    resolve_1cv8
    DESIGNER_LOG_FILE="$WORK_DIR/$log_name.log"
    rm -f "$DESIGNER_LOG_FILE"

    local args=(DESIGNER /S "$CONNECTION")
    if [ -n "$IB_USER" ]; then
        args+=(/N "$IB_USER" /P "$IB_PASS")
    fi
    if [ "$use_repo" = "yes" ]; then
        args+=(/ConfigurationRepositoryF "$REPO_PATH")
        if [ -n "$REPO_USER" ]; then
            args+=(/ConfigurationRepositoryN "$REPO_USER" /ConfigurationRepositoryP "$REPO_PASS")
        fi
    fi
    args+=("$@")
    args+=(/DisableStartupDialogs /DisableStartupMessages /Out "$(to_win "$DESIGNER_LOG_FILE")")

    info "designer: $*"
    set +e
    # MSYS/Git Bash rewrites args starting with '/' into filesystem paths before they
    # reach Windows binaries — that turns /Out, /S etc. into garbage. Disable it for
    # this invocation only (MSYS_NO_PATHCONV = Git for Windows, ARG_CONV_EXCL = MSYS2).
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' "$ONEC_EXE" "${args[@]}"
    DESIGNER_EXIT=$?
    set -e
    DESIGNER_LOG_TEXT="$(read_text_smart "$DESIGNER_LOG_FILE")"
}

designer_errors() {
    # Prints error-looking lines from the last designer log.
    printf '%s\n' "$DESIGNER_LOG_TEXT" | grep -E "$DESIGNER_ERROR_PATTERN" || true
}

assert_designer_success() {
    # assert_designer_success <operation-name>
    local operation="$1" errors
    errors="$(designer_errors)"
    if [ "$DESIGNER_EXIT" -ne 0 ] || [ -n "$errors" ]; then
        [ -n "$errors" ] || errors="designer exit code $DESIGNER_EXIT"
        die "$EXIT_DESIGNER" "$operation failed" \
            "\"exitCode\":$DESIGNER_EXIT,\"log\":\"$(json_escape "$errors")\",\"logFile\":\"$(json_escape "$DESIGNER_LOG_FILE")\""
    fi
}

# ---- Repository report parsing ----
repo_versions_from_report() {
    # repo_versions_from_report <report-file> -> sorted unique version numbers, one per line
    # The designer writes the report as an MXL spreadsheet (MOXCEL) on most builds even
    # when the file name ends in .txt; some builds write plain text. Handle both.
    local text
    text="$(read_text_smart "$1" | tr -d '\0')"
    if printf '%s' "$text" | head -c 64 | grep -q 'MOXCEL' || printf '%s' "$text" | grep -q '{"#","'; then
        # MXL: versions are cell pairs — a {"#","Версия:"} label cell whose next string
        # cell holds the number. "Версия конфигурации:" etc. must not match.
        printf '%s\n' "$text" \
            | grep -oE '\{"#","[^"]*"\}' \
            | sed -E 's/^\{"#","(.*)"\}$/\1/' \
            | awk '
                prev == "Версия:" || prev == "Version:" {
                    if ($0 ~ /^[0-9]+$/) print $0
                }
                { prev = $0 }
              ' \
            | sort -n -u
    else
        printf '%s\n' "$text" | sed -nE 's/^[[:space:]]*(Версия|Version):?[[:space:]]*([0-9]+)[[:space:]]*$/\2/p' | sort -n -u
    fi
}
