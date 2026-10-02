# Script Contract

Source of truth for behavior parity between `scripts/ps/*.ps1` (PowerShell) and
`scripts/sh/*.sh` (Git Bash). Any change here must land in **both** implementations in the
same commit.

## Universal rules

- **Working files:** each script resolves the project from `--project-dir` / `-ProjectDir`
  (default: current directory). It requires `1c-project.json` there and maintains
  `.1c-state.json` (state) and `.1c-work/` (logs, reports, objects.xml).
- **stdout:** the **last line** is a single-line JSON result object. Success always has
  `"ok":true`; failure has `"ok":false` and `"error":"<message>"`. Extra fields per script
  below. Human-readable progress goes to **stderr** only.
- **Exit codes:**
  | code | meaning |
  |------|---------|
  | 0 | success |
  | 1 | designer/batch operation failed (see `log`, `logFile` fields) |
  | 2 | missing/invalid `1c-project.json`, or no 1C platform installed |
  | 3 | repository lock conflict (object held by another user) |
  | 4 | bad script arguments |
  | 5 | the configuration check ran and found errors (`check-config` only) |
- **Designer calls:** always append `/DisableStartupDialogs /DisableStartupMessages
  /Out <workdir>/<name>.log`; treat as failed when exit code ≠ 0 **or** the log contains
  error-marker lines (see `DESIGNER_ERROR_PATTERN` in the cores).
- **Argument naming:** PowerShell uses `-PascalCase` parameters, bash uses `--kebab-case`
  long options. Same names, same semantics, same defaults.
- **File lists** are passed via a UTF-8 text file (one path per line, relative to
  `xmlDir`) using `--list-file` / `-ListFile`, or inline comma-separated via
  `--files` / `-Files`. Both variants accept both.

## `1c-project.json` schema

```json
{
  "platformVersion": "8.3.24",              // optional; exact "8.3.24.1234" or prefix; omit = latest installed
  "infobase":  { "server": "srv1c", "base": "dev_base", "user": "Admin", "password": "" },
  "repository": { "path": "tcp://srv1c/repo", "user": "dev", "password": "" },
  "xmlDir": "src",                           // relative to project dir, or absolute
  "tempXmlDir": ".1c-temp",                  // used only by the full-dump fallback
  "checkMode": "modules"                     // optional: "config" | "modules" | "none"
}
```

`checkMode` picks what `check-config` runs between load and commit:

| value | check | what blocks the commit |
|---|---|---|
| `config` | `/CheckConfig` (integrity, references, thin client + server modules) | every finding |
| `modules` | `/CheckModules` (thin client + server) | findings in the modules edited in the task |
| `none` | nothing | — |

The key is optional. Absent means *not chosen yet*: `check-config` skips and reports
`"mode":"unset"`. Any other value is an invalid config — **every** script exits 2 on it.

`.1c-state.json`: `{ "lastRepoVersion": <int>, "lastSync": "<ISO-8601 UTC>" }`.

## Subcommands

### test-connection
Validates platform, infobase and repository access in one designer call
(`/ConfigurationRepositoryReport` bounded to version 1).
- Args: none beyond universal.
- Result: `{"ok":true,"exe":"<1cv8 path>","repoReachable":true}`

### get-repo-changes
Detects repository versions newer than `lastRepoVersion`.
- Args: `--full` / `-Full` — report from version 1 (used at setup to learn the current
  version when no state exists).
- Runs `/ConfigurationRepositoryReport <file> -NBegin <last+1>` and parses version numbers.
- Result: `{"ok":true,"hasChanges":<bool>,"lastSyncedVersion":<int>,"latestVersion":<int>,"newVersions":<int>}`
  (`latestVersion` = last synced when no changes). **Does not modify state.**

### update-from-repo
Full pull: `/ConfigurationRepositoryUpdateCfg -force` → `/UpdateDBCfg` → XML sync
(same logic as sync-xml) → state update (version from a fresh report).
- Args: `--mode auto|full` / `-Mode` (forwarded to the sync step, default `auto`).
- Result: `{"ok":true,"repoVersion":<int>,"syncMode":"incremental|full|initial","changed":<int>,"deleted":<int>}`

### sync-xml
Dump the current main configuration to the XML dir without touching unchanged files.
- Args: `--mode auto|full` / `-Mode auto|full` (default `auto`).
- `auto`: if `<xmlDir>/ConfigDumpInfo.xml` exists → `/DumpConfigToFiles <xmlDir> -update -force`;
  if that fails, fall back to `full`. If xmlDir is empty/missing → dump straight into it
  (mode `initial`).
- `full`: clear `tempXmlDir`, `/DumpConfigToFiles <tempXmlDir>` (complete), then byte-diff
  against `xmlDir`: copy new/changed files, delete files that vanished, copy
  `ConfigDumpInfo.xml` last.
