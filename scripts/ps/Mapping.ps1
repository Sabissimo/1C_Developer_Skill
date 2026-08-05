# Mapping.ps1 — XML file path -> metadata object name mapping + objects.xml generation.
# Dot-sourced by Lock-Objects.ps1 (after Common.ps1).
# Rules: references/file-to-object-map.md; contract: references/script-contract.md.

# Top-level dump directory -> metadata class (singular English name used in fullName).
$CLASS_BY_DIR = @{
    'Languages'                    = 'Language'
    'Subsystems'                   = 'Subsystem'
    'StyleItems'                   = 'StyleItem'
    'Styles'                       = 'Style'
    'CommonPictures'               = 'CommonPicture'
    'SessionParameters'            = 'SessionParameter'
    'Roles'                        = 'Role'
    'CommonTemplates'              = 'CommonTemplate'
    'FilterCriteria'               = 'FilterCriterion'
    'CommonModules'                = 'CommonModule'
    'CommonAttributes'             = 'CommonAttribute'
    'ExchangePlans'                = 'ExchangePlan'
    'XDTOPackages'                 = 'XDTOPackage'
    'WebServices'                  = 'WebService'
    'HTTPServices'                 = 'HTTPService'
    'WSReferences'                 = 'WSReference'
    'EventSubscriptions'           = 'EventSubscription'
    'ScheduledJobs'                = 'ScheduledJob'
    'SettingsStorages'             = 'SettingsStorage'
    'FunctionalOptions'            = 'FunctionalOption'
    'FunctionalOptionsParameters'  = 'FunctionalOptionsParameter'
    'DefinedTypes'                 = 'DefinedType'
    'CommonCommands'               = 'CommonCommand'
    'CommandGroups'                = 'CommandGroup'
    'Constants'                    = 'Constant'
    'CommonForms'                  = 'CommonForm'
    'Catalogs'                     = 'Catalog'
    'Documents'                    = 'Document'
    'DocumentNumerators'           = 'DocumentNumerator'
    'Sequences'                    = 'Sequence'
    'DocumentJournals'             = 'DocumentJournal'
    'Enums'                        = 'Enum'
    'Reports'                      = 'Report'
    'DataProcessors'               = 'DataProcessor'
    'ChartsOfCharacteristicTypes'  = 'ChartOfCharacteristicTypes'
    'ChartsOfAccounts'             = 'ChartOfAccounts'
    'ChartsOfCalculationTypes'     = 'ChartOfCalculationTypes'
    'InformationRegisters'         = 'InformationRegister'
    'AccumulationRegisters'        = 'AccumulationRegister'
    'AccountingRegisters'          = 'AccountingRegister'
    'CalculationRegisters'         = 'CalculationRegister'
    'BusinessProcesses'            = 'BusinessProcess'
    'Tasks'                        = 'Task'
    'ExternalDataSources'          = 'ExternalDataSource'
    'IntegrationServices'          = 'IntegrationService'
    'Bots'                         = 'Bot'
}

$ROOT_OBJECT_NAME = 'Configuration'

function Remove-XmlExtension([string]$Name) {
    return ($Name -replace '\.(xml|bsl|mdo)$', '')
}

function ConvertTo-MetadataObject([string]$RelativePath) {
    # Maps one path (relative to xmlDir, either separator) to a lockable object name.
    # Returns 'Configuration' for the root, $null for files that need no lock (ConfigDumpInfo.xml).
    $normalized = $RelativePath -replace '\\', '/' -replace '^\./', ''
    $segments = $normalized -split '/' | Where-Object { $_ -ne '' }
    if ($segments.Count -eq 0) { return $null }

    $first = $segments[0]
    if ($first -eq 'ConfigDumpInfo.xml') { return $null }
    if ($first -eq 'Configuration.xml' -or $first -eq 'Configuration') { return $ROOT_OBJECT_NAME }

    if (-not $CLASS_BY_DIR.ContainsKey($first)) {
        throw "Cannot map path to a metadata object: $RelativePath (unknown top-level directory '$first')"
    }
    $class = $CLASS_BY_DIR[$first]
    if ($segments.Count -lt 2) {
        throw "Cannot map path to a metadata object: $RelativePath (no object name segment)"
    }
    $objectName = Remove-XmlExtension $segments[1]
    $base = "$class.$objectName"

    # Forms and templates are separately lockable repository objects.
    if ($segments.Count -ge 4 -and $first -ne 'CommonForms' -and $first -ne 'CommonTemplates') {
        $kind = $segments[2]
        $childName = Remove-XmlExtension $segments[3]
        if ($kind -eq 'Forms')     { return "$base.Form.$childName" }
        if ($kind -eq 'Templates') { return "$base.Template.$childName" }
    }
    return $base
}

function ConvertTo-MetadataObjects([string[]]$RelativePaths) {
    $objects = @()
    foreach ($path in $RelativePaths) {
        $mapped = ConvertTo-MetadataObject $path
        if ($mapped) { $objects += $mapped }
    }
    return @($objects | Sort-Object -Unique)
}

function New-ObjectsXml([string[]]$Objects, [string]$OutputPath) {
    # objects.xml (version 1.0) consumed by /ConfigurationRepositoryLock|Commit|Unlock.
    $lines = @('<?xml version="1.0" encoding="UTF-8"?>')
    $lines += '<Objects xmlns="http://v8.1c.ru/8.3/config/objects" version="1.0">'
    foreach ($objectName in $Objects) {
        if ($objectName -eq $ROOT_OBJECT_NAME) {
            $lines += "`t<Configuration includeChildObjects=`"false`"/>"
        } else {
            $lines += "`t<Object fullName=`"$objectName`" includeChildObjects=`"false`"/>"
        }
    }
    $lines += '</Objects>'
    Write-TextUtf8Bom $OutputPath (($lines -join "`r`n") + "`r`n")
}

# ---- Locked-objects list persistence (.1c-work/locked-objects.json) ----
function Get-LockedObjects($Context) {
    if (-not (Test-Path -LiteralPath $Context.LockedList)) { return @() }
    $parsed = Get-Content -LiteralPath $Context.LockedList -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($parsed)
}

function Set-LockedObjects($Context, [string[]]$Objects) {
    if (-not $Objects -or $Objects.Count -eq 0) {
        if (Test-Path -LiteralPath $Context.LockedList) { Remove-Item -LiteralPath $Context.LockedList -Force }
        return
    }
    $json = ConvertTo-Json -InputObject @($Objects)
    [IO.File]::WriteAllText($Context.LockedList, $json, (New-Object Text.UTF8Encoding($false)))
}
