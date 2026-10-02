#!/usr/bin/env bash
# checking.sh — configuration check: designer arguments, check-log parsing and
# XML file path -> module id mapping.
# Sourced by check-config.sh (after common.sh and mapping.sh).
# Contract: references/script-contract.md #check-config — keep in sync with scripts/ps/Checking.ps1.

# /CheckConfig and /CheckModules exit with this code when the check ran and found errors.
DESIGNER_EXIT_CHECK_ERRORS=101

# One designer run per check-config call, chosen by what is to be checked.
# /CheckConfig with only -ConfigLogIntegrity does not look at modules, /CheckModules does
# not look at metadata, and /CheckConfig with the mode flags added does both in one pass.
# /CheckModules without a mode flag checks nothing and still reports "no syntax errors",
# so the mode flags are not optional.
CHECK_INTEGRITY_ARGS=(/CheckConfig -ConfigLogIntegrity)
CHECK_MODULES_ARGS=(/CheckModules -Server -ThinClient)
CHECK_BOTH_ARGS=(/CheckConfig -ConfigLogIntegrity -Server -ThinClient)

# Names of the two checks in the JSON result.
CHECK_KIND_INTEGRITY="integrity"
CHECK_KIND_MODULES="modules"

# Edited metadata lives in .xml files: one of them among the task's files calls for the
# integrity check.
XML_EXTENSION=".xml"

# Whole-line messages of a clean check. They contain "ошибок" / "не обнаружено" / "errors",
# so a check log must never go through designer_errors unfiltered.
CHECK_CLEAN_PATTERN='^(Синтаксических ошибок не обнаружено!?|Ошибок не обнаружено|No syntax errors found!?|No errors found)$'
# Printed for a repository-bound base opened without repository credentials; not a finding.
CHECK_NOISE_PATTERN='^(Соединение с хранилищем конфигурации не установлено|Connection to the configuration repository is not established)$'
# The source line quoted under a finding carries this marker at the error position.
CHECK_CONTEXT_MARKER='<<?>>'
# {Документ.Заказ.МодульОбъекта(3,11)}: <message> — the module id is what precedes "(".
CHECK_FINDING_PATTERN='^\{[^()]+\([0-9]+(,[0-9]+)?\)\}:'

# Findings listed in the JSON result; the counts stay complete and the log has the rest.
MAX_REPORTED_FINDINGS=50

# ---- Module id vocabulary ----
# The designer names a module by the configuration's script variant, not by the UI
# language: a Russian-variant configuration prints Документ.Заказ.МодульОбъекта even
# under /Len. Both spellings are generated and either one matches.
# (EXT_DIR_NAME comes from mapping.sh.)
FORMS_DIR_NAME="Forms"
COMMANDS_DIR_NAME="Commands"
MODULE_EXTENSION=".bsl"
COMMAND_MODULE_FILE="CommandModule"
COMMAND_MODULE_SUFFIX="/$EXT_DIR_NAME/$COMMAND_MODULE_FILE$MODULE_EXTENSION"

FORM_NAME_EN="Form"
FORM_NAME_RU="Форма"
COMMAND_NAME_EN="Command"
COMMAND_NAME_RU="Команда"

module_ru_by_file() {
    # module_ru_by_file <module file name without .bsl> -> Russian module name, or ""
    case "$1" in
        ObjectModule) echo МодульОбъекта ;;
        ManagerModule) echo МодульМенеджера ;;
        RecordSetModule) echo МодульНабораЗаписей ;;
        ValueManagerModule) echo МодульМенеджераЗначения ;;
        CommandModule) echo МодульКоманды ;;
        Module) echo Модуль ;;
        *) echo "" ;;
    esac
}

root_module_ru_by_file() {
    # root_module_ru_by_file <root module file name (<xmlDir>/Ext/<name>.bsl)> -> Russian name, or ""
    case "$1" in
        ManagedApplicationModule) echo МодульУправляемогоПриложения ;;
        OrdinaryApplicationModule) echo МодульОбычногоПриложения ;;
        SessionModule) echo МодульСеанса ;;
        ExternalConnectionModule) echo МодульВнешнегоСоединения ;;
        *) echo "" ;;
    esac
}

