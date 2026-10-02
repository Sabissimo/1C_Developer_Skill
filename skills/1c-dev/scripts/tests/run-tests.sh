#!/usr/bin/env bash
# run-tests.sh — bash-variant tests: mapping table + objects.xml generation + parity
# with the PowerShell variant (objects.xml content must match after normalization).
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$TESTS_DIR/../sh/common.sh"
. "$TESTS_DIR/../sh/mapping.sh"
. "$TESTS_DIR/../sh/checking.sh"

# mapping.sh functions may call die/info from common.sh; LOCKED_LIST isn't needed here.
failures=0
case_count=0

# ---- mapping cases ----
while IFS='|' read -r path expected; do
    # mapping-cases.txt is covered by "* text=auto", so it lands CRLF on a Windows
    # checkout — strip the CR or every comparison fails against an invisible \r.
    expected="${expected%$'\r'}"
    [ -n "$path" ] || continue
    case_count=$((case_count + 1))
    actual="$(map_path_to_object "$path")" || actual="__ERROR__"
    [ -n "$actual" ] || actual="-"
    if [ "$actual" != "$expected" ]; then
        echo "FAIL mapping: '$path' -> '$actual' (expected '$expected')"
        failures=$((failures + 1))
    fi
done < "$TESTS_DIR/mapping-cases.txt"

# ---- unknown top-level directory must fail ----
case_count=$((case_count + 1))
if map_path_to_object "Nonsense/Файл.xml" >/dev/null 2>&1; then
    echo "FAIL mapping: unknown directory did not fail"
    failures=$((failures + 1))
fi

# ---- lock-objects, whole script: an unmappable path stops it with exit 4 before any designer call ----
# Regression: the mapping used to run inside <(...), where die only ended the subshell and
# its JSON was read as an object name.
case_count=$((case_count + 1))
lock_project="$(mktemp -d -t 1c-dev-test-lock-XXXX)"
printf '%s\n' '{"infobase":{"server":"none","base":"none"},"repository":{"path":"none"},"xmlDir":"src","tempXmlDir":".1c-temp"}' \
    > "$lock_project/$CONFIG_FILE_NAME"
lock_output="$(bash "$TESTS_DIR/../sh/lock-objects.sh" --project-dir "$lock_project" --files "Nonsense/X.xml,Catalogs/A.xml" 2>/dev/null)"
lock_exit=$?
lock_result="$(printf '%s\n' "$lock_output" | tail -n 1)"
lock_objects_file="$lock_project/$WORK_DIR_NAME/$OBJECTS_FILE_NAME"
case "$lock_result" in
    *'"ok":false'*'Cannot map path to a metadata object: Nonsense/X.xml'*) lock_message_ok="yes" ;;
    *) lock_message_ok="no" ;;
esac
if [ "$lock_exit" != "$EXIT_USAGE" ] || [ "$lock_message_ok" != "yes" ] || [ -e "$lock_objects_file" ]; then
    echo "FAIL lock-objects unmappable path: exit $lock_exit, result '$lock_result'"
    [ -e "$lock_objects_file" ] && echo "  objects.xml was written"
    failures=$((failures + 1))
fi
rm -rf "$lock_project"

# ---- objects.xml generation ----
case_count=$((case_count + 1))
out_file="$(mktemp -t 1c-dev-test-objects-XXXX.xml)"
write_objects_xml "$out_file" "Catalog.Товары" "Catalog.Товары.Form.ФормаЭлемента" "Configuration"
xml="$(read_text_smart "$out_file")"
for fragment in \
    'version="1.0"' \
    'xmlns="http://v8.1c.ru/8.3/config/objects"' \
    '<Object fullName="Catalog.Товары" includeChildObjects="false"/>' \
    '<Object fullName="Catalog.Товары.Form.ФормаЭлемента" includeChildObjects="false"/>' \
    '<Configuration includeChildObjects="false"/>'
do
    if ! printf '%s' "$xml" | grep -qF "$fragment"; then
        echo "FAIL objects.xml: missing fragment $fragment"
        failures=$((failures + 1))
    fi
done
sig="$(head -c 3 "$out_file" | od -An -tx1 | tr -d ' \n')"
if [ "$sig" != "efbbbf" ]; then
    echo "FAIL objects.xml: missing UTF-8 BOM"
    failures=$((failures + 1))
fi

