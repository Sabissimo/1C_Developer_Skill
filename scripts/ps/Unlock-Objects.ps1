# Unlock-Objects.ps1 — abort path: release repository locks without committing.
# Contract: references/script-contract.md #unlock-objects
param(
    [string]$ProjectDir,
    [string]$Objects     # comma-separated object names — overrides the recorded locked list
)
. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\Mapping.ps1"

$context = Get-ProjectContext $ProjectDir

$objectNames = @()
if ($Objects) {
    $objectNames = @($Objects -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
} else {
    $objectNames = @(Get-LockedObjects $context)
}
if ($objectNames.Count -eq 0) {
    Exit-WithError $EXIT_USAGE 'No locked objects recorded and none passed via -Objects'
}

New-ObjectsXml $objectNames $context.ObjectsFile

Write-Info "unlocking: $($objectNames -join ', ')"
$result = Invoke-Designer $context @('/ConfigurationRepositoryUnlock', '-Objects', $context.ObjectsFile, '-force') -UseRepository -LogName 'unlock-objects'
Assert-DesignerSuccess $context $result 'Repository unlock'

if (-not $Objects) {
    Set-LockedObjects $context @()
} else {
    # Partial unlock: drop only the released objects from the recorded list.
    $remaining = @(Get-LockedObjects $context | Where-Object { $objectNames -notcontains $_ })
    Set-LockedObjects $context $remaining
}

Write-ResultJson @{ ok = $true; objects = $objectNames }
exit $EXIT_OK
