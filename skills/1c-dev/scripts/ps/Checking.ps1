# Checking.ps1 — configuration check: designer arguments, check-log parsing and
# XML file path -> module id mapping.
# Dot-sourced by Check-Config.ps1 (after Common.ps1 and Mapping.ps1).
# Contract: references/script-contract.md #check-config — keep in sync with scripts/sh/checking.sh.

# /CheckConfig and /CheckModules exit with this code when the check ran and found errors.
$DESIGNER_EXIT_CHECK_ERRORS = 101

# One designer run per check-config call, chosen by what is to be checked.
# /CheckConfig with only -ConfigLogIntegrity does not look at modules, /CheckModules does
# not look at metadata, and /CheckConfig with the mode flags added does both in one pass.
# /CheckModules without a mode flag checks nothing and still reports "no syntax errors",
# so the mode flags are not optional.
$CHECK_INTEGRITY_ARGS = @('/CheckConfig', '-ConfigLogIntegrity')
$CHECK_MODULES_ARGS   = @('/CheckModules', '-Server', '-ThinClient')
$CHECK_BOTH_ARGS      = @('/CheckConfig', '-ConfigLogIntegrity', '-Server', '-ThinClient')

# Names of the two checks in the JSON result.
$CHECK_KIND_INTEGRITY = 'integrity'
$CHECK_KIND_MODULES   = 'modules'

# Edited metadata lives in .xml files: one of them among the task's files calls for the
# integrity check.
$XML_EXTENSION = '.xml'

# Whole-line messages of a clean check. They contain "ошибок" / "не обнаружено" / "errors",
# so a check log must never go through Get-DesignerErrors unfiltered.
$CHECK_CLEAN_PATTERN = '^(Синтаксических ошибок не обнаружено!?|Ошибок не обнаружено|No syntax errors found!?|No errors found)$'
# Printed for a repository-bound base opened without repository credentials; not a finding.
$CHECK_NOISE_PATTERN = '^(Соединение с хранилищем конфигурации не установлено|Connection to the configuration repository is not established)$'
# The source line quoted under a finding carries this marker at the error position.
$CHECK_CONTEXT_MARKER = '<<?>>'
# {Документ.Заказ.МодульОбъекта(3,11)}: <message> — group 1 is the module id.
$CHECK_FINDING_PATTERN = '^\{([^()]+)\(\d+(,\d+)?\)\}:'

# Findings listed in the JSON result; the counts stay complete and the log has the rest.
$MAX_REPORTED_FINDINGS = 50

# ---- Module id vocabulary ----
# The designer names a module by the configuration's script variant, not by the UI
# language: a Russian-variant configuration prints Документ.Заказ.МодульОбъекта even
# under /Len. Both spellings are generated and either one matches.
$EXT_DIR_NAME      = 'Ext'
$FORMS_DIR_NAME    = 'Forms'
$COMMANDS_DIR_NAME = 'Commands'
$MODULE_EXTENSION  = '.bsl'
$COMMAND_MODULE_FILE   = 'CommandModule'
$COMMAND_MODULE_SUFFIX = "/$EXT_DIR_NAME/$COMMAND_MODULE_FILE$MODULE_EXTENSION"

$FORM_NAME_EN    = 'Form'
$FORM_NAME_RU    = 'Форма'
$COMMAND_NAME_EN = 'Command'
$COMMAND_NAME_RU = 'Команда'

# Module file name (without .bsl) -> Russian module name.
$MODULE_RU_BY_FILE = @{
    'ObjectModule'       = 'МодульОбъекта'
    'ManagerModule'      = 'МодульМенеджера'
    'RecordSetModule'    = 'МодульНабораЗаписей'
    'ValueManagerModule' = 'МодульМенеджераЗначения'
    'CommandModule'      = 'МодульКоманды'
    'Module'             = 'Модуль'
}

# Root module file name (<xmlDir>/Ext/<name>.bsl) -> Russian module name.
$ROOT_MODULE_RU_BY_FILE = @{
    'ManagedApplicationModule'  = 'МодульУправляемогоПриложения'
    'OrdinaryApplicationModule' = 'МодульОбычногоПриложения'
    'SessionModule'             = 'МодульСеанса'
    'ExternalConnectionModule'  = 'МодульВнешнегоСоединения'
}