# ---- repository report: grouped thousands separators (regression: detection capped at 999) ----
case_count=$((case_count + 1))
report_file="$(mktemp -t 1c-dev-test-report-XXXX.txt)"
cat > "$report_file" <<'REPORT'
MOXCEL
{"#","Версия:"}
{"#","1"}
{"#","Версия:"}
{"#","999"}
{"#","Версия:"}
{"#","2,555"}
{"#","Версия:"}
{"#","12 345"}
{"#","Версия конфигурации:"}
{"#","8.3.14"}
REPORT
versions="$(repo_versions_from_report "$report_file" | tr '\n' ' ' | sed 's/ *$//')"
if [ "$versions" != "1 999 2555 12345" ]; then
    echo "FAIL repo report: got '$versions' (expected '1 999 2555 12345')"
    failures=$((failures + 1))
fi
rm -f "$report_file"

# ---- designer errors: object names containing error words are not failures ----
case_count=$((case_count + 1))
DESIGNER_LOG_TEXT='Новый объект: Константа.УведомлятьОбОшибкахМеханизмаОнлайнСервисовРО
Новый объект: РегистрСведений.ДокументыСОшибкамиПроверкиКонтрагентов
Новый объект: РегистрСведений.ОшибкиЗакрытияМесяца
Ошибка: объект Справочник.Товары не может быть изменен
Не удалось обновить конфигурацию базы данных'
flagged="$(designer_errors | grep -c . || true)"
if [ "$flagged" != "2" ]; then
    echo "FAIL designer errors: flagged $flagged line(s), expected 2"
    designer_errors
    failures=$((failures + 1))
fi

# ---- load list: a form module is loaded through its Form.xml ----
while IFS='|' read -r path expected; do
    expected="${expected%$'\r'}"
    [ -n "$path" ] || continue
    case_count=$((case_count + 1))
    actual="$(resolve_load_path "$path")"
    if [ "$actual" != "$expected" ]; then
        echo "FAIL load path: '$path' -> '$actual' (expected '$expected')"
        failures=$((failures + 1))
    fi
done < "$TESTS_DIR/load-path-cases.txt"

# ---- module ids: dump file -> the ids a check finding may carry ----
join_ids() {
    # join_ids <path> -> "ru|en", "" for a file without a module, "!" for an unmappable module
    local ids
    if ! ids="$(module_ids_for_path "$1")"; then
        printf '!'
        return 0
    fi
    printf '%s' "$ids" | tr '\n' '|' | sed 's/|$//'
}
while IFS='|' read -r path expected; do
    expected="${expected%$'\r'}"
    [ -n "$path" ] || continue
    case_count=$((case_count + 1))
    actual="$(join_ids "$path")"
    case "$actual" in
        "") actual="-|-" ;;
        "!") actual="!|!" ;;
    esac
    if [ "$actual" != "$expected" ]; then
        echo "FAIL module ids: '$path' -> '$actual' (expected '$expected')"
        failures=$((failures + 1))
    fi
done < "$TESTS_DIR/module-id-cases.txt"

# ---- check log: repeats collapse, context lines and the repository notice drop out ----
case_count=$((case_count + 1))
findings="$(check_findings "$(read_text_smart "$TESTS_DIR/check-log-errors.txt")")"
if [ "$(count_lines "$findings")" != "4" ]; then
    echo "FAIL check log: $(count_lines "$findings") finding(s), expected 4"
    printf '%s\n' "$findings" | sed 's/^/  /'
    failures=$((failures + 1))
fi

# ---- check log: "no errors" lines are not findings, though they match the error pattern ----
case_count=$((case_count + 1))
clean_findings="$(check_findings "$(read_text_smart "$TESTS_DIR/check-log-clean.txt")")"
if [ -n "$clean_findings" ]; then
    echo "FAIL check log: clean log produced $(count_lines "$clean_findings") finding(s)"
    printf '%s\n' "$clean_findings" | sed 's/^/  /'
    failures=$((failures + 1))
fi

# ---- check log: findings split into edited modules, other modules, and no module at all ----
case_count=$((case_count + 1))
# The files "edited" in this scenario — the same list is spelled out in Write-CheckingParity.ps1.
EDITED_FILES=(
    "Documents/Инвентаризация/Ext/ObjectModule.bsl"
    "Documents/Инвентаризация/Forms/ФормаДокумента/Ext/Form.xml"
    "Documents/Инвентаризация.xml"
)
module_ids_for_paths "${EDITED_FILES[@]}"
edited_ids="$MODULE_IDS"
with_integrity="$findings
РегистрСведений.ЦеныНоменклатуры: Ни один из документов не является регистратором для регистра"
split_counts=""
for group in edited elsewhere unattributed; do
    split_counts="$split_counts/$(count_lines "$(split_check_findings "$with_integrity" "$edited_ids" "$group")")"
