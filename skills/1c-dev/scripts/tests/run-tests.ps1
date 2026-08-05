# run-tests.ps1 — PowerShell-variant tests: mapping table + objects.xml generation.
# Cross-variant parity is checked by run-tests.sh (it re-runs these cases through bash).
$ErrorActionPreference = 'Stop'
$testsDir = Split-Path -Parent $MyInvocation.MyCommand.Path

. "$testsDir\..\ps\Common.ps1"
. "$testsDir\..\ps\Mapping.ps1"

$failures = 0
$caseCount = 0

# ---- mapping cases ----
foreach ($line in (Get-Content -LiteralPath "$testsDir\mapping-cases.txt" -Encoding UTF8)) {
    if (-not $line.Trim()) { continue }
    $parts = $line -split '\|', 2
    $path = $parts[0]
    $expected = $parts[1]
    $caseCount++
    $actual = ConvertTo-MetadataObject $path
    if ($null -eq $actual) { $actual = '-' }
    if ($actual -ne $expected) {
        Write-Host "FAIL mapping: '$path' -> '$actual' (expected '$expected')"
        $failures++
    }
}

# ---- unknown top-level directory must throw ----
$caseCount++
try {
    ConvertTo-MetadataObject 'Nonsense/Файл.xml' | Out-Null
    Write-Host "FAIL mapping: unknown directory did not throw"
    $failures++
} catch { }

# ---- objects.xml generation ----
$caseCount++
$outFile = Join-Path $env:TEMP "1c-dev-test-objects.xml"
New-ObjectsXml @('Catalog.Товары', 'Catalog.Товары.Form.ФормаЭлемента', 'Configuration') $outFile
$xml = Read-TextSmart $outFile
$checks = @(
    'version="1.0"',
    'xmlns="http://v8.1c.ru/8.3/config/objects"',
    '<Object fullName="Catalog.Товары" includeChildObjects="false"/>',
    '<Object fullName="Catalog.Товары.Form.ФормаЭлемента" includeChildObjects="false"/>',
    '<Configuration includeChildObjects="false"/>'
)
foreach ($fragment in $checks) {
    if ($xml -notlike "*$fragment*") {
        Write-Host "FAIL objects.xml: missing fragment $fragment"
        $failures++
    }
}
$bytes = [IO.File]::ReadAllBytes($outFile)
if (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) {
    Write-Host 'FAIL objects.xml: missing UTF-8 BOM'
    $failures++
}
Remove-Item -LiteralPath $outFile -Force

# ---- repository report: grouped thousands separators (regression: detection capped at 999) ----
$caseCount++
$reportFile = Join-Path $env:TEMP '1c-dev-test-report.txt'
Set-Content -LiteralPath $reportFile -Encoding UTF8 -Value @(
    'MOXCEL',
    '{"#","Версия:"}', '{"#","1"}',
    '{"#","Версия:"}', '{"#","999"}',
    '{"#","Версия:"}', '{"#","2,555"}',
    '{"#","Версия:"}', '{"#","12 345"}',
    '{"#","Версия конфигурации:"}', '{"#","8.3.14"}'
)
$versions = @(Get-RepoVersionsFromReport $reportFile)
if (($versions -join ',') -ne '1,999,2555,12345') {
    Write-Host "FAIL repo report: got '$($versions -join ',')' (expected '1,999,2555,12345')"
    $failures++
}
Remove-Item -LiteralPath $reportFile -Force

# ---- designer errors: object names containing error words are not failures ----
$caseCount++
$log = @(
    'Новый объект: Константа.УведомлятьОбОшибкахМеханизмаОнлайнСервисовРО',
    'Новый объект: РегистрСведений.ДокументыСОшибкамиПроверкиКонтрагентов',
    'Новый объект: РегистрСведений.ОшибкиЗакрытияМесяца',
    'Ошибка: объект Справочник.Товары не может быть изменен',
    'Не удалось обновить конфигурацию базы данных'
) -join "`n"
$detected = @(Get-DesignerErrors ([PSCustomObject]@{ Log = $log; ExitCode = 0 }))
if ($detected.Count -ne 2) {
    Write-Host "FAIL designer errors: flagged $($detected.Count) line(s), expected 2"
    $detected | ForEach-Object { Write-Host "  $_" }
    $failures++
}

if ($failures -gt 0) {
    Write-Host "ps tests: $failures failure(s) out of $caseCount cases"
    exit 1
}
Write-Host "ps tests: all $caseCount cases passed"
exit 0
