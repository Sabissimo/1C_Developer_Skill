#!/usr/bin/env bash
# mapping.sh — XML file path -> metadata object name mapping + objects.xml generation.
# Sourced by lock-objects.sh (after common.sh).
# Rules: references/file-to-object-map.md; contract: references/script-contract.md.

ROOT_OBJECT_NAME="Configuration"

class_by_dir() {
    # class_by_dir <top-level-dir> -> class name, or "" if unknown
    case "$1" in
        Languages) echo Language ;;
        Subsystems) echo Subsystem ;;
        StyleItems) echo StyleItem ;;
        Styles) echo Style ;;
        CommonPictures) echo CommonPicture ;;
        SessionParameters) echo SessionParameter ;;
        Roles) echo Role ;;
        CommonTemplates) echo CommonTemplate ;;
        FilterCriteria) echo FilterCriterion ;;
        CommonModules) echo CommonModule ;;
        CommonAttributes) echo CommonAttribute ;;
        ExchangePlans) echo ExchangePlan ;;
        XDTOPackages) echo XDTOPackage ;;
        WebServices) echo WebService ;;
        HTTPServices) echo HTTPService ;;
        WSReferences) echo WSReference ;;
        EventSubscriptions) echo EventSubscription ;;
        ScheduledJobs) echo ScheduledJob ;;
        SettingsStorages) echo SettingsStorage ;;
        FunctionalOptions) echo FunctionalOption ;;
        FunctionalOptionsParameters) echo FunctionalOptionsParameter ;;
        DefinedTypes) echo DefinedType ;;
        CommonCommands) echo CommonCommand ;;
        CommandGroups) echo CommandGroup ;;
        Constants) echo Constant ;;
        CommonForms) echo CommonForm ;;
        Catalogs) echo Catalog ;;
        Documents) echo Document ;;
        DocumentNumerators) echo DocumentNumerator ;;
        Sequences) echo Sequence ;;
        DocumentJournals) echo DocumentJournal ;;
        Enums) echo Enum ;;
        Reports) echo Report ;;
        DataProcessors) echo DataProcessor ;;
        ChartsOfCharacteristicTypes) echo ChartOfCharacteristicTypes ;;
        ChartsOfAccounts) echo ChartOfAccounts ;;
        ChartsOfCalculationTypes) echo ChartOfCalculationTypes ;;
        InformationRegisters) echo InformationRegister ;;
        AccumulationRegisters) echo AccumulationRegister ;;
        AccountingRegisters) echo AccountingRegister ;;
        CalculationRegisters) echo CalculationRegister ;;
        BusinessProcesses) echo BusinessProcess ;;
        Tasks) echo Task ;;
        ExternalDataSources) echo ExternalDataSource ;;
        IntegrationServices) echo IntegrationService ;;
        Bots) echo Bot ;;
        *) echo "" ;;
    esac
}

strip_xml_ext() {
    printf '%s' "$1" | sed -E 's/\.(xml|bsl|mdo)$//'
}

map_path_to_object() {
    # map_path_to_object <relative-path> -> object name on stdout.
    # "Configuration" for the root; empty output for files that need no lock.
    # Returns 1 for unmappable paths.
    local path segments first class object_name kind child base
    path="$(printf '%s' "$1" | tr '\\' '/' | sed -E 's#^\./##')"
    IFS='/' read -r -a segments <<< "$path"
    [ ${#segments[@]} -gt 0 ] || return 1

    first="${segments[0]}"
    if [ "$first" = "ConfigDumpInfo.xml" ]; then return 0; fi
    if [ "$first" = "Configuration.xml" ] || [ "$first" = "Configuration" ]; then
        echo "$ROOT_OBJECT_NAME"
        return 0
    fi

    class="$(class_by_dir "$first")"
    if [ -z "$class" ]; then
        info "Cannot map path to a metadata object: $1 (unknown top-level directory '$first')"
        return 1
    fi
    if [ ${#segments[@]} -lt 2 ]; then
        info "Cannot map path to a metadata object: $1 (no object name segment)"
        return 1
    fi
    object_name="$(strip_xml_ext "${segments[1]}")"
    base="$class.$object_name"

    # Forms and templates are separately lockable repository objects.
    if [ ${#segments[@]} -ge 4 ] && [ "$first" != "CommonForms" ] && [ "$first" != "CommonTemplates" ]; then
        kind="${segments[2]}"
        child="$(strip_xml_ext "${segments[3]}")"
        if [ "$kind" = "Forms" ]; then echo "$base.Form.$child"; return 0; fi
        if [ "$kind" = "Templates" ]; then echo "$base.Template.$child"; return 0; fi
    fi
    echo "$base"
}

map_paths_to_objects() {
    # map_paths_to_objects <path>... -> unique object names, one per line. Dies on unmappable paths.
    local path mapped result=""
    for path in "$@"; do
        if ! mapped="$(map_path_to_object "$path")"; then
            die "$EXIT_USAGE" "Cannot map path to a metadata object: $path"
        fi
        [ -n "$mapped" ] && result="$result$mapped
"
    done
    printf '%s' "$result" | sort -u | sed '/^$/d'
}

write_objects_xml() {
    # write_objects_xml <output-file> <object-name>...
    # objects.xml (version 1.0) consumed by /ConfigurationRepositoryLock|Commit|Unlock.
    local output="$1" body="" object_name
    shift
    for object_name in "$@"; do
        if [ "$object_name" = "$ROOT_OBJECT_NAME" ]; then
            body="$body	<Configuration includeChildObjects=\"false\"/>
"
        else
            body="$body	<Object fullName=\"$object_name\" includeChildObjects=\"false\"/>
"
        fi
    done
    write_utf8_bom "$output" "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<Objects xmlns=\"http://v8.1c.ru/8.3/config/objects\" version=\"1.0\">
$body</Objects>
"
}

# ---- Locked-objects list persistence (.1c-work/locked-objects.json) ----
get_locked_objects() {
    # -> object names, one per line
    [ -f "$LOCKED_LIST" ] || return 0
    grep -o '"[^"]*"' "$LOCKED_LIST" | sed -E 's/^"|"$//g'
}

set_locked_objects() {
    # set_locked_objects <object-name>...  (no args = clear)
    if [ $# -eq 0 ]; then
        rm -f "$LOCKED_LIST"
        return
    fi
    local json="[" first="yes" object_name
    for object_name in "$@"; do
        [ "$first" = "yes" ] || json="$json,"
        json="$json\"$(json_escape "$object_name")\""
        first="no"
    done
    printf '%s]\n' "$json" > "$LOCKED_LIST"
}
