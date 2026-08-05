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
  "tempXmlDir": ".1c-temp"                   // used only by the full-dump fallback
}
```

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
- Writes an absolute-Windows-path list file (UTF-8 BOM), runs
  `/LoadConfigFromFiles <xmlDir> -listFile <file> -updateConfigDumpInfo`, then `/UpdateDBCfg`.
- Result: `{"ok":true,"loaded":<int>}`

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
