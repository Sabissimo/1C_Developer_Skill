# 1C Designer Batch Commands Used by This Skill

Reference for the `1cv8.exe DESIGNER` batch-mode commands the scripts call. Full
documentation: 1C:Enterprise Administrator Guide, "Command-line startup options".

## Common switches (every call)

```
1cv8.exe DESIGNER /S "server\base" [/N user /P password]
    [/ConfigurationRepositoryF <path> /ConfigurationRepositoryN <user> /ConfigurationRepositoryP <password>]
    <operation> /DisableStartupDialogs /DisableStartupMessages /Out <logfile>
```

- `/S server\base` — server infobase (this skill supports server bases only).
- `/Out <file>` — writes the batch log. **The designer sometimes exits 0 on failure** —
  the scripts always scan this log for error markers too.
- Repository switches are needed only for `ConfigurationRepository*` operations.
- The infobase must already be **bound** to the repository (done once, manually in the
  Designer: Configuration → Configuration Repository → Bind).

## Operations

| Command | Purpose | Notes |
|---|---|---|
| `/ConfigurationRepositoryReport <file> [-NBegin N] [-NEnd N]` | Version-history report | Cheapest full-stack connectivity check; scripts parse `Версия: N` / `Version: N` lines |
| `/ConfigurationRepositoryUpdateCfg -force` | Update main configuration from the repository | `-force` answers "yes" to prompts (new objects, unbound changes) |
| `/ConfigurationRepositoryLock -Objects <objects.xml>` | Lock objects for editing | 8.3.11+; fails if already locked by another user |
| `/ConfigurationRepositoryCommit -Objects <objects.xml> -comment "<text>" [-keepLocked]` | Commit locked objects | Releases locks unless `-keepLocked` |
| `/ConfigurationRepositoryUnlock -Objects <objects.xml> -force` | Release locks without committing | 8.3.11+ |
| `/DumpConfigToFiles <dir> [-update -force]` | Dump configuration to XML | `-update` = incremental via `ConfigDumpInfo.xml`: touches only changed files, removes deleted |
| `/LoadConfigFromFiles <dir> [-files "a,b"] [-listFile <file>] [-updateConfigDumpInfo]` | Load XML into main configuration | Partial load via `-listFile` (one absolute path per line, UTF-8 BOM); `-updateConfigDumpInfo` keeps the incremental-dump index in sync |
| `/UpdateDBCfg` | Apply main configuration to the database | Needs no active sessions; on a dev base this is instant |

## Log & report encodings

`/Out` logs and repository reports come as UTF-8, UTF-16 or CP1251 depending on
platform version and OS locale. The cores (`Read-TextSmart` / `read_text_smart`)
detect BOMs and fall back CP1251 ← UTF-8; never read these files raw.

## objects.xml

See references/script-contract.md#objectsxml-format. Subordinate objects (forms,
templates) are addressed by full name: `Catalog.Товары.Form.ФормаЭлемента`.
