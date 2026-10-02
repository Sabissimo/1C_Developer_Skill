# Check-Config.ps1 — run the configuration check the project chose (checkMode) on the
# main configuration, between load-from-xml and commit-to-repo.
# Contract: references/script-contract.md #check-config  (exit 5 when the check finds errors)
param(
    [string]$ProjectDir,
    [string]$Files,      # comma-separated paths relative to xmlDir — the files edited in the task
    [string]$ListFile,   # file with one path per line, relative to xmlDir
    [string]$Mode        # config | modules | none — overrides checkMode for this run
)
. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\Mapping.ps1"
. "$PSScriptRoot\Checking.ps1"

$CHECK_LOG_NAME = 'check-config'
$CHECK_OPERATION = 'Configuration check'

function Write-SkippedResult([string]$CheckMode, [string]$Reason) {
    Write-Info "check skipped: $Reason"
    Write-ResultJson @{ ok = $true; mode = $CheckMode; skipped = $true; reason = $Reason }
    exit $EXIT_OK
}

function Select-ReportedFindings([string[]]$Findings) {
    return @($Findings | Select-Object -First $MAX_REPORTED_FINDINGS)
}

$context = Get-ProjectContext $ProjectDir

$checkMode = $context.CheckMode
if ($Mode) {
    if ($CHECK_MODES -cnotcontains $Mode) {
        Exit-WithError $EXIT_USAGE "Unknown mode: $Mode (expected one of $($CHECK_MODES -join ', '))"
    }
    $checkMode = $Mode
}
if ($checkMode -eq $CHECK_MODE_UNSET) { Write-SkippedResult $checkMode 'checkMode is not set in 1c-project.json' }
if ($checkMode -eq $CHECK_MODE_NONE)  { Write-SkippedResult $checkMode 'checkMode is none' }

$moduleIds = @()
if ($checkMode -eq $CHECK_MODE_MODULES) {
    $paths = @()
    if ($Files) { $paths += @($Files -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    if ($ListFile) {
        if (-not (Test-Path -LiteralPath $ListFile)) {
            Exit-WithError $EXIT_USAGE "List file not found: $ListFile"
        }
        $paths += @(Get-Content -LiteralPath $ListFile -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    if ($paths.Count -eq 0) {
        Exit-WithError $EXIT_USAGE 'modules mode needs the edited files: pass -Files or -ListFile'
    }
    try {
        $moduleIds = @(ConvertTo-ModuleIdSet $paths)
    } catch {
        Exit-WithError $EXIT_USAGE "$($_.Exception.Message) (run with -Mode $CHECK_MODE_CONFIG to check without module filtering)"
    }
    if ($moduleIds.Count -eq 0) { Write-SkippedResult $checkMode 'no module among the edited files' }
}

$checkArgs = $CHECK_CONFIG_ARGS
if ($checkMode -eq $CHECK_MODE_MODULES) { $checkArgs = $CHECK_MODULES_ARGS }

Write-Info "checking the main configuration (mode: $checkMode)"
$result = Invoke-Designer $context $checkArgs -LogName $CHECK_LOG_NAME

# Anything but "clean" (0) and "found errors" (101) means the check itself did not run.
if ($result.ExitCode -ne 0 -and $result.ExitCode -ne $DESIGNER_EXIT_CHECK_ERRORS) {
    Assert-DesignerSuccess $context $result $CHECK_OPERATION
}

$findings = @(Get-CheckFindings $result.Log)
$structured = @($findings | Where-Object { $_ -cmatch $CHECK_FINDING_PATTERN })

if ($result.ExitCode -eq 0 -and $structured.Count -eq 0) {
    # The designer sometimes exits 0 on failure: scan what is left once the "no errors"
    # lines are gone — those would trip the error pattern by themselves.
    $remainder = [PSCustomObject]@{ ExitCode = 0; Log = ($findings -join "`n"); LogFile = $result.LogFile }
    Assert-DesignerSuccess $context $remainder $CHECK_OPERATION
    Write-ResultJson @{
        ok = $true; mode = $checkMode; skipped = $false
        errorCount = 0; otherErrorCount = 0; otherErrors = @()
        logFile = $result.LogFile
    }
    exit $EXIT_OK
}

$errors = $findings
$otherErrors = @()
if ($checkMode -eq $CHECK_MODE_MODULES) {
    $split = Split-CheckFindings $findings $moduleIds
    $errors = @($split.Edited)
    $otherErrors = @($split.Other)
}

$report = @{
    mode            = $checkMode
    errorCount      = $errors.Count
    errors          = @(Select-ReportedFindings $errors)
    otherErrorCount = $otherErrors.Count
    otherErrors     = @(Select-ReportedFindings $otherErrors)
    logFile         = $result.LogFile
}

if ($errors.Count -gt 0) {
    Exit-WithError $EXIT_CHECK_FAILED "$CHECK_OPERATION found errors" $report
}
if ($otherErrors.Count -eq 0) {
    # Exit 101 with nothing recognisable in the log: refuse to call that clean.
    Exit-WithError $EXIT_CHECK_FAILED "$CHECK_OPERATION reported errors (exit $($result.ExitCode)) but the log holds no finding lines" $report
}

Write-Info "no findings in the edited modules; $($otherErrors.Count) elsewhere"
$report.Remove('errors')
$report.ok = $true
$report.skipped = $false
Write-ResultJson $report
exit $EXIT_OK
