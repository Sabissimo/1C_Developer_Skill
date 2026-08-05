# Lock-Objects.ps1 — map changed files to metadata objects and lock them in the repository.
# Contract: references/script-contract.md #lock-objects  (exit 3 on lock conflict)
param(
    [string]$ProjectDir,
    [string]$Files,      # comma-separated paths relative to xmlDir
    [string]$ListFile,   # file with one path per line, relative to xmlDir
    [string]$Objects     # comma-separated object names — bypasses mapping
)
. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\Mapping.ps1"

$context = Get-ProjectContext $ProjectDir

$objectNames = @()
if ($Objects) {
    $objectNames = @($Objects -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
} else {
    $paths = @()
    if ($Files) { $paths += @($Files -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    if ($ListFile) {
        if (-not (Test-Path -LiteralPath $ListFile)) {
            Exit-WithError $EXIT_USAGE "List file not found: $ListFile"
        }
        $paths += @(Get-Content -LiteralPath $ListFile -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    if ($paths.Count -eq 0) {
        Exit-WithError $EXIT_USAGE 'Nothing to lock: pass -Files, -ListFile or -Objects'
    }
    try {
        $objectNames = @(ConvertTo-MetadataObjects $paths)
    } catch {
        Exit-WithError $EXIT_USAGE $_.Exception.Message
    }
}
if ($objectNames.Count -eq 0) {
    Exit-WithError $EXIT_USAGE 'The given files map to no lockable objects'
}

Write-Info "locking: $($objectNames -join ', ')"
New-ObjectsXml $objectNames $context.ObjectsFile

$result = Invoke-Designer $context @('/ConfigurationRepositoryLock', '-Objects', $context.ObjectsFile) -UseRepository -LogName 'lock-objects'
$errors = @(Get-DesignerErrors $result)
if ($result.ExitCode -ne 0 -or $errors.Count -gt 0) {
    $conflictLines = @(($result.Log -split "`r?`n") | Where-Object { $_ -match $LOCK_CONFLICT_PATTERN })
    if ($conflictLines.Count -gt 0) {
        Exit-WithError $EXIT_LOCK_CONFLICT 'Lock conflict: object(s) already locked by another repository user' @{
            conflict = ($conflictLines -join ' | ')
            logFile  = $result.LogFile
        }
    }
    Exit-WithError $EXIT_DESIGNER 'Repository lock failed' @{
        exitCode = $result.ExitCode
        log      = ($errors -join ' | ')
        logFile  = $result.LogFile
    }
}

# Remember the full locked set so commit/unlock cover everything across multiple lock calls.
$allLocked = @((@(Get-LockedObjects $context) + $objectNames) | Sort-Object -Unique)
Set-LockedObjects $context $allLocked

Write-ResultJson @{ ok = $true; objects = $objectNames }
exit $EXIT_OK
