# Troubleshooting

## Verified live (8.3.19.1351, Windows 11, tcp:// repository)

The full cycle — test-connection, initial dump, update-from-repo, lock, partial load
via `-listFile`, commit with comment, unlock, version detection — passed end-to-end.
In particular: objects.xml version 1.0 is accepted by Lock/Commit/Unlock, and
`/ConfigurationRepositoryReport` writes **MXL (MOXCEL) data even into a `.txt` file** —
the report parsers handle both MXL cell pairs and plain text. Re-locking an object the
same repository user already holds succeeds silently (idempotent). The conflict path is
verified live too: locking an object held by **another** repository user exits 3 in both
variants with the designer's conflict line ("Объект захвачен для редактирования другим
пользователем: …") in the `conflict` field, and the locked-objects list stays untouched.

Verified again on **8.3.14.1779** (Windows 11, `tcp://` repository, ~2 500 versions,
28 000-file configuration): test-connection, get-repo-changes, update-from-repo and the
incremental dump all pass. That run is what surfaced the two 1.0.1 fixes below —
thousands-separated version numbers and error words inside metadata names — neither of
which appears on a repository with fewer than 1 000 versions.

The post-load check was verified live on 8.3.19.1351 in both variants, with a real
integrity error (a recorder-subordinate register left without a recorder) and module
errors (object, manager and form modules) loaded on purpose under a lock:

- `auto` runs integrity alone for an `.xml`, modules alone for a module, and the single
  combined `/CheckConfig -ConfigLogIntegrity -Server -ThinClient` for both — whose log
  carries the integrity finding and the module findings together; `always` makes that
  combined run for any file list;
- `integrity` never runs the module check (and does not trip over an unmappable `.bsl`),
  `modules` never runs the integrity check;
- module findings in the edited modules are exit 5, findings in other modules land in
  `otherErrors` and do not block; a clean base passes; a base that cannot be opened is
  exit 1, not 5.

Timing was measured only on that small configuration (6–7 s per run, the combined run
included); how long any of the three takes on a large one is **unverified**.

## First live run on a different platform build — verify once

1. **objects.xml is accepted** by `/ConfigurationRepositoryLock`. If the designer
   complains about the format or about subordinate names (`Catalog.X.Form.Y`), try
   locking the parent (`--objects "Catalog.X"`) — and if that is what your platform
   needs, report it so the mapping can switch to `includeChildObjects="true"`.
2. **`-listFile` for `/LoadConfigFromFiles`** works (8.3.10+). If not, fall back to
   `-files "p1,p2"` with comma-separated absolute paths.
3. **Report parsing** finds versions (see the MXL note above): run
   `get-repo-changes --full` and check that `latestVersion` matches the newest version
   in the Designer's repository history — not merely that it is > 0. A differently-
   localized platform needs the label list in `Get-RepoVersionsFromReport` /
   `repo_versions_from_report` extended ("Версия:", "Version:"), and possibly the
   thousands-separator character class alongside `, . ' ` and NBSP.
4. **Check-log parsing** (`check-config`): break a module on purpose and confirm the
   finding lands in `errors`, not `otherErrors`. A platform whose clean message differs
   from the four in `CHECK_CLEAN_PATTERN` shows up as exit 1 on a clean base; a module
   kind whose id differs from references/file-to-object-map.md shows up as the finding
   sitting in `otherErrors`. Integrity findings are recognised by having **no**
   `{module(line,col)}` prefix, so they need no per-platform table.

## Common failures