# Top-level dump directory -> Russian metadata class name (same keys as $CLASS_BY_DIR).
$CLASS_RU_BY_DIR = @{
    'Languages'                    = 'Язык'
    'Subsystems'                   = 'Подсистема'
    'StyleItems'                   = 'ЭлементСтиля'
    'Styles'                       = 'Стиль'
    'CommonPictures'               = 'ОбщаяКартинка'
    'SessionParameters'            = 'ПараметрСеанса'
    'Roles'                        = 'Роль'
    'CommonTemplates'              = 'ОбщийМакет'
    'FilterCriteria'               = 'КритерийОтбора'
    'CommonModules'                = 'ОбщийМодуль'
    'CommonAttributes'             = 'ОбщийРеквизит'
    'ExchangePlans'                = 'ПланОбмена'
    'XDTOPackages'                 = 'ПакетXDTO'
    'WebServices'                  = 'WebСервис'
    'HTTPServices'                 = 'HTTPСервис'
    'WSReferences'                 = 'WSСсылка'
    'EventSubscriptions'           = 'ПодпискаНаСобытие'
    'ScheduledJobs'                = 'РегламентноеЗадание'
    'SettingsStorages'             = 'ХранилищеНастроек'
    'FunctionalOptions'            = 'ФункциональнаяОпция'
    'FunctionalOptionsParameters'  = 'ПараметрФункциональныхОпций'
    'DefinedTypes'                 = 'ОпределяемыйТип'
    'CommonCommands'               = 'ОбщаяКоманда'
    'CommandGroups'                = 'ГруппаКоманд'
    'Constants'                    = 'Константа'
    'CommonForms'                  = 'ОбщаяФорма'
    'Catalogs'                     = 'Справочник'
    'Documents'                    = 'Документ'
    'DocumentNumerators'           = 'НумераторДокументов'
    'Sequences'                    = 'Последовательность'
    'DocumentJournals'             = 'ЖурналДокументов'
    'Enums'                        = 'Перечисление'
    'Reports'                      = 'Отчет'
    'DataProcessors'               = 'Обработка'
    'ChartsOfCharacteristicTypes'  = 'ПланВидовХарактеристик'
    'ChartsOfAccounts'             = 'ПланСчетов'
    'ChartsOfCalculationTypes'     = 'ПланВидовРасчета'
    'InformationRegisters'         = 'РегистрСведений'
    'AccumulationRegisters'        = 'РегистрНакопления'
    'AccountingRegisters'          = 'РегистрБухгалтерии'
    'CalculationRegisters'         = 'РегистрРасчета'
    'BusinessProcesses'            = 'БизнесПроцесс'
    'Tasks'                        = 'Задача'
    'ExternalDataSources'          = 'ВнешнийИсточникДанных'
    'IntegrationServices'          = 'СервисИнтеграции'
    'Bots'                         = 'Бот'
}

# ---- File path -> module ids ----
function Test-FormPath([string]$Suffix) {
    # True for the two dump paths that carry a form's module: the module itself and the
    # form file load-from-xml lists in its place.
    return ($Suffix -ceq $FORM_FILE_SUFFIX -or $Suffix -ceq $FORM_MODULE_SUFFIX)
}

function Get-ModuleIdPair([string[]]$Segments) {
    # Russian and English module id for a path split into segments; nothing for a path
    # that holds no module.
    $count = $Segments.Count
    if ($count -eq 2 -and $Segments[0] -ceq $EXT_DIR_NAME) {
        if (-not $Segments[1].EndsWith($MODULE_EXTENSION, [StringComparison]::Ordinal)) { return @() }
        $file = $Segments[1].Substring(0, $Segments[1].Length - $MODULE_EXTENSION.Length)
        if (-not $ROOT_MODULE_RU_BY_FILE.ContainsKey($file)) { return @() }
        return @($ROOT_MODULE_RU_BY_FILE[$file], $file)
    }
    if ($count -lt 4 -or -not $CLASS_BY_DIR.ContainsKey($Segments[0])) { return @() }

    $ownerRu = "$($CLASS_RU_BY_DIR[$Segments[0]]).$($Segments[1])"
    $ownerEn = "$($CLASS_BY_DIR[$Segments[0]]).$($Segments[1])"
    $kind = $Segments[2]
    $rest = '/' + (@($Segments[2..($count - 1)]) -join '/')

    # CommonForms/<Имя>/Ext/Form.xml — the object is the form.
    if (Test-FormPath $rest) {
        return @("$ownerRu.$FORM_NAME_RU", "$ownerEn.$FORM_NAME_EN")
    }
    # <Dir>/<Имя>/Ext/<Module>.bsl
    if ($count -eq 4 -and $kind -ceq $EXT_DIR_NAME -and $Segments[3].EndsWith($MODULE_EXTENSION, [StringComparison]::Ordinal)) {
        $file = $Segments[3].Substring(0, $Segments[3].Length - $MODULE_EXTENSION.Length)
        if (-not $MODULE_RU_BY_FILE.ContainsKey($file)) { return @() }
        return @("$ownerRu.$($MODULE_RU_BY_FILE[$file])", "$ownerEn.$file")
    }
    if ($count -ge 6) {
        $child = $Segments[3]
        $childRest = '/' + (@($Segments[4..($count - 1)]) -join '/')
        # <Dir>/<Имя>/Forms/<Форма>/Ext/Form.xml
        if ($kind -ceq $FORMS_DIR_NAME -and (Test-FormPath $childRest)) {
            return @("$ownerRu.$FORM_NAME_RU.$child.$FORM_NAME_RU", "$ownerEn.$FORM_NAME_EN.$child.$FORM_NAME_EN")
        }
        # <Dir>/<Имя>/Commands/<Команда>/Ext/CommandModule.bsl
        if ($kind -ceq $COMMANDS_DIR_NAME -and $childRest -ceq $COMMAND_MODULE_SUFFIX) {
            return @(
                "$ownerRu.$COMMAND_NAME_RU.$child.$($MODULE_RU_BY_FILE[$COMMAND_MODULE_FILE])",
                "$ownerEn.$COMMAND_NAME_EN.$child.$COMMAND_MODULE_FILE"
            )
        }
    }
    return @()
}

