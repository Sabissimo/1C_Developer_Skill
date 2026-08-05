---
name: 1c-dev
description: >-
  1C:Enterprise development workflow automation. Use when a project involves 1C
  configuration development: editing configuration XML/BSL sources, syncing with a
  1C configuration repository (хранилище конфигурации), updating an infobase from the
  repository, locking/committing objects, or loading XML changes back into the
  configuration. Triggers: "1C", "1С", "конфигурация", "хранилище", "конфигуратор",
  "BSL", "1cv8".
---

# 1C Developer Skill

Automates the 1C configuration-repository round-trip for **server infobases**: update
from хранилище → dump to XML → lock objects → edit → partial load back → commit. All
heavy lifting is done by scripts driving `1cv8.exe DESIGNER` in batch mode.

## Picking the script variant

Two equivalent implementations exist — pick by the shell you are about to invoke:

- **Bash tool** → `scripts/sh/<name>.sh` with `--kebab-case` options
- **PowerShell tool** → `scripts/ps/<Name>.ps1` with `-PascalCase` parameters

Same behavior, same exit codes; the **last stdout line is a JSON result** (`ok`,
`error`, extras). Full contract: [references/script-contract.md](references/script-contract.md).
Run all scripts from the 1C project directory (or pass `--project-dir` / `-ProjectDir`).

Exit codes: `0` ok · `1` designer failed · `2` bad config/environment · `3` **lock
conflict** · `4` bad arguments.

## Workflow 1 — Project setup (once per project)

When the user says a project is a 1C project and `1c-project.json` doesn't exist:

1. Interview the user for: platform version (optional), infobase server & name, infobase
   user/password, repository path (`tcp://…` or a UNC/local dir), repository
   user/password, XML dir (default `src`), temp XML dir (default `.1c-temp`).
   The XML dir must contain configuration files **only** — a full sync deletes anything
   the dump does not produce. If the project already has its dump at the repository
   root, move it into `src/` before setting up, or the first full sync will delete
   `README.md` and `1c-project.json` itself.
2. Write `1c-project.json` (schema in script-contract.md) into the project root.
3. Ensure `.gitignore` covers: `1c-project.json`, `.1c-state.json`, `.1c-temp/`, `.1c-work/`.
4. Run `test-connection` — stop and report if it fails.
5. Run `sync-xml` (initial full dump into the XML dir).
6. Run `get-repo-changes --full` and record the reported `latestVersion` by running
   `update-from-repo` **only if** the infobase might be behind — otherwise simply tell
   the user setup is done. (State gets its version on the first `update-from-repo` or
   `commit-to-repo`.)

## Workflow 2 — Update from repository

Run when the user asks to update, **and check automatically before starting any new
task**:

1. `get-repo-changes` → if `hasChanges` is `false`, say so and skip the rest.
2. `update-from-repo` — updates the configuration from the repository, updates the DB
   configuration, re-syncs the XML dir (only really-changed files are touched), and
   records the new repository version.
3. Report the new version and what changed (`git status` / `git diff --stat` of the XML
   dir shows it precisely if the project is under git).

## Workflow 3 — Task editing cycle

For every task that changes configuration files:

1. **Identify** the files you will edit (paths relative to the XML dir).
2. **Lock first**: `lock-objects --files "Catalogs/Товары/Ext/ObjectModule.bsl,…"`.
   - Exit 3 = someone else holds the lock. **STOP immediately**, show the `conflict`
     lines to the user, do not edit anything.
   - Editing a file whose object is not locked will make the later commit fail — never
     skip this step. If mapping fails (exit 4), lock by explicit names:
     `lock-objects --objects "Catalog.Товары"`.
3. **Edit** the XML/BSL files. Rules:
   - Preserve encoding: files are UTF-8 **with BOM** — do not strip it.
   - Never edit `ConfigDumpInfo.xml` by hand.
   - New objects (a file that doesn't exist yet) cannot be partially loaded reliably —
     for new top-level objects prefer creating them via the Designer, then re-sync.
4. **Finish the task**:
   a. `load-from-xml --files "<same file list>"` — partial load + DB update.
   b. `commit-to-repo --comment "<task summary>"` — commits everything locked in this
      task and releases the locks.
5. **Abort path**: if the user cancels the task — revert the file edits (git checkout)
   and `unlock-objects`.

Multiple `lock-objects` calls accumulate in `.1c-work/locked-objects.json`; `commit-to-repo`
commits the whole recorded set at once.

## Hard rules

- **Never edit before locking.** Lock conflict (exit 3) = stop and report.
- **Never commit to the repository without loading the XML into the configuration
  first** — the repository takes the configuration state, not the files.
- Designer operations can take minutes on big configurations — use generous tool
  timeouts (10 min) for `update-from-repo` and full `sync-xml`.
- If any script returns `ok:false`, read its `logFile` for the full designer log before
  deciding what to do next.
- Requirements: Windows, 1C platform **8.3.11+** (for `/ConfigurationRepositoryLock`/
  `Unlock`), a dedicated dev infobase bound to the repository under a dedicated
  repository user (not shared with humans).

## References

- [references/script-contract.md](references/script-contract.md) — args, exit codes, JSON results
- [references/designer-cli.md](references/designer-cli.md) — the underlying designer batch commands
- [references/file-to-object-map.md](references/file-to-object-map.md) — path → object mapping rules
- [references/troubleshooting.md](references/troubleshooting.md) — common failures and fixes