class_ru_by_dir() {
    # class_ru_by_dir <top-level-dir> -> Russian metadata class name (same keys as class_by_dir)
    case "$1" in
        Languages) echo Язык ;;
        Subsystems) echo Подсистема ;;
        StyleItems) echo ЭлементСтиля ;;
        Styles) echo Стиль ;;
        CommonPictures) echo ОбщаяКартинка ;;
        SessionParameters) echo ПараметрСеанса ;;
        Roles) echo Роль ;;
        CommonTemplates) echo ОбщийМакет ;;
        FilterCriteria) echo КритерийОтбора ;;
        CommonModules) echo ОбщийМодуль ;;
        CommonAttributes) echo ОбщийРеквизит ;;
        ExchangePlans) echo ПланОбмена ;;
        XDTOPackages) echo ПакетXDTO ;;
        WebServices) echo WebСервис ;;
        HTTPServices) echo HTTPСервис ;;
        WSReferences) echo WSСсылка ;;
        EventSubscriptions) echo ПодпискаНаСобытие ;;
        ScheduledJobs) echo РегламентноеЗадание ;;
        SettingsStorages) echo ХранилищеНастроек ;;
        FunctionalOptions) echo ФункциональнаяОпция ;;
        FunctionalOptionsParameters) echo ПараметрФункциональныхОпций ;;
        DefinedTypes) echo ОпределяемыйТип ;;
        CommonCommands) echo ОбщаяКоманда ;;
        CommandGroups) echo ГруппаКоманд ;;
        Constants) echo Константа ;;
        CommonForms) echo ОбщаяФорма ;;
        Catalogs) echo Справочник ;;
        Documents) echo Документ ;;
        DocumentNumerators) echo НумераторДокументов ;;
        Sequences) echo Последовательность ;;
        DocumentJournals) echo ЖурналДокументов ;;
        Enums) echo Перечисление ;;
        Reports) echo Отчет ;;
        DataProcessors) echo Обработка ;;
        ChartsOfCharacteristicTypes) echo ПланВидовХарактеристик ;;
        ChartsOfAccounts) echo ПланСчетов ;;
        ChartsOfCalculationTypes) echo ПланВидовРасчета ;;
        InformationRegisters) echo РегистрСведений ;;
        AccumulationRegisters) echo РегистрНакопления ;;
        AccountingRegisters) echo РегистрБухгалтерии ;;
        CalculationRegisters) echo РегистрРасчета ;;
        BusinessProcesses) echo БизнесПроцесс ;;
        Tasks) echo Задача ;;
        ExternalDataSources) echo ВнешнийИсточникДанных ;;
        IntegrationServices) echo СервисИнтеграции ;;
        Bots) echo Бот ;;
        *) echo "" ;;
    esac
}

# ---- File path -> module ids ----
is_form_path() {
    # is_form_path <suffix> -> 0 for the two dump paths that carry a form's module: the
    # module itself and the form file load-from-xml lists in its place.
    [ "$1" = "$FORM_FILE_SUFFIX" ] || [ "$1" = "$FORM_MODULE_SUFFIX" ]
}

join_segments() {
    # join_segments <segment>... -> "/a/b/c"
    local segment joined=""
    for segment in "$@"; do joined="$joined/$segment"; done
    printf '%s' "$joined"
}

module_id_pair() {
    # module_id_pair <path-segment>... -> Russian and English module id, one per line;
    # nothing for a path that holds no module.
    local count=$# file module_ru class_en owner_ru owner_en kind rest child child_rest
    if [ "$count" -eq 2 ] && [ "$1" = "$EXT_DIR_NAME" ]; then
        case "$2" in *"$MODULE_EXTENSION") ;; *) return 0 ;; esac
        file="${2%"$MODULE_EXTENSION"}"
        module_ru="$(root_module_ru_by_file "$file")"
        if [ -n "$module_ru" ]; then printf '%s\n%s\n' "$module_ru" "$file"; fi
        return 0
    fi
    class_en="$(class_by_dir "${1:-}")"
    if [ "$count" -lt 4 ] || [ -z "$class_en" ]; then return 0; fi

    owner_ru="$(class_ru_by_dir "$1").$2"
    owner_en="$class_en.$2"
    kind="$3"
    rest="$(join_segments "${@:3}")"

    # CommonForms/<Имя>/Ext/Form.xml — the object is the form.
    if is_form_path "$rest"; then
        printf '%s\n%s\n' "$owner_ru.$FORM_NAME_RU" "$owner_en.$FORM_NAME_EN"
        return 0
    fi
    # <Dir>/<Имя>/Ext/<Module>.bsl
    if [ "$count" -eq 4 ] && [ "$kind" = "$EXT_DIR_NAME" ]; then
        case "$4" in *"$MODULE_EXTENSION") ;; *) return 0 ;; esac
        file="${4%"$MODULE_EXTENSION"}"
        module_ru="$(module_ru_by_file "$file")"
        if [ -n "$module_ru" ]; then printf '%s\n%s\n' "$owner_ru.$module_ru" "$owner_en.$file"; fi
        return 0
    fi
    if [ "$count" -ge 6 ]; then
        child="$4"
        child_rest="$(join_segments "${@:5}")"
        # <Dir>/<Имя>/Forms/<Форма>/Ext/Form.xml
        if [ "$kind" = "$FORMS_DIR_NAME" ] && is_form_path "$child_rest"; then
            printf '%s\n%s\n' "$owner_ru.$FORM_NAME_RU.$child.$FORM_NAME_RU" "$owner_en.$FORM_NAME_EN.$child.$FORM_NAME_EN"
            return 0
        fi
        # <Dir>/<Имя>/Commands/<Команда>/Ext/CommandModule.bsl
        if [ "$kind" = "$COMMANDS_DIR_NAME" ] && [ "$child_rest" = "$COMMAND_MODULE_SUFFIX" ]; then
            printf '%s\n%s\n' \
                "$owner_ru.$COMMAND_NAME_RU.$child.$(module_ru_by_file "$COMMAND_MODULE_FILE")" \
                "$owner_en.$COMMAND_NAME_EN.$child.$COMMAND_MODULE_FILE"
            return 0
        fi
    fi
    return 0
}

