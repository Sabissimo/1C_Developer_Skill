# Write-CheckingParity.ps1 — dump the PowerShell variant's module ids and check-log
# findings in a canonical text form. run-tests.sh builds the same text from the bash
# variant and diffs the two.
param([Parameter(Mandatory = $true)][string]$OutputPath)
$ErrorActionPreference = 'Stop'
$testsDir = Split-Path -Parent $MyInvocation.MyCommand.Path

. "$testsDir\..\ps\Common.ps1"
. "$testsDir\..\ps\Mapping.ps1"
. "$testsDir\..\ps\Checking.ps1"

# The files "edited" in the parity scenario — the same list is spelled out in run-tests.sh.
$EDITED_FILES = @(
    'Documents/Инвентаризация/Ext/ObjectModule.bsl',
    'Documents/Инвентаризация/Forms/ФормаДокумента/Ext/Form.xml',
    'Documents/Инвентаризация.xml'
)

$lines = @()
foreach ($line in (Get-Content -LiteralPath "$testsDir\module-id-cases.txt" -Encoding UTF8)) {
    if (-not $line.Trim()) { continue }
    $path = ($line -split '\|', 2)[0]
    try {
        $ids = @(ConvertTo-ModuleIds $path)
        $lines += "ids $path => $($ids -join '|')"
    } catch {
        $lines += "ids $path => !"
    }
}

$findings = @(Get-CheckFindings (Read-TextSmart "$testsDir\check-log-errors.txt"))
$findings += 'РегистрСведений.ЦеныНоменклатуры: Ни один из документов не является регистратором для регистра'
$split = Split-CheckFindings $findings @(ConvertTo-ModuleIdSet $EDITED_FILES)
$lines += @($findings | ForEach-Object { "finding $_" })
$lines += @($split.Edited | ForEach-Object { "edited $_" })
$lines += @($split.Elsewhere | ForEach-Object { "elsewhere $_" })
$lines += @($split.Unattributed | ForEach-Object { "unattributed $_" })

[IO.File]::WriteAllLines($OutputPath, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
