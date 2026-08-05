# Commit-ToRepo.ps1 — commit locked objects to the repository (releases the locks).
# Contract: references/script-contract.md #commit-to-repo
param(
    [string]$ProjectDir,
    [Parameter(Mandatory = $false)]
    [string]$Comment,
    [switch]$KeepLocked
)
. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\Mapping.ps1"

$context = Get-ProjectContext $ProjectDir

if (-not $Comment) {
    Exit-WithError $EXIT_USAGE 'Commit comment is required: pass -Comment "<task summary>"'
}
$lockedObjects = @(Get-LockedObjects $context)
if ($lockedObjects.Count -eq 0) {
    Exit-WithError $EXIT_USAGE 'No locked objects recorded (.1c-work/locked-objects.json) — lock before committing'
}

$state = Get-State $context
$lastSynced = 0
if ($state.PSObject.Properties.Name -contains 'lastRepoVersion' -and $state.lastRepoVersion) {
    $lastSynced = [int]$state.lastRepoVersion
}

New-ObjectsXml $lockedObjects $context.ObjectsFile

Write-Info "committing $($lockedObjects.Count) object(s): $Comment"
$commitArgs = @('/ConfigurationRepositoryCommit', '-Objects', $context.ObjectsFile, '-comment', $Comment)
if ($KeepLocked) { $commitArgs += '-keepLocked' }
$commit = Invoke-Designer $context $commitArgs -UseRepository -LogName 'commit-to-repo'
Assert-DesignerSuccess $context $commit 'Repository commit'

# Learn the new repository version created by this commit.
$reportFile = Join-Path $context.WorkDir 'commit-report.txt'
if (Test-Path -LiteralPath $reportFile) { Remove-Item -LiteralPath $reportFile -Force }
$begin = if ($lastSynced -eq 0) { 1 } else { $lastSynced + 1 }
$report = Invoke-Designer $context @('/ConfigurationRepositoryReport', $reportFile, '-NBegin', "$begin") -UseRepository -LogName 'commit-report'
Assert-DesignerSuccess $context $report 'Repository report after commit'
$versions = @(Get-RepoVersionsFromReport $reportFile)
$latest = $lastSynced
if ($versions.Count -gt 0) {
    $maxSeen = ($versions | Measure-Object -Maximum).Maximum
    if ($maxSeen -gt $latest) { $latest = $maxSeen }
}

Set-State $context ([PSCustomObject]@{
    lastRepoVersion = [int]$latest
    lastSync        = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
})

if (-not $KeepLocked) { Set-LockedObjects $context @() }

Write-ResultJson @{ ok = $true; repoVersion = [int]$latest; objects = $lockedObjects }
exit $EXIT_OK
