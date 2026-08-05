#!/usr/bin/env bash
# run-tests.sh — bash-variant tests: mapping table + objects.xml generation + parity
# with the PowerShell variant (objects.xml content must match after normalization).
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$TESTS_DIR/../sh/common.sh"
. "$TESTS_DIR/../sh/mapping.sh"

# mapping.sh functions may call die/info from common.sh; LOCKED_LIST isn't needed here.
failures=0
case_count=0

# ---- mapping cases ----
while IFS='|' read -r path expected; do
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
