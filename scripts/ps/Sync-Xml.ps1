# Sync-Xml.ps1 — dump the main configuration to the XML dir without touching unchanged files.
# Contract: references/script-contract.md #sync-xml
param(
    [string]$ProjectDir,
    [ValidateSet('auto', 'full')]
    [string]$Mode = 'auto'
)
. "$PSScriptRoot\Common.ps1"

$context = Get-ProjectContext $ProjectDir

function Get-RelativeFiles([string]$Root) {
    $rootFull = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\') + '\'
    Get-ChildItem -LiteralPath $Root -Recurse -File | ForEach-Object {
        $_.FullName.Substring($rootFull.Length)
    }
}

function Test-FilesEqual([string]$PathA, [string]$PathB) {
    $a = Get-Item -LiteralPath $PathA
    $b = Get-Item -LiteralPath $PathB
    if ($a.Length -ne $b.Length) { return $false }
    $hashA = (Get-FileHash -LiteralPath $PathA -Algorithm MD5).Hash
    $hashB = (Get-FileHash -LiteralPath $PathB -Algorithm MD5).Hash
    return $hashA -eq $hashB
}

function Invoke-FullDumpAndDiff($Context) {
    # Full dump into a clean temp dir, then mirror only real differences into XmlDir.
    if (Test-Path -LiteralPath $Context.TempXmlDir) {
        Remove-Item -LiteralPath $Context.TempXmlDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Context.TempXmlDir -Force | Out-Null

    $dump = Invoke-Designer $Context @('/DumpConfigToFiles', $Context.TempXmlDir) -LogName 'sync-xml-full'
    Assert-DesignerSuccess $Context $dump 'Full configuration dump'

    $changed = 0
    $deleted = 0
    $tempFiles = @(Get-RelativeFiles $Context.TempXmlDir)
    $tempSet = @{}
    foreach ($relative in $tempFiles) { $tempSet[$relative] = $true }

    foreach ($relative in $tempFiles) {
        $source = Join-Path $Context.TempXmlDir $relative
        $target = Join-Path $Context.XmlDir $relative
        if (-not (Test-Path -LiteralPath $target) -or -not (Test-FilesEqual $source $target)) {
            $targetDir = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            Copy-Item -LiteralPath $source -Destination $target -Force
            $changed++
        }
    }

    foreach ($relative in @(Get-RelativeFiles $Context.XmlDir)) {
        if (-not $tempSet.ContainsKey($relative)) {
            Remove-Item -LiteralPath (Join-Path $Context.XmlDir $relative) -Force
            $deleted++
        }
    }
    # Drop directories that became empty after deletions (deepest first).
    Get-ChildItem -LiteralPath $Context.XmlDir -Recurse -Directory |
        Sort-Object { $_.FullName.Length } -Descending |
        Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force) } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

    Write-Info "full sync: $changed changed, $deleted deleted"
    return @{ mode = 'full'; changed = $changed; deleted = $deleted }
}

$outcome = $null
if ($Mode -eq 'auto') {
    $xmlDirEmpty = (-not (Test-Path -LiteralPath $context.XmlDir)) -or
        (@(Get-ChildItem -LiteralPath $context.XmlDir -Force -ErrorAction SilentlyContinue).Count -eq 0)
    $dumpInfo = Join-Path $context.XmlDir 'ConfigDumpInfo.xml'

    if ($xmlDirEmpty) {
        # First dump for this project: write straight into the XML dir.
        if (-not (Test-Path -LiteralPath $context.XmlDir)) {
            New-Item -ItemType Directory -Path $context.XmlDir -Force | Out-Null
        }
        Write-Info 'initial full dump into empty XML dir'
        $dump = Invoke-Designer $context @('/DumpConfigToFiles', $context.XmlDir) -LogName 'sync-xml-initial'
        Assert-DesignerSuccess $context $dump 'Initial configuration dump'
        $outcome = @{ mode = 'initial'; changed = -1; deleted = -1 }
    }
    elseif (Test-Path -LiteralPath $dumpInfo) {
        Write-Info 'incremental dump (-update -force)'
        $dump = Invoke-Designer $context @('/DumpConfigToFiles', $context.XmlDir, '-update', '-force') -LogName 'sync-xml-incremental'
        $errors = @(Get-DesignerErrors $dump)
        if ($errors.Count -eq 0) {
            $outcome = @{ mode = 'incremental'; changed = -1; deleted = -1 }
        } else {
            Write-Info "incremental dump failed ($($errors -join ' | ')) — falling back to full dump"
            $outcome = Invoke-FullDumpAndDiff $context
        }
    }
    else {
        Write-Info 'no ConfigDumpInfo.xml — full dump with diff-sync'
        $outcome = Invoke-FullDumpAndDiff $context
    }
}
else {
    $outcome = Invoke-FullDumpAndDiff $context
}

Write-ResultJson @{ ok = $true; mode = $outcome.mode; changed = $outcome.changed; deleted = $outcome.deleted }
exit $EXIT_OK
