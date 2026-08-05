# Test-Connection.ps1 — validate platform, infobase and repository access in one call.
# Contract: references/script-contract.md #test-connection
param(
    [string]$ProjectDir
)
. "$PSScriptRoot\Common.ps1"

$context = Get-ProjectContext $ProjectDir
$exe = Resolve-OneCExe $context
Write-Info "1cv8.exe: $exe"

$reportFile = Join-Path $context.WorkDir 'connection-report.txt'
if (Test-Path -LiteralPath $reportFile) { Remove-Item -LiteralPath $reportFile -Force }

# A version-bounded repository report is the cheapest call that exercises the platform,
# the infobase credentials and the repository credentials at once.
$result = Invoke-Designer $context @('/ConfigurationRepositoryReport', $reportFile, '-NBegin', '1', '-NEnd', '1') -UseRepository -LogName 'test-connection'
Assert-DesignerSuccess $context $result 'Connection test'

if (-not (Test-Path -LiteralPath $reportFile)) {
    Exit-WithError $EXIT_DESIGNER 'Connection test failed: repository report was not produced' @{ logFile = $result.LogFile }
}

Write-ResultJson @{ ok = $true; exe = $exe; repoReachable = $true }
exit $EXIT_OK