function ConvertTo-ModuleIds([string]$RelativePath) {
    # Module ids the designer may print for one dump file (relative to xmlDir, either
    # separator). Empty for a file that holds no module. Throws for a .bsl file it cannot
    # place: dropping it silently would hide that module's findings.
    $normalized = $RelativePath -replace '\\', '/' -replace '^\./', ''
    $segments = @($normalized -split '/' | Where-Object { $_ -ne '' })
    $ids = @(Get-ModuleIdPair $segments)
    if ($ids.Count -eq 0 -and $normalized.EndsWith($MODULE_EXTENSION, [StringComparison]::Ordinal)) {
        throw "Cannot map module file to a module id: $RelativePath"
    }
    return $ids
}

function ConvertTo-ModuleIdSet([string[]]$RelativePaths) {
    $ids = @()
    foreach ($path in $RelativePaths) {
        foreach ($id in @(ConvertTo-ModuleIds $path)) {
            if ($ids -cnotcontains $id) { $ids += $id }
        }
    }
    return $ids
}

function Test-MetadataEdited([string[]]$RelativePaths) {
    # True when the task touched metadata, i.e. at least one .xml file.
    foreach ($path in $RelativePaths) {
        if ($path.EndsWith($XML_EXTENSION, [StringComparison]::Ordinal)) { return $true }
    }
    return $false
}

# ---- Check-log parsing ----
function Get-CheckFindings([string]$Log) {
    # Finding lines of a check log, in log order, without repeats: the same finding is
    # printed once per checked mode (server, thin client).
    $findings = New-Object 'System.Collections.Generic.List[string]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($rawLine in ($Log -split "`r?`n")) {
        if ($rawLine.Contains($CHECK_CONTEXT_MARKER)) { continue }
        $line = $rawLine.Trim()
        if (-not $line) { continue }
        if ($line -cmatch $CHECK_CLEAN_PATTERN -or $line -cmatch $CHECK_NOISE_PATTERN) { continue }
        if ($seen.Add($line)) { $findings.Add($line) }
    }
    return $findings.ToArray()
}

function Get-FindingModule([string]$Finding) {
    # Module id of a finding line, or $null for a finding that names no module.
    if ($Finding -cmatch $CHECK_FINDING_PATTERN) { return $Matches[1] }
    return $null
}

function Split-CheckFindings([string[]]$Findings, [string[]]$ModuleIds) {
    # Edited = findings in one of the given modules; Elsewhere = findings in any other
    # module; Unattributed = findings that name no module (integrity findings name a
    # metadata object instead).
    $edited = New-Object 'System.Collections.Generic.List[string]'
    $elsewhere = New-Object 'System.Collections.Generic.List[string]'
    $unattributed = New-Object 'System.Collections.Generic.List[string]'
    foreach ($finding in $Findings) {
        $module = Get-FindingModule $finding
        if (-not $module) { $unattributed.Add($finding) }
        elseif ($ModuleIds -ccontains $module) { $edited.Add($finding) }
        else { $elsewhere.Add($finding) }
    }
    return [PSCustomObject]@{
        Edited       = $edited.ToArray()
        Elsewhere    = $elsewhere.ToArray()
        Unattributed = $unattributed.ToArray()
    }
}