module_ids_for_path() {
    # module_ids_for_path <relative-path> -> module ids the designer may print for one dump
    # file, one per line. No output for a file that holds no module. Returns 1 for a .bsl
    # file it cannot place: dropping it silently would hide that module's findings.
    local path segments=() segment ids
    path="$(printf '%s' "$1" | tr '\\' '/' | sed -E 's#^\./##')"
    while IFS= read -r segment; do
        [ -n "$segment" ] && segments+=("$segment")
    done < <(printf '%s\n' "$path" | tr '/' '\n')
    ids=""
    if [ ${#segments[@]} -gt 0 ]; then
        ids="$(module_id_pair "${segments[@]}")"
    fi
    if [ -z "$ids" ]; then
        case "$path" in *"$MODULE_EXTENSION") return 1 ;; esac
        return 0
    fi
    printf '%s\n' "$ids"
}

module_ids_for_paths() {
    # module_ids_for_paths <path>...
    # Sets MODULE_IDS: unique module ids, one per line, in first-seen order. Dies on a
    # module file it cannot place — so call it directly, never inside $(...), where die
    # would only end the subshell and its JSON would be captured instead of printed.
    local path ids result=""
    for path in "$@"; do
        if ! ids="$(module_ids_for_path "$path")"; then
            die "$EXIT_USAGE" "Cannot map module file to a module id: $path"
        fi
        [ -n "$ids" ] && result="$result$ids
"
    done
    MODULE_IDS="$(printf '%s' "$result" | awk 'length($0) > 0 && !seen[$0]++')"
}

is_metadata_edited() {
    # is_metadata_edited <path>... -> 0 when the task touched metadata, i.e. at least one .xml file
    local path
    for path in "$@"; do
        case "$path" in *"$XML_EXTENSION") return 0 ;; esac
    done
    return 1
}

# ---- Check-log parsing ----
check_findings() {
    # check_findings <log-text> -> finding lines, in log order, without repeats: the same
    # finding is printed once per checked mode (server, thin client).
    printf '%s\n' "$1" | tr -d '\r' \
        | { grep -vF -- "$CHECK_CONTEXT_MARKER" || true; } \
        | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
        | { grep -vE -- "$CHECK_CLEAN_PATTERN" || true; } \
        | { grep -vE -- "$CHECK_NOISE_PATTERN" || true; } \
        | awk 'length($0) > 0 && !seen[$0]++'
}

split_check_findings() {
    # split_check_findings <findings> <module-ids> <edited|elsewhere|unattributed>
    # edited = findings in one of the given modules; elsewhere = findings in any other
    # module; unattributed = findings that name no module (integrity findings name a
    # metadata object instead).
    awk -v want="$3" '
        NR == FNR { if (length($0) > 0) ids[$0] = 1; next }
        length($0) == 0 { next }
        {
            group = "unattributed"
            if ($0 ~ /^\{[^()]+\([0-9]+(,[0-9]+)?\)\}:/) {
                module = substr($0, 2, index($0, "(") - 2)
                group = (module in ids) ? "edited" : "elsewhere"
            }
            if (group == want) print
        }' <(printf '%s\n' "$2") <(printf '%s\n' "$1")
}

count_lines() {
    # count_lines <text> -> number of non-empty lines
    printf '%s\n' "$1" | grep -c . || true
}

json_string_list() {
    # json_string_list <lines> -> "a","b",... for the first MAX_REPORTED_FINDINGS lines
    local line list=""
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        if [ -n "$list" ]; then list="$list,"; fi
        list="$list\"$(json_escape "$line")\""
    done < <(printf '%s\n' "$1" | head -n "$MAX_REPORTED_FINDINGS")
    printf '%s' "$list"
}
