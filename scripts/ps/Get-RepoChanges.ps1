# Get-RepoChanges.ps1 — detect repository versions newer than the last synced one.
# Contract: references/script-contract.md #get-repo-changes  (never modifies state)
param(
    [string]$ProjectDir,
    [switch]$Full
)
. "$PSScriptRoot\Common.ps1"

$context = Get-ProjectContext $ProjectDir
$state = Get-State $context
$lastSynced = 0
if ($state.PSObject.Properties.Name -contains 'lastRepoVersion' -and $state.lastRepoVersion) {
    $lastSynced = [int]$state.lastRepoVersion
}

$begin = if ($Full -or $lastSynced -eq 0) { 1 } else { $lastSynced + 1 }
$reportFile = Join-Path $context.WorkDir 'repo-report.txt'
if (Test-Path -LiteralPath $reportFile) { Remove-Item -LiteralPath $reportFile -Force }

Write-Info "repository report from version $begin"
$result = Invoke-Designer $context @('/ConfigurationRepositoryReport', $reportFile, '-NBegin', "$begin") -UseRepository -LogName 'get-repo-changes'
Assert-DesignerSuccess $context $result 'Repository report'

$versions = @(Get-RepoVersionsFromReport $reportFile)
$newVersions = @($versions | Where-Object { $_ -gt $lastSynced })
$latest = $lastSynced
if ($newVersions.Count -gt 0) { $latest = ($newVersions | Measure-Object -Maximum).Maximum }

Write-ResultJson @{
    ok               = $true
    hasChanges       = ($newVersions.Count -gt 0)
    lastSyncedVersion = $lastSynced
    latestVersion    = [int]$latest
    newVersions      = $newVersions.Count
}
exit $EXIT_OK
