#!/usr/bin/env bash
# sync-xml.sh — dump the main configuration to the XML dir without touching unchanged files.
# Contract: references/script-contract.md #sync-xml
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"

project_dir=""
mode="auto"
while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir) project_dir="$2"; shift 2 ;;
        --mode) mode="$2"; shift 2 ;;
        *) die "$EXIT_USAGE" "Unknown argument: $1" ;;
    esac
done
case "$mode" in auto|full) ;; *) die "$EXIT_USAGE" "Invalid --mode: $mode (auto|full)" ;; esac

load_context "$project_dir"

full_dump_and_diff() {
    # Full dump into a clean temp dir, then mirror only real differences into XML_DIR.
    rm -rf "$TEMP_XML_DIR"
    mkdir -p "$TEMP_XML_DIR"

    run_designer sync-xml-full no /DumpConfigToFiles "$(to_win "$TEMP_XML_DIR")"
    assert_designer_success "Full configuration dump"

    SYNC_CHANGED=0
    SYNC_DELETED=0
    local relative source target target_dir

    while IFS= read -r -d '' source; do
        relative="${source#"$TEMP_XML_DIR"/}"
        target="$XML_DIR/$relative"
        if [ ! -f "$target" ] || ! cmp -s "$source" "$target"; then
            target_dir="$(dirname "$target")"
            mkdir -p "$target_dir"
            cp -f "$source" "$target"
            SYNC_CHANGED=$((SYNC_CHANGED + 1))
        fi
    done < <(find "$TEMP_XML_DIR" -type f -print0)

    while IFS= read -r -d '' target; do
        relative="${target#"$XML_DIR"/}"
        if [ ! -f "$TEMP_XML_DIR/$relative" ]; then
            rm -f "$target"
            SYNC_DELETED=$((SYNC_DELETED + 1))
        fi
    done < <(find "$XML_DIR" -type f -print0)

    # Drop directories that became empty after deletions.
    find "$XML_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null || true

    info "full sync: $SYNC_CHANGED changed, $SYNC_DELETED deleted"
    SYNC_MODE="full"
}

SYNC_MODE=""
SYNC_CHANGED=-1
SYNC_DELETED=-1

if [ "$mode" = "auto" ]; then
    xml_dir_empty="yes"
    if [ -d "$XML_DIR" ] && [ -n "$(ls -A "$XML_DIR" 2>/dev/null)" ]; then
        xml_dir_empty="no"
    fi

    if [ "$xml_dir_empty" = "yes" ]; then
        # First dump for this project: write straight into the XML dir.
        mkdir -p "$XML_DIR"
        info "initial full dump into empty XML dir"
        run_designer sync-xml-initial no /DumpConfigToFiles "$(to_win "$XML_DIR")"
        assert_designer_success "Initial configuration dump"
        SYNC_MODE="initial"
    elif [ -f "$XML_DIR/ConfigDumpInfo.xml" ]; then
        info "incremental dump (-update -force)"
        run_designer sync-xml-incremental no /DumpConfigToFiles "$(to_win "$XML_DIR")" -update -force
        errors="$(designer_errors)"
        if [ "$DESIGNER_EXIT" -eq 0 ] && [ -z "$errors" ]; then
            SYNC_MODE="incremental"
        else
            info "incremental dump failed — falling back to full dump"
            full_dump_and_diff
        fi
    else
        info "no ConfigDumpInfo.xml — full dump with diff-sync"
        full_dump_and_diff
    fi
else
    full_dump_and_diff
fi

printf '{"ok":true,"mode":"%s","changed":%s,"deleted":%s}\n' "$SYNC_MODE" "$SYNC_CHANGED" "$SYNC_DELETED"
exit "$EXIT_OK"
