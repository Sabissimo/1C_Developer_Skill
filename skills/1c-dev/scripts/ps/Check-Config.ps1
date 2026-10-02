# Check-Config.ps1 — run the configuration check the project chose (checkMode) on the
# main configuration, between load-from-xml and commit-to-repo. checkMode says which
# checks are allowed; the files edited in the task say which of those are needed.
# Contract: references/script-contract.md #check-config  (exit 5 when the check finds errors)
param(
    [string]$ProjectDir,
    [string]$Files,      # comma-separated paths relative to xmlDir — the files edited in the task
    [string]$ListFile,   # file with one path per line, relative to xmlDir
    [string]$Mode        # always | auto | modules | integrity | none — overrides checkMode for this run
)
. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\Mapping.ps1"
. "$PSScriptRoot\Checking.ps1"

$CHECK_LOG_NAME = 'check-config'
$CHECK_OPERATION = 'Configuration check'

# Why nothing was checked although a check is configured, by mode.
$NOTHING_TO_CHECK_REASON = @{
    $CHECK_MODE_AUTO      = 'no .xml file and no module among the edited files'
    $CHECK_MODE_MODULES   = 'no module among the edited files'
    $CHECK_MODE_INTEGRITY = 'no .xml file among the edited files'
}

function Write-SkippedResult([string]$CheckMode, [string]$Reason) {
    Write-Info "check skipped: $Reason"
    Write-ResultJson @{ ok = $true; mode = $CheckMode; skipped = $true; reason = $Reason }
    exit $EXIT_OK
}

function Select-ReportedFindings([string[]]$Findings) {
    return @($Findings | Select-Object -First $MAX_REPORTED_FINDINGS)
}

function Invoke-Check($Context, [string[]]$DesignerArgs) {
    # The designer check run. Returns its finding lines, its log file, and whether the
    # designer reported errors that the log parser could not find.
    $result = Invoke-Designer $Context $DesignerArgs -LogName $CHECK_LOG_NAME

    # Anything but "clean" (0) and "found errors" (101) means the check itself did not run.
    if ($result.ExitCode -ne 0 -and $result.ExitCode -ne $DESIGNER_EXIT_CHECK_ERRORS) {
        Assert-DesignerSuccess $Context $result $CHECK_OPERATION
    }

    $findings = @(Get-CheckFindings $result.Log)
    if ($result.ExitCode -eq 0) {
        $structured = @($findings | Where-Object { $_ -cmatch $CHECK_FINDING_PATTERN })
        if ($structured.Count -eq 0) {
            # The designer sometimes exits 0 on failure: scan what is left once the "no
            # errors" lines are gone — those would trip the error pattern by themselves.
            $remainder = [PSCustomObject]@{ ExitCode = 0; Log = ($findings -join "`n"); LogFile = $result.LogFile }
            Assert-DesignerSuccess $Context $remainder $CHECK_OPERATION
            $findings = @()
        }
    }
    return [PSCustomObject]@{
        Findings     = $findings
        LogFile      = $result.LogFile
        Unrecognised = ($result.ExitCode -eq $DESIGNER_EXIT_CHECK_ERRORS -and $findings.Count -eq 0)
    }
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

$paths = @()
if ($Files) { $paths += @($Files -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
if ($ListFile) {
    if (-not (Test-Path -LiteralPath $ListFile)) {
        Exit-WithError $EXIT_USAGE "List file not found: $ListFile"
    }
    $paths += @(Get-Content -LiteralPath $ListFile -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
if ($paths.Count -eq 0) {
    Exit-WithError $EXIT_USAGE 'Nothing to check: pass the edited files via -Files or -ListFile'
}

# The mode allows checks; the edited files decide which of the allowed ones are needed:
# metadata (.xml) -> integrity, modules -> syntax. "always" needs both whatever was edited.
$checkAlways = $checkMode -eq $CHECK_MODE_ALWAYS
$integrityAllowed = $checkAlways -or ($checkMode -eq $CHECK_MODE_AUTO) -or ($checkMode -eq $CHECK_MODE_INTEGRITY)
$modulesAllowed = $checkAlways -or ($checkMode -eq $CHECK_MODE_AUTO) -or ($checkMode -eq $CHECK_MODE_MODULES)

$moduleIds = @()
if ($modulesAllowed) {
    try {
        $moduleIds = @(ConvertTo-ModuleIdSet $paths)
    } catch {
        Exit-WithError $EXIT_USAGE $_.Exception.Message
    }
}
$checkIntegrity = $integrityAllowed -and ($checkAlways -or (Test-MetadataEdited $paths))
$checkModules = $modulesAllowed -and ($checkAlways -or ($moduleIds.Count -gt 0))
if (-not $checkIntegrity -and -not $checkModules) {
    Write-SkippedResult $checkMode $NOTHING_TO_CHECK_REASON[$checkMode]
}

$checks = @()
if ($checkIntegrity) { $checks += $CHECK_KIND_INTEGRITY }
if ($checkModules) { $checks += $CHECK_KIND_MODULES }
$checkArgs = $CHECK_MODULES_ARGS
if ($checkIntegrity -and $checkModules) { $checkArgs = $CHECK_BOTH_ARGS }
elseif ($checkIntegrity) { $checkArgs = $CHECK_INTEGRITY_ARGS }

Write-Info "checking the main configuration: $($checks -join ' + ')"
$run = Invoke-Check $context $checkArgs

$split = Split-CheckFindings @($run.Findings) $moduleIds
$errors = @($split.Edited)
$otherErrors = @($split.Elsewhere)
if ($checkIntegrity) {
    # Integrity findings name a metadata object, not a file: every one of them counts.
    $errors = @($split.Unattributed) + $errors
} else {
    $otherErrors += @($split.Unattributed)
}

$report = @{
    mode            = $checkMode
    checks          = $checks
    errorCount      = $errors.Count
    errors          = @(Select-ReportedFindings $errors)
    otherErrorCount = $otherErrors.Count
    otherErrors     = @(Select-ReportedFindings $otherErrors)
    logFile         = $run.LogFile
}

if ($errors.Count -gt 0) {
    Exit-WithError $EXIT_CHECK_FAILED "$CHECK_OPERATION found errors" $report
}
if ($run.Unrecognised) {
    # Designer exit 101 with nothing recognisable in the log: refuse to call that clean.
    Exit-WithError $EXIT_CHECK_FAILED "$CHECK_OPERATION reported errors (designer exit $DESIGNER_EXIT_CHECK_ERRORS) but the log holds no finding lines" $report
}

if ($otherErrors.Count -gt 0) { Write-Info "no findings in the edited modules; $($otherErrors.Count) elsewhere" }
$report.Remove('errors')
$report.ok = $true
$report.skipped = $false
Write-ResultJson $report
exit $EXIT_OK
