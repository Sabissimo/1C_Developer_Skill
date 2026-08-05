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

## Common failures

| Symptom | Cause | Fix |
|---|---|---|
| exit 2, "Config not found" | script not run from the project dir | pass `--project-dir` / `-ProjectDir` |
| exit 2, "No 1C platform installation found" | platform in a non-standard dir | put the full path logic in config: set `platformVersion` to an installed version, or install under `Program Files\1cv8` |
| exit 3 on lock | object captured by another repository user | wait/ask that user to release; **do not edit** |
| exit 1 on `update-from-repo`, log mentions "монопольн"/"exclusive" | sessions are open on the dev base | close Designer/Enterprise sessions on the dev base |
| exit 1 on `load-from-xml` within seconds, log mentions "не захвачен"/"not locked" | the object is not locked — the хранилище refuses the **load**, not just the commit. With `Configuration.xml` in the file list the object named is `Configuration` | `lock-objects` for the object the log names (`--objects "Configuration"` for the root), then retry the load |
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
8. `commit-to-repo --comment "smoke test"` → ok; new version in the repository history;
   lock released.
9. `update-from-repo` from a second machine/base → the comment arrives.
10. `unlock-objects` after a fresh lock → lock disappears in the Designer.