| Symptom | Cause | Fix |
|---|---|---|
| exit 2, "Config not found" | script not run from the project dir | pass `--project-dir` / `-ProjectDir` |
| exit 2, "No 1C platform installation found" | platform in a non-standard dir | put the full path logic in config: set `platformVersion` to an installed version, or install under `Program Files\1cv8` |
| exit 3 on lock | object captured by another repository user | wait/ask that user to release; **do not edit** |
| exit 1 on `update-from-repo`, log mentions "монопольн"/"exclusive" | sessions are open on the dev base | close Designer/Enterprise sessions on the dev base |
| exit 1 on `load-from-xml` within seconds, log mentions "не захвачен"/"not locked" | the object is not locked — the хранилище refuses the **load**, not just the commit. With `Configuration.xml` in the file list the object named is `Configuration` | `lock-objects` for the object the log names (`--objects "Configuration"` for the root), then retry the load |
| exit 1 on `load-from-xml`, log says `Неизвестный объект метаданных <Class>.<Obj>.Form.<Имя>.Ext` | a form's `Ext/Form/Module.bsl` was listed on its own — the designer loads a form module only together with the form | fixed in 1.0.4: the script lists the form's `Ext/Form.xml` instead; on an older copy pass `…/Ext/Form.xml` yourself |
| exit 1 on `load-from-xml`, `log` is `При проверке метаданных обнаружены ошибки!` (designer exit 101) | the loaded metadata fails the logical-integrity check that `/UpdateDBCfg` runs — the files **were** loaded into the main configuration, the database update was refused | the specific finding is the line above it in `logFile` (it carries no error marker, so `log` omits it); fix the `.xml` and load again |
| exit 5 on `check-config` | the check found errors — `errors` lists module errors as `{module(line,col)}: message`, integrity errors as `Объект: message` | fix them, `load-from-xml` again, re-check; do not commit |
| `check-config` passes but `otherErrors` is non-empty | errors in modules the task did not edit — pre-existing, or callers broken by the edit | read them; fix the ones the change caused |
| `check-config` returns `"skipped":true` although a check is configured | nothing among the files that the mode checks: no `.xml` for `integrity`, no module for `modules`, neither for `auto` (`always` never skips) | expected; pass the complete list of edited files so the script can tell |
| `check-config` returns `"mode":"unset","skipped":true` | `1c-project.json` has no `checkMode` (project set up before 1.1.0) | choose `always`, `auto`, `integrity`, `modules` or `none` and add the key |
| exit 2, "checkMode must be one of …" on **any** script | typo in `checkMode` | use `always`, `auto`, `integrity`, `modules` or `none`, or remove the key |
| exit 4 on `check-config`, "Cannot map module file to a module id" | a `.bsl` file of a kind the module-id table has no row for | `--mode integrity` for this run (it does not map modules), and file an issue with the path |
| exit 1 on `check-config` on a base that is actually clean | the platform words its "no errors" line differently | extend `CHECK_CLEAN_PATTERN` in `Checking.ps1` / `checking.sh` with the line from `logFile` |
| a module error you expect is missing from the check | `check-config` was run while `load-from-xml` was failing at `/UpdateDBCfg` — errors in a newly added module file were seen to appear only after the database update went through | get the load to `ok` first, then check |
| the check takes too long on a large configuration | each designer check scans the whole configuration; the script narrows the report, not the work | pick a cheaper mode for the project (`auto` instead of `always`; `integrity` or `modules`; `none`); run `check-config --mode always --files …` by hand when wanted |
| exit 1 on `commit`, log mentions "не захвачен"/"not locked" | commit set ≠ locked set (state lost) | re-run `lock-objects`, or commit from the Designer once |
| exit 1 on `UpdateDBCfg` | structure change needs exclusive access | ensure nobody (including you) has the base open |
| `latestVersion` stops at a suspiciously round **999** and every later `get-repo-changes` reports hundreds of "new" versions | the designer formats the version cell with the locale thousands separator (`{"#","2,555"}`); pre-1.0.1 parsers validated with `^\d+$` and dropped anything ≥ 1000 | fixed in 1.0.1; on an older copy, delete `.1c-state.json` after upgrading so the bad `lastRepoVersion` is re-learned |
| exit 1 on `update-from-repo` although the designer exited **0**, and the reported log lines are all `Новый объект: …` | a metadata name contains an error word — `РегистрСведений.ОшибкиЗакрытияМесяца` matches `ошибк` | fixed in 1.0.1: dotted 1C identifiers are blanked before the error pattern is applied |
| incremental sync silently falls back to full every time | `ConfigDumpInfo.xml` deleted/broken in xmlDir | let one full sync finish; never hand-edit that file |
| Cyrillic garbage in logs shown by scripts | non-standard OS code page | logs are decoded UTF-16/UTF-8/CP1251 automatically; other encodings need `Read-TextSmart`/`read_text_smart` extended |
| designer window pops up and hangs | a dialog the batch switches can't suppress (e.g. base not bound to the repository) | bind the base to the repository manually once; check creds |
| exit 1 instantly, no `/Out` log, when calling `1cv8.exe` **manually** from Git Bash | MSYS rewrites `/S`, `/Out` etc. into filesystem paths | prefix the call with `MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'` (the skill's `run_designer` already does) |
| `1c-project.json` parse error in Git Bash | no jq/python and PowerShell missing from PATH | install jq (`pacman -S jq` in Git for Windows SDK) or ensure `powershell.exe` is reachable |

## Live smoke-test checklist (per new environment)

1. `test-connection` → ok.
2. `sync-xml` on an empty XML dir → mode `initial`, files appear.
3. `get-repo-changes --full` → `latestVersion` > 0.
4. `lock-objects --files "<one module>"` → ok; verify the lock is visible in the
   Designer's repository window.
5. Lock the same object as another repository user from the Designer → `lock-objects`
   again → exit 3.
6. `load-from-xml --files "<a file whose object is NOT locked>"` → exit 1 within seconds,
   log contains "не захвачен". Confirms the хранилище gates the load, not just the
   commit. Safe: nothing is locked, nothing is committed, nothing changes.
7. Edit a comment in the module, `load-from-xml --files ...` → ok; the change is visible
   in the Designer.
8. `check-config --mode auto --files "<the module>"` → ok, `checks` is `["modules"]`,
   `errorCount` 0. Then put a call to a procedure that does not exist into the module,
   `load-from-xml`, check again → exit 5 with that line in `errors`. Remove it, load,
   check → ok. With the object's `.xml` added to `--files`, `checks` becomes
   `["integrity","modules"]`.
9. `commit-to-repo --comment "smoke test"` → ok; new version in the repository history;
   lock released.
10. `update-from-repo` from a second machine/base → the comment arrives.
11. `unlock-objects` after a fresh lock → lock disappears in the Designer.
