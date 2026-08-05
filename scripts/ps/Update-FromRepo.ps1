# Update-FromRepo.ps1 — pull latest repository version into the infobase and re-sync XML.
# Contract: references/script-contract.md #update-from-repo
param(
    [string]$ProjectDir,
    [ValidateSet('auto', 'full')]
    [string]$Mode = 'auto'
)
. "$PSScriptRoot\Common.ps1"

$context = Get-ProjectContext $ProjectDir
$state = Get-State $context
$lastSynced = 0
if ($state.PSObject.Properties.Name -contains 'lastRepoVersion' -and $state.lastRepoVersion) {
    $lastSynced = [int]$state.lastRepoVersion
}

# Learn the current repository version first so state ends up accurate.
$reportFile = Join-Path $context.WorkDir 'repo-report.txt'
if (Test-Path -LiteralPath $reportFile) { Remove-Item -LiteralPath $reportFile -Force }
$begin = if ($lastSynced -eq 0) { 1 } else { $lastSynced + 1 }
$report = Invoke-Designer $context @('/ConfigurationRepositoryReport', $reportFile, '-NBegin', "$begin") -UseRepository -LogName 'update-report'
Assert-DesignerSuccess $context $report 'Repository report'
$versions = @(Get-RepoVersionsFromReport $reportFile)
$latest = $lastSynced
if ($versions.Count -gt 0) {
    $maxSeen = ($versions | Measure-Object -Maximum).Maximum
    if ($maxSeen -gt $latest) { $latest = $maxSeen }
}

Write-Info 'updating configuration from repository'
$update = Invoke-Designer $context @('/ConfigurationRepositoryUpdateCfg', '-force') -UseRepository -LogName 'update-cfg'
Assert-DesignerSuccess $context $update 'Update from repository'

Write-Info 'updating database configuration'
$dbUpdate = Invoke-Designer $context @('/UpdateDBCfg') -LogName 'update-dbcfg'
Assert-DesignerSuccess $context $dbUpdate 'Database configuration update'

# Re-sync XML via the sync script; keep its stdout (its own result JSON) off our stdout.
$syncOutput = & "$PSScriptRoot\Sync-Xml.ps1" -ProjectDir $context.ProjectDir -Mode $Mode
$syncExit = $LASTEXITCODE
$syncJson = ($syncOutput | Select-Object -Last 1)
if ($syncExit -ne 0) {
    Write-Output $syncJson   # surface the sync error result as ours
    exit $syncExit
}
$sync = $syncJson | ConvertFrom-Json

Set-State $context ([PSCustomObject]@{
    lastRepoVersion = [int]$latest
    lastSync        = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
})

Write-ResultJson @{
    ok          = $true
    repoVersion = [int]$latest
    syncMode    = $sync.mode
    changed     = $sync.changed
    deleted     = $sync.deleted
}
exit $EXIT_OK
