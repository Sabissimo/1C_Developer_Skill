# Load-FromXml.ps1 — partial load of edited XML files into the main configuration + DB update.
# Contract: references/script-contract.md #load-from-xml
param(
    [string]$ProjectDir,
    [string]$Files,      # comma-separated paths relative to xmlDir
    [string]$ListFile    # file with one path per line, relative to xmlDir
)
. "$PSScriptRoot\Common.ps1"

$context = Get-ProjectContext $ProjectDir

$paths = @()
if ($Files) { $paths += @($Files -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
if ($ListFile) {
    if (-not (Test-Path -LiteralPath $ListFile)) {
        Exit-WithError $EXIT_USAGE "List file not found: $ListFile"
    }
    $paths += @(Get-Content -LiteralPath $ListFile -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
if ($paths.Count -eq 0) {
    Exit-WithError $EXIT_USAGE 'Nothing to load: pass -Files or -ListFile'
}

$absolutePaths = @()
foreach ($relative in $paths) {
    $absolute = Join-Path $context.XmlDir ($relative -replace '/', '\')
    if (-not (Test-Path -LiteralPath $absolute)) {
        Exit-WithError $EXIT_USAGE "File not found under xmlDir: $relative"
    }
    $absolutePaths += (Resolve-Path -LiteralPath $absolute).Path
}

# The designer reads the list file: absolute Windows paths, one per line, UTF-8 with BOM.
$designerListFile = Join-Path $context.WorkDir 'load-list.txt'
Write-TextUtf8Bom $designerListFile (($absolutePaths -join "`r`n") + "`r`n")

Write-Info "loading $($absolutePaths.Count) file(s) into the main configuration"
$load = Invoke-Designer $context @('/LoadConfigFromFiles', $context.XmlDir, '-listFile', $designerListFile, '-updateConfigDumpInfo') -LogName 'load-from-xml'
Assert-DesignerSuccess $context $load 'Partial load from XML'

Write-Info 'updating database configuration'
$dbUpdate = Invoke-Designer $context @('/UpdateDBCfg') -LogName 'load-update-dbcfg'
Assert-DesignerSuccess $context $dbUpdate 'Database configuration update'

Write-ResultJson @{ ok = $true; loaded = $absolutePaths.Count }
exit $EXIT_OK
