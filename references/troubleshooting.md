# Troubleshooting

## First live run — verify these once per environment

The scripts follow documented designer behavior, but 1C platform builds differ. On the
first real project, verify:

1. **objects.xml is accepted** by `/ConfigurationRepositoryLock` on your platform build.
   If the designer complains about the format or about subordinate names
   (`Catalog.X.Form.Y`), try locking the parent (`--objects "Catalog.X"`) — and if that
   is what your platform needs, report it so the mapping can switch to
   `includeChildObjects="true"` on parents.
2. **`-listFile` for `/LoadConfigFromFiles`** works (8.3.10+). If not, fall back to
   `-files "p1,p2"` with comma-separated absolute paths.
3. **Report parsing** finds versions: check `.1c-work/repo-report.txt` contains
   `Версия: N` (or `Version: N`) lines. A differently-localized platform needs the
   regex in `Get-RepoVersionsFromReport` / `repo_versions_from_report` extended.

## Common failures

| Symptom | Cause | Fix |
|---|---|---|
| exit 2, "Config not found" | script not run from the project dir | pass `--project-dir` / `-ProjectDir` |
| exit 2, "No 1C platform installation found" | platform in a non-standard dir | put the full path logic in config: set `platformVersion` to an installed version, or install under `Program Files\1cv8` |
| exit 3 on lock | object captured by another repository user | wait/ask that user to release; **do not edit** |
| exit 1 on `update-from-repo`, log mentions "монопольн"/"exclusive" | sessions are open on the dev base | close Designer/Enterprise sessions on the dev base |
| exit 1 on `commit`, log mentions "не захвачен"/"not locked" | commit set ≠ locked set (state lost) | re-run `lock-objects`, or commit from the Designer once |
| exit 1 on `UpdateDBCfg` | structure change needs exclusive access | ensure nobody (including you) has the base open |
| incremental sync silently falls back to full every time | `ConfigDumpInfo.xml` deleted/broken in xmlDir | let one full sync finish; never hand-edit that file |
| Cyrillic garbage in logs shown by scripts | non-standard OS code page | logs are decoded UTF-16/UTF-8/CP1251 automatically; other encodings need `Read-TextSmart`/`read_text_smart` extended |
| designer window pops up and hangs | a dialog the batch switches can't suppress (e.g. base not bound to the repository) | bind the base to the repository manually once; check creds |
| `1c-project.json` parse error in Git Bash | no jq/python and PowerShell missing from PATH | install jq (`pacman -S jq` in Git for Windows SDK) or ensure `powershell.exe` is reachable |

## Live smoke-test checklist (per new environment)

1. `test-connection` → ok.
2. `sync-xml` on an empty XML dir → mode `initial`, files appear.
3. `get-repo-changes --full` → `latestVersion` > 0.
4. `lock-objects --files "<one module>"` → ok; verify the lock is visible in the
   Designer's repository window.
5. Lock the same object as another repository user from the Designer → `lock-objects`
   again → exit 3.
6. Edit a comment in the module, `load-from-xml --files ...` → ok; the change is visible
   in the Designer.
7. `commit-to-repo --comment "smoke test"` → ok; new version in the repository history;
   lock released.
8. `update-from-repo` from a second machine/base → the comment arrives.
9. `unlock-objects` after a fresh lock → lock disappears in the Designer.