- Result: `{"ok":true,"mode":"incremental|full|initial","changed":<int>,"deleted":<int>}`
  (`changed`/`deleted` are `-1` in incremental/initial modes — the designer doesn't report counts).

### lock-objects
Map changed files to metadata objects and lock them in the repository.
- Args: `--files a,b` / `--list-file f` (paths relative to `xmlDir`), or
  `--objects "Catalog.X,Document.Y"` to bypass mapping.
- Generates `.1c-work/objects.xml`, runs `/ConfigurationRepositoryLock -Objects <file>`.
- On conflict (log matches `LOCK_CONFLICT_PATTERN`): **exit 3**, result includes the
  conflicting log lines. Nothing may be edited after this failure.
- On success appends the objects to `.1c-work/locked-objects.json` (deduplicated) so
  commit/unlock know the full set.
- Result: `{"ok":true,"objects":["Catalog.X", ...]}`

### load-from-xml
Partial load of edited files into the main configuration + DB update.
- Args: `--files` / `--list-file` (paths relative to `xmlDir`), required.
- A form module (`…/Ext/Form/Module.bsl`) is replaced by its form (`…/Ext/Form.xml`) and
  the list is deduplicated: the designer rejects the module file on its own
  (`Неизвестный объект метаданных …Form.<Имя>.Ext`) and loads it with the form.
  `loaded` counts the files actually listed.
- Writes an absolute-Windows-path list file (UTF-8 BOM), runs
  `/LoadConfigFromFiles <xmlDir> -listFile <file> -updateConfigDumpInfo`, then `/UpdateDBCfg`.
- Result: `{"ok":true,"loaded":<int>}`

### check-config
Check the main configuration after a load, as the project's `checkMode` says.
- Args: `--files` / `--list-file` (the files edited in the task, paths relative to
  `xmlDir`) — required in `modules` mode, ignored otherwise;
  `--mode config|modules|none` / `-Mode` — overrides `checkMode` for this run.
- `none`, `unset`, or `modules` with no module among the files: no designer call,
  `{"ok":true,"mode":"<mode>","skipped":true,"reason":"<why>"}`.
- `modules`: `/CheckModules -ThinClient -Server`. `config`:
  `/CheckConfig -ConfigLogIntegrity -IncorrectReferences -ThinClient -Server`. No
  repository connection is opened.
- Designer exit code `0` = clean, `101` = the check found errors, anything else = the
  check did not run (exit 1). The generic error-marker scan is **not** applied to the raw
  log — "Ошибок не обнаружено" matches it — only to what remains after the clean lines
  are removed.
- Findings are the log lines left after dropping the quoted source lines (`<<?>>`), the
  clean lines and the repository notice; repeats (one per checked mode) collapse.
  `{<module id>(<line>,<col>)}: <message>` names the module.
- `modules` mode splits them: `errors` = findings in a module of the given files,
  `otherErrors` = the rest (other modules, and findings that name no module). A file maps
  to module ids as in references/file-to-object-map.md; a `.bsl` file that cannot be
  mapped is exit 4, not a silent pass. `config` mode puts every finding in `errors`.
- **Exit 5** when `errors` is non-empty (or the designer reported errors and no finding
  line was recognised):
  `{"ok":false,"error":"Configuration check found errors","mode":"<mode>","errorCount":<int>,"errors":[...],"otherErrorCount":<int>,"otherErrors":[...],"logFile":"<path>"}`
- Otherwise:
  `{"ok":true,"mode":"<mode>","skipped":false,"errorCount":0,"otherErrorCount":<int>,"otherErrors":[...],"logFile":"<path>"}`
- `errors` / `otherErrors` list at most 50 lines each; the counts are complete and
  `logFile` has everything. Does not modify state.

### commit-to-repo
Commit locked objects to the repository (releases the locks).
- Args: `--comment "<text>"` / `-Comment` (required); `--keep-locked` / `-KeepLocked`.
- Uses `.1c-work/objects.xml` built from `.1c-work/locked-objects.json`; errors (exit 4)
  if no locked-object list exists.
- `/ConfigurationRepositoryCommit -Objects <file> -comment <text>` then a bounded report
  to learn the new version; updates state; clears `locked-objects.json` (unless keep-locked).
- Result: `{"ok":true,"repoVersion":<int>,"objects":[...]}`

### unlock-objects
Abort path: release locks without committing.
- Args: `--objects` optional override; default = `.1c-work/locked-objects.json`.
- `/ConfigurationRepositoryUnlock -Objects <file> -force`; clears the locked list.
- Result: `{"ok":true,"objects":[...]}`

## objects.xml format

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Objects xmlns="http://v8.1c.ru/8.3/config/objects" version="1.0">
    <Object fullName="Catalog.Товары" includeChildObjects="false"/>
    <Object fullName="Catalog.Товары.Form.ФормаЭлемента" includeChildObjects="false"/>
    <Configuration includeChildObjects="false"/>  <!-- root, only when Configuration.xml changed -->
</Objects>
```
Written as UTF-8 **with BOM**. Verify against the target platform on the first live run
(see references/troubleshooting.md).
