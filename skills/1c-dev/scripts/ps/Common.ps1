# Common.ps1 — shared core for all 1c-dev skill scripts (PowerShell variant).
# Dot-source from every script:  . "$PSScriptRoot\Common.ps1"
# Contract: references/script-contract.md — keep in sync with scripts/sh/common.sh.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ---- Contract constants ----
$EXIT_OK            = 0
$EXIT_DESIGNER      = 1   # designer/batch operation failed
$EXIT_CONFIG        = 2   # missing/invalid 1c-project.json or environment
$EXIT_LOCK_CONFLICT = 3   # object already locked by another repository user
$EXIT_USAGE         = 4   # bad script arguments

$CONFIG_FILE_NAME = '1c-project.json'
$STATE_FILE_NAME  = '.1c-state.json'
$WORK_DIR_NAME    = '.1c-work'
$OBJECTS_FILE_NAME = 'objects.xml'
$LOCKED_LIST_NAME  = 'locked-objects.json'

# Designer log lines matching this mean failure even when the exit code is 0.
$DESIGNER_ERROR_PATTERN = '(?i)(ошибк|error|не удалось|не обнаружен|failed|failure|отказано|access denied|исключительн|нет доступа)'
$LOCK_CONFLICT_PATTERN  = '(?i)(захвачен|заблокирован|locked by|already locked|не может быть захвачен)'

# ---- Output helpers ----
function Write-Info([string]$Message) {
    [Console]::Error.WriteLine($Message)
}

function Write-ResultJson($Object) {
    # Final line of stdout: single-line JSON — the machine-readable result.
    Write-Output (ConvertTo-Json -InputObject $Object -Compress -Depth 8)
}

function Exit-WithError([int]$Code, [string]$Message, $Extra) {
    $result = @{ ok = $false; error = $Message }
    if ($null -ne $Extra) { foreach ($k in $Extra.Keys) { $result[$k] = $Extra[$k] } }
    Write-ResultJson $result
    exit $Code
}

