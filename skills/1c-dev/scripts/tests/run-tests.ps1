# run-tests.ps1 — PowerShell-variant tests: mapping table + objects.xml generation.
# Cross-variant parity is checked by run-tests.sh (it re-runs these cases through bash).
$ErrorActionPreference = 'Stop'
$testsDir = Split-Path -Parent $MyInvocation.MyCommand.Path

. "$testsDir\..\ps\Common.ps1"
. "$testsDir\..\ps\Mapping.ps1"
. "$testsDir\..\ps\Checking.ps1"

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

# ---- load list: a form module is loaded through its Form.xml ----
foreach ($line in (Get-Content -LiteralPath "$testsDir\load-path-cases.txt" -Encoding UTF8)) {
    if (-not $line.Trim()) { continue }
    $parts = $line -split '\|', 2
    $caseCount++
    $actual = Resolve-LoadPath $parts[0]
    if ($actual -cne $parts[1]) {
        Write-Host "FAIL load path: '$($parts[0])' -> '$actual' (expected '$($parts[1])')"
        $failures++
    }
}

# ---- module ids: dump file -> the ids a check finding may carry ----
foreach ($line in (Get-Content -LiteralPath "$testsDir\module-id-cases.txt" -Encoding UTF8)) {
    if (-not $line.Trim()) { continue }
    $parts = $line -split '\|', 2
    $caseCount++
    try {
        $ids = @(ConvertTo-ModuleIds $parts[0])
        $actual = '-|-'
        if ($ids.Count -gt 0) { $actual = $ids -join '|' }
    } catch {
        $actual = '!|!'
    }
    if ($actual -cne $parts[1]) {
        Write-Host "FAIL module ids: '$($parts[0])' -> '$actual' (expected '$($parts[1])')"
        $failures++
    }
}

# ---- check log: repeats collapse, context lines and the repository notice drop out ----
$caseCount++
$findings = @(Get-CheckFindings (Read-TextSmart "$testsDir\check-log-errors.txt"))
if ($findings.Count -ne 4) {
    Write-Host "FAIL check log: $($findings.Count) finding(s), expected 4"
    $findings | ForEach-Object { Write-Host "  $_" }
    $failures++
}

# ---- check log: "no errors" lines are not findings, though they match the error pattern ----
$caseCount++
$cleanFindings = @(Get-CheckFindings (Read-TextSmart "$testsDir\check-log-clean.txt"))
if ($cleanFindings.Count -ne 0) {
    Write-Host "FAIL check log: clean log produced $($cleanFindings.Count) finding(s)"
    $cleanFindings | ForEach-Object { Write-Host "  $_" }
    $failures++
}

# ---- check log: findings split into edited modules, other modules, and no module at all ----
$caseCount++
$editedIds = @(ConvertTo-ModuleIdSet @(
    'Documents/Инвентаризация/Ext/ObjectModule.bsl',
    'Documents/Инвентаризация/Forms/ФормаДокумента/Ext/Form.xml',
    'Documents/Инвентаризация.xml'
))
$integrityFinding = 'РегистрСведений.ЦеныНоменклатуры: Ни один из документов не является регистратором для регистра'
$split = Split-CheckFindings ($findings + $integrityFinding) $editedIds
$splitCounts = "$($split.Edited.Count)/$($split.Elsewhere.Count)/$($split.Unattributed.Count)"
if ($splitCounts -ne '3/1/1') {
    Write-Host "FAIL check split: edited/elsewhere/unattributed = $splitCounts, expected 3/1/1"
    $failures++
}

# ---- full mode: an edited .xml calls for the integrity check, a module alone does not ----
$metadataCases = @(
    @{ Paths = @('Documents/Заказ.xml'); Expected = $true },
    @{ Paths = @('Documents/Заказ/Ext/ObjectModule.bsl'); Expected = $false },
    @{ Paths = @('Documents/Заказ/Ext/ObjectModule.bsl', 'Documents/Заказ/Forms/Форма/Ext/Form.xml'); Expected = $true },
    @{ Paths = @('CommonPictures/Логотип/Ext/Picture.png'); Expected = $false }
)
foreach ($case in $metadataCases) {
    $caseCount++
    $actual = Test-MetadataEdited $case.Paths
    if ($actual -ne $case.Expected) {
        Write-Host "FAIL metadata edited: '$($case.Paths -join ', ')' -> $actual (expected $($case.Expected))"
        $failures++
    }
}

if ($failures -gt 0) {
    Write-Host "ps tests: $failures failure(s) out of $caseCount cases"
    exit 1
}
Write-Host "ps tests: all $caseCount cases passed"
exit 0
