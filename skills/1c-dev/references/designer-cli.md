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
| `/CheckModules -ThinClient -Server` | Syntax check of every module | **Without a mode flag it checks nothing and still reports success.** Exit 101 = errors found |
| `/CheckConfig -ConfigLogIntegrity -IncorrectReferences -ThinClient -Server` | Full configuration check | Superset of the module check. Exit 101 = errors found |

## Check output (`/CheckModules`, `/CheckConfig`)

Verified on 8.3.19.1351. Neither command can be limited to chosen modules — both scan the
whole configuration; `check-config` narrows the *report*, not the work.

```
Соединение с хранилищем конфигурации не установлено
{Документ.Инвентаризация.МодульОбъекта(3,11)}: Переменная не определена (ИмяПеременной)
	Сообщить(<<?>>ИмяПеременной); (Проверка: Сервер)
{Документ.Инвентаризация.Форма.ФормаДокумента.Форма(9,1)}: Ожидается ключевое слово 'КонецЕсли' ('EndIf')
<<?>>КонецПроцедуры (Проверка: Тонкий клиент)
```

- Exit code **101** = the check ran and found errors; `0` = clean; `1` = the designer
  could not start the check (e.g. `Информационная база не обнаружена!`).
- A finding is one `{<module id>(<line>,<col>)}: <message>` line followed by the source
  line with `<<?>>` at the error position. The same finding is printed once per checked
  mode.
- The **module id follows the configuration's script variant, not the UI language**: a
  Russian-variant configuration prints `Документ.….МодульОбъекта` even under `/Len`; only
  the message text is translated.
- Clean results read `Синтаксических ошибок не обнаружено!` / `Ошибок не обнаружено`
  (`No syntax errors found!` / `No errors found`). All four trip
  `DESIGNER_ERROR_PATTERN`, so check logs have their own parser.
- The first line is printed for any repository-bound base opened without repository
  credentials. It is a notice, not an error.

## Log & report encodings

`/Out` logs and repository reports come as UTF-8, UTF-16 or CP1251 depending on
platform version and OS locale. The cores (`Read-TextSmart` / `read_text_smart`)
detect BOMs and fall back CP1251 ← UTF-8; never read these files raw.

## objects.xml

See references/script-contract.md#objectsxml-format. Subordinate objects (forms,
templates) are addressed by full name: `Catalog.Товары.Form.ФормаЭлемента`.