# ---- Project context ----
function Get-ProjectContext([string]$ProjectDir) {
    if (-not $ProjectDir) { $ProjectDir = (Get-Location).Path }
    $ProjectDir = (Resolve-Path -LiteralPath $ProjectDir).Path
    $configPath = Join-Path $ProjectDir $CONFIG_FILE_NAME
    if (-not (Test-Path -LiteralPath $configPath)) {
        Exit-WithError $EXIT_CONFIG "Config not found: $configPath. Run the 1c-dev setup first."
    }
    try {
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Exit-WithError $EXIT_CONFIG "Cannot parse ${configPath}: $($_.Exception.Message)"
    }

    foreach ($required in @('infobase', 'repository', 'xmlDir', 'tempXmlDir')) {
        if (-not ($config.PSObject.Properties.Name -contains $required)) {
            Exit-WithError $EXIT_CONFIG "Config field missing: $required"
        }
    }
    foreach ($required in @('server', 'base')) {
        if (-not ($config.infobase.PSObject.Properties.Name -contains $required) -or -not $config.infobase.$required) {
            Exit-WithError $EXIT_CONFIG "Config field missing: infobase.$required"
        }
    }
    if (-not ($config.repository.PSObject.Properties.Name -contains 'path') -or -not $config.repository.path) {
        Exit-WithError $EXIT_CONFIG 'Config field missing: repository.path'
    }

    $workDir = Join-Path $ProjectDir $WORK_DIR_NAME
    if (-not (Test-Path -LiteralPath $workDir)) {
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    }

    function Resolve-InProject([string]$PathValue) {
        if ([IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
        return (Join-Path $ProjectDir $PathValue)
    }

    return [PSCustomObject]@{
        ProjectDir = $ProjectDir
        Config     = $config
        Connection = "$($config.infobase.server)\$($config.infobase.base)"
        XmlDir     = Resolve-InProject $config.xmlDir
        TempXmlDir = Resolve-InProject $config.tempXmlDir
        WorkDir    = $workDir
        StateFile  = Join-Path $ProjectDir $STATE_FILE_NAME
        ObjectsFile = Join-Path $workDir $OBJECTS_FILE_NAME
        LockedList  = Join-Path $workDir $LOCKED_LIST_NAME
    }
}

# ---- State ----
function Get-State($Context) {
    if (Test-Path -LiteralPath $Context.StateFile) {
        return Get-Content -LiteralPath $Context.StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return [PSCustomObject]@{ lastRepoVersion = 0; lastSync = $null }
}

function Set-State($Context, $State) {
    $json = ConvertTo-Json -InputObject $State -Depth 4
    [IO.File]::WriteAllText($Context.StateFile, $json, (New-Object Text.UTF8Encoding($false)))
}

# ---- Platform resolution ----
function Resolve-OneCExe($Context) {
    $roots = @()
    if ($env:ProgramFiles) { $roots += (Join-Path $env:ProgramFiles '1cv8') }
    $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($pf86) { $roots += (Join-Path $pf86 '1cv8') }
    $roots = $roots | Where-Object { Test-Path -LiteralPath $_ }
    if (-not $roots) {
        Exit-WithError $EXIT_CONFIG 'No 1C platform installation found under Program Files\1cv8'
    }

    $wanted = $null
    if ($Context.Config.PSObject.Properties.Name -contains 'platformVersion') {
        $wanted = $Context.Config.platformVersion
    }

    $candidates = @()
    foreach ($root in $roots) {
        $candidates += Get-ChildItem -LiteralPath $root -Directory |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bin\1cv8.exe') }
    }
    if (-not $candidates) {
        Exit-WithError $EXIT_CONFIG 'No 1cv8.exe found in any Program Files\1cv8\<version>\bin'
    }

    if ($wanted) {
        # platformVersion may be a prefix ("8.3.24") or a full build ("8.3.24.1234")
        $match = $candidates |
            Where-Object { $_.Name -eq $wanted -or $_.Name.StartsWith("$wanted.") } |
            Sort-Object { [version]$_.Name } | Select-Object -Last 1
        if (-not $match) {
            Exit-WithError $EXIT_CONFIG "Configured platformVersion '$wanted' not installed. Installed: $(($candidates.Name | Sort-Object) -join ', ')"
        }
        return (Join-Path $match.FullName 'bin\1cv8.exe')
    }

    $latest = $candidates | Sort-Object { [version]$_.Name } | Select-Object -Last 1
    return (Join-Path $latest.FullName 'bin\1cv8.exe')
}

# ---- Encoding-tolerant text reading (designer logs/reports: UTF-16, UTF-8 or CP1251) ----
function Read-TextSmart([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) { return '' }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return [Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    $strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
    try {
        return $strictUtf8.GetString($bytes)
    } catch {
        return [Text.Encoding]::GetEncoding(1251).GetString($bytes)
    }
}

function Write-TextUtf8Bom([string]$Path, [string]$Content) {
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($true)))
}

# ---- Designer invocation ----
function ConvertTo-ArgString([string[]]$Arguments) {
    $quoted = foreach ($arg in $Arguments) {
        if ($arg -match '[\s"]' -or $arg -eq '') {
            '"' + ($arg -replace '"', '\"') + '"'
        } else {
            $arg
        }
    }
    return ($quoted -join ' ')
}

function Invoke-Designer($Context, [string[]]$OperationArgs, [switch]$UseRepository, [string]$LogName = 'designer') {
    $exe = Resolve-OneCExe $Context
    $logFile = Join-Path $Context.WorkDir "$LogName.log"
    if (Test-Path -LiteralPath $logFile) { Remove-Item -LiteralPath $logFile -Force }

    $designerArgs = @('DESIGNER', '/S', $Context.Connection)
    $ib = $Context.Config.infobase
    if ($ib.PSObject.Properties.Name -contains 'user' -and $ib.user) {
        $designerArgs += @('/N', [string]$ib.user)
        $pw = ''
        if ($ib.PSObject.Properties.Name -contains 'password' -and $null -ne $ib.password) { $pw = [string]$ib.password }
        $designerArgs += @('/P', $pw)
    }
    if ($UseRepository) {
        $repo = $Context.Config.repository
        $designerArgs += @('/ConfigurationRepositoryF', [string]$repo.path)
        if ($repo.PSObject.Properties.Name -contains 'user' -and $repo.user) {
            $designerArgs += @('/ConfigurationRepositoryN', [string]$repo.user)
            $rpw = ''
            if ($repo.PSObject.Properties.Name -contains 'password' -and $null -ne $repo.password) { $rpw = [string]$repo.password }
            $designerArgs += @('/ConfigurationRepositoryP', $rpw)
        }
    }
    $designerArgs += $OperationArgs
    $designerArgs += @('/DisableStartupDialogs', '/DisableStartupMessages', '/Out', $logFile)

    Write-Info "designer: $($OperationArgs -join ' ')"
    # 1cv8.exe is a GUI-subsystem binary: Start-Process -Wait is required to block until exit.
    $process = Start-Process -FilePath $exe -ArgumentList (ConvertTo-ArgString $designerArgs) -Wait -PassThru -WindowStyle Hidden
    $log = Read-TextSmart $logFile

    return [PSCustomObject]@{
        ExitCode = $process.ExitCode
        Log      = $log
        LogFile  = $logFile
    }
}

function Get-DesignerErrors($DesignerResult) {
    # Failure = non-zero exit code OR error-looking lines in the /Out log.
    $errorLines = @()
    foreach ($line in ($DesignerResult.Log -split "`r?`n")) {
        if ($line -match $DESIGNER_ERROR_PATTERN) { $errorLines += $line.Trim() }
    }
    if ($DesignerResult.ExitCode -ne 0 -and -not $errorLines) {
        $errorLines += "designer exit code $($DesignerResult.ExitCode)"
    }
    if ($DesignerResult.ExitCode -eq 0 -and -not $errorLines) { return @() }
    return $errorLines
}

function Assert-DesignerSuccess($Context, $DesignerResult, [string]$Operation) {
    $errors = @(Get-DesignerErrors $DesignerResult)
    if ($errors.Count -gt 0) {
        Exit-WithError $EXIT_DESIGNER "$Operation failed" @{
            exitCode = $DesignerResult.ExitCode
            log      = ($errors -join ' | ')
            logFile  = $DesignerResult.LogFile
        }
    }
}

# ---- Repository report parsing ----
function Get-RepoVersionsFromReport([string]$ReportPath) {
    # The designer writes the report as an MXL spreadsheet (MOXCEL) on most builds even
    # when the file name ends in .txt; some builds write plain text. Handle both.
    $text = Read-TextSmart $ReportPath
    $versions = @()

    if ($text -match 'MOXCEL' -or $text -match '\{"#","') {
        # MXL: versions are cell pairs — a {"#","Версия:"} label cell whose next string
        # cell holds the number. "Версия конфигурации:" etc. must not match.
        $cells = [regex]::Matches($text, '\{"#","([^"]*)"\}')
        for ($i = 0; $i -lt $cells.Count - 1; $i++) {
            $label = $cells[$i].Groups[1].Value.Trim()
            if ($label -eq 'Версия:' -or $label -eq 'Version:') {
                $value = $cells[$i + 1].Groups[1].Value.Trim()
                if ($value -match '^\d+$') { $versions += [int]$value }
            }
        }
    } else {
        foreach ($line in ($text -split "`r?`n")) {
            if ($line -match '^\s*(Версия|Version)\s*:?\s*(\d+)\s*$') {
                $versions += [int]$Matches[2]
            }
        }
    }
    return ($versions | Sort-Object -Unique)
}
