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
from хранилище → dump to XML → lock objects → edit → partial load back → check → commit. All
heavy lifting is done by scripts driving `1cv8.exe DESIGNER` in batch mode.

## Picking the script variant

Two equivalent implementations exist — pick by the shell you are about to invoke:

- **Bash tool** → `scripts/sh/<name>.sh` with `--kebab-case` options
- **PowerShell tool** → `scripts/ps/<Name>.ps1` with `-PascalCase` parameters

Same behavior, same exit codes; the **last stdout line is a JSON result** (`ok`,
`error`, extras). Full contract: [references/script-contract.md](references/script-contract.md).
Run all scripts from the 1C project directory (or pass `--project-dir` / `-ProjectDir`).

Exit codes: `0` ok · `1` designer failed · `2` bad config/environment · `3` **lock
conflict** · `4` bad arguments · `5` **the check found errors**.

## Workflow 1 — Project setup (once per project)

When the user says a project is a 1C project and `1c-project.json` doesn't exist:

1. Interview the user for: platform version (optional), infobase server & name, infobase
   user/password, repository path (`tcp://…` or a UNC/local dir), repository
   user/password, XML dir (default `src`), temp XML dir (default `.1c-temp`).
   The XML dir must contain configuration files **only** — a full sync deletes anything
   the dump does not produce. If the project already has its dump at the repository
   root, move it into `src/` before setting up, or the first full sync will delete
   `README.md` and `1c-project.json` itself.
   Also ask which **check** runs after every load, before the commit (`checkMode`) —
   offer these and recommend keeping one on:
   - `always` — logical integrity + module syntax (server + thin client) on every task,
     whatever was edited.
   - `auto` (**recommended**) — checks what the task touched: integrity when an `.xml`
     was edited, module syntax when a module was edited, both in one designer run when
     both were.
   - `integrity` — only the integrity check on `.xml` edits; modules are never checked.
   - `modules` — only the module syntax check on module edits; metadata is never checked.
   - `none` — no check.

   In every mode only module errors in the modules edited in the task block the commit;
   module errors elsewhere are reported but do not.
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
   - The lock gates the **load**, not just the commit. `load-from-xml` on an object
     nobody holds fails within seconds: `Загрузка невозможна: объект метаданных <Имя>
     не захвачен в хранилище!`. Locking first is a precondition, not etiquette — never
     skip this step. If mapping fails (exit 4), lock by explicit names:
     `lock-objects --objects "Catalog.Товары"`.
3. **Edit** the XML/BSL files. Rules:
   - Preserve encoding: files are UTF-8 **with BOM** — do not strip it.
   - Never edit `ConfigDumpInfo.xml` by hand.
   - Files in the dump's top-level `Ext/` (`SessionModule.bsl`,
     `ManagedApplicationModule.bsl`, command interface, …) belong to the configuration
     itself: `lock-objects` on them takes the **root** `Configuration` lock.
   - A **new** object must be loaded together with its parent, because the parent is
     what enumerates its children: a new form, attribute or template needs the owner's
     `.xml` in the file list; a new *top-level* object needs `Configuration.xml`, and
     therefore the root `Configuration` object locked. Watch the trap that
     `CommonForms/` and `CommonTemplates/` are themselves top-level (see
     [references/file-to-object-map.md](references/file-to-object-map.md)) — a new
     common form takes the root lock, a new form on an existing catalog does not.
   - Partial load **creates new objects fine, including top-level ones** — nothing is
     refused. What differs is cost: a new *top-level* object changes
     `Configuration.xml`, and loading that file reconciles the whole object tree and
     rebuilds the dump index — a near-full reload. Measured 2026-08-05 on a
     ~28,000-file configuration: still running after 17 minutes, aborted by us rather
     than by an error; whether it completes cleanly is **unverified**.
   - So when a task needs a new **top-level** object, pause and let the user choose:
     - **Suggested**: the user creates the empty object in the Designer (seconds; the
       Designer takes the root lock interactively), then `sync-xml` picks it up and
       the rest of the task proceeds as normal cheap partial loads.
     - **Full-reload path**: stay automated — lock the root
       (`lock-objects --objects "Configuration"`), include `Configuration.xml` in the
       file list, and accept the near-full reload time.
4. **Finish the task**:
   a. `load-from-xml --files "<same file list>"` — partial load + DB update. A form
      module (`…/Ext/Form/Module.bsl`) is loaded through its `…/Ext/Form.xml`; the
      script makes that substitution itself, so pass the paths you edited.
   b. `check-config --files "<same file list>"` — only after the load returned `ok`.
      The project's `checkMode` says which checks are allowed, the file list says which
      are needed (`.xml` → integrity, module → syntax; `always` runs both regardless);
      pass the complete list of edited files in every mode and let the script decide.
      Read the result:
      - **Exit 5** — the check found errors. `errors` holds module errors as
        `{module(line,col)}: message` and integrity errors as `Объект: message`.
        Fix them, then repeat a–b. **Do not commit.**
      - `ok:true` with `otherErrors` — module errors outside the modules you edited.
        They do not block, but read them: removing or renaming an exported procedure
        breaks its *callers*, and that shows up here. If your change caused one, fix
        it; if it was there before, mention it to the user and go on.
      - `"mode":"unset"` — the project has not chosen yet. Ask the user once, with the
        options from Workflow 1 and `auto` recommended, write `checkMode` into
        `1c-project.json`, and run the check again.
      - `skipped:true` otherwise (`none`, or nothing among the files that the mode
        checks) — go on.
   c. `commit-to-repo --comment "<task summary>"` — commits everything locked in this
      task and releases the locks.
5. **Abort path**: if the user cancels the task — revert the file edits (git checkout)
   and `unlock-objects`.

Multiple `lock-objects` calls accumulate in `.1c-work/locked-objects.json`; `commit-to-repo`
commits the whole recorded set at once.

The check setting belongs to the project, not to the task: do not skip a configured check
to save time, and do not run one the project turned off. Change it only when the user
asks — edit `checkMode` in `1c-project.json`. For a one-off run in another mode (the user
asks for "a full check now") use `check-config --mode always --files "<files>"`; it leaves
the setting alone. The module check cannot be limited to some modules — the designer
always compiles the whole configuration, and the script narrows the report, not the work.

If `load-from-xml` fails with `При проверке метаданных обнаружены ошибки!`, that is the
same integrity check, run by `/UpdateDBCfg`: the metadata you loaded is inconsistent. The
specific finding is the line above it in `logFile`. Fix the `.xml` and load again.

## Hard rules

- **Never edit before locking.** Lock conflict (exit 3) = stop and report.
- **Never commit to the repository without loading the XML into the configuration
  first** — the repository takes the configuration state, not the files.
- **Never commit past a failed check** (`check-config` exit 5). Fix and re-check, or stop
  and report.
- Designer operations can take minutes on big configurations — use generous tool
  timeouts (10 min) for `update-from-repo`, full `sync-xml` and `check-config`.
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