done
if [ "$split_counts" != "/3/1/1" ]; then
    echo "FAIL check split: /edited/elsewhere/unattributed = $split_counts, expected /3/1/1"
    failures=$((failures + 1))
fi

# ---- full mode: an edited .xml calls for the integrity check, a module alone does not ----
expect_metadata_edited() {
    # expect_metadata_edited <yes|no> <path>...
    local expected="$1" actual="no"
    shift
    case_count=$((case_count + 1))
    if is_metadata_edited "$@"; then actual="yes"; fi
    if [ "$actual" != "$expected" ]; then
        echo "FAIL metadata edited: '$*' -> $actual (expected $expected)"
        failures=$((failures + 1))
    fi
}
expect_metadata_edited yes "Documents/Заказ.xml"
expect_metadata_edited no "Documents/Заказ/Ext/ObjectModule.bsl"
expect_metadata_edited yes "Documents/Заказ/Ext/ObjectModule.bsl" "Documents/Заказ/Forms/Форма/Ext/Form.xml"
expect_metadata_edited no "CommonPictures/Логотип/Ext/Picture.png"

# ---- parity: PowerShell variant must produce identical objects.xml (modulo CRLF) ----
case_count=$((case_count + 1))
ps_exe=""
command -v pwsh >/dev/null 2>&1 && ps_exe="pwsh"
[ -z "$ps_exe" ] && command -v powershell.exe >/dev/null 2>&1 && ps_exe="powershell.exe"
if [ -n "$ps_exe" ]; then
    ps_out_file="$(mktemp -t 1c-dev-test-objects-ps-XXXX.xml)"
    "$ps_exe" -NoProfile -NonInteractive -Command \
        ". '$(to_win "$TESTS_DIR/../ps/Common.ps1")'; . '$(to_win "$TESTS_DIR/../ps/Mapping.ps1")'; New-ObjectsXml @('Catalog.Товары', 'Catalog.Товары.Form.ФормаЭлемента', 'Configuration') '$(to_win "$ps_out_file")'" >/dev/null
    if ! diff <(read_text_smart "$out_file" | tr -d '\r') <(read_text_smart "$ps_out_file" | tr -d '\r') >/dev/null; then
        echo "FAIL parity: bash and PowerShell objects.xml differ"
        diff <(read_text_smart "$out_file" | tr -d '\r') <(read_text_smart "$ps_out_file" | tr -d '\r') || true
        failures=$((failures + 1))
    fi
    rm -f "$ps_out_file"

    # ---- parity: module ids and check-log findings must match line for line ----
    case_count=$((case_count + 1))
    sh_parity_file="$(mktemp -t 1c-dev-test-checking-sh-XXXX.txt)"
    ps_parity_file="$(mktemp -t 1c-dev-test-checking-ps-XXXX.txt)"
    {
        while IFS='|' read -r path _; do
            [ -n "$path" ] || continue
            printf 'ids %s => %s\n' "$path" "$(join_ids "$path")"
        done < "$TESTS_DIR/module-id-cases.txt"
        printf '%s\n' "$with_integrity" | sed '/^$/d; s/^/finding /'
        for group in edited elsewhere unattributed; do
            split_check_findings "$with_integrity" "$edited_ids" "$group" | sed "s/^/$group /"
        done
    } > "$sh_parity_file"
    "$ps_exe" -NoProfile -NonInteractive -File "$(to_win "$TESTS_DIR/Write-CheckingParity.ps1")" "$(to_win "$ps_parity_file")" >/dev/null
    if ! diff <(tr -d '\r' < "$sh_parity_file") <(tr -d '\r' < "$ps_parity_file") >/dev/null; then
        echo "FAIL parity: bash and PowerShell module ids / check findings differ"
        diff <(tr -d '\r' < "$sh_parity_file") <(tr -d '\r' < "$ps_parity_file") || true
        failures=$((failures + 1))
    fi
    rm -f "$sh_parity_file" "$ps_parity_file"
else
    echo "skip parity: no pwsh/powershell.exe available"
fi
rm -f "$out_file"

if [ "$failures" -gt 0 ]; then
    echo "sh tests: $failures failure(s) out of $case_count cases"
    exit 1
fi
echo "sh tests: all $case_count cases passed"
exit 0
