# Architecture

## What this is

`1c-dev` is a user-level Claude Code skill that automates the 1C configuration-repository
round-trip for **server infobases**. Claude reads `SKILL.md`, picks the script variant
matching its current shell, and drives the whole cycle: update from the repository →
XML sync → lock → edit → partial load → commit.

```
Claude Code session
   │  (SKILL.md workflows)
   ▼
scripts/ps/*.ps1  ◄─contract─►  scripts/sh/*.sh          (identical behavior)
   │
   ▼
1cv8.exe DESIGNER /S server\base ... /Out log            (batch mode)
   │
   ├── dev infobase (server, no data, one per developer)
   └── configuration repository (хранилище) — tcp:// or file share
```

The skill ships two ways from the same repo: as a Claude Code **plugin**
(`.claude-plugin/marketplace.json` + `.claude-plugin/plugin.json` at the repo root,
skill auto-discovered from `skills/1c-dev/`) and as a **manual user-level skill**
(`install.ps1` / `install.sh` copy `skills/1c-dev/` to `~/.claude/skills/1c-dev`).

## Per-project files (in each 1C project, all gitignored)

| File | Owner | Purpose |
|---|---|---|
| `1c-project.json` | setup interview | connection settings, creds, dirs (schema: skills/1c-dev/references/script-contract.md) |
| `.1c-state.json` | scripts | `lastRepoVersion` + `lastSync` — the change-detection anchor |
| `<xmlDir>/` | designer dumps | configuration source of truth for editing (usually `src/`, committed to git) |
| `<tempXmlDir>/` | sync-xml fallback | scratch area for full dumps, safe to delete |
| `.1c-work/` | scripts | designer logs, repo reports, `objects.xml`, `locked-objects.json` |

## The scripts

Each exists twice (`skills/1c-dev/scripts/ps/`, `skills/1c-dev/scripts/sh/`) with one CLI contract
(skills/1c-dev/references/script-contract.md). Cores (`Common.ps1` / `common.sh`) provide: config and
state I/O, `1cv8.exe` resolution (configured version or newest installed), a designer
runner (always `/DisableStartupDialogs /DisableStartupMessages /Out`, checks exit code
**and** scans the log), and encoding-tolerant readers (UTF-16/UTF-8/CP1251).

| Script | Designer calls | State |
|---|---|---|
| test-connection | `ConfigurationRepositoryReport -NBegin 1 -NEnd 1` | — |
| get-repo-changes | `ConfigurationRepositoryReport -NBegin last+1` | read-only |
| update-from-repo | report → `ConfigurationRepositoryUpdateCfg -force` → `UpdateDBCfg` → sync-xml | writes version |
| sync-xml | `DumpConfigToFiles` (`-update -force` / full to temp + diff) | — |
| lock-objects | `ConfigurationRepositoryLock -Objects` | appends locked list |
| load-from-xml | `LoadConfigFromFiles -listFile -updateConfigDumpInfo` → `UpdateDBCfg` | — |
| commit-to-repo | `ConfigurationRepositoryCommit` → report | writes version, clears locked list |
| unlock-objects | `ConfigurationRepositoryUnlock -force` | clears/reduces locked list |

## Key mechanisms

**Change detection.** The repository has monotonically increasing version numbers.
`.1c-state.json` stores the last version this project consumed; a bounded
`ConfigurationRepositoryReport -NBegin last+1` returns exactly the newer versions —
non-empty means "update needed". This lets Claude auto-check before every task.

The report itself is an MXL spreadsheet even when written to a `.txt` path, and the
version cell carries the designer's *locale* number formatting — `{"#","2,555"}`, not
`2555`. The parsers therefore accept grouped digits and strip the separators; a naive
integer test caps detection at 999 and poisons `.1c-state.json` silently.

**Hybrid XML sync.** Default is the designer's incremental dump (`-update -force`),
which itself touches only changed files (driven by `ConfigDumpInfo.xml`). When that
index is missing or the incremental dump fails, a full dump goes to `tempXmlDir` and a
byte-diff mirrors it into `xmlDir` (copy changed/new, delete vanished, prune empty
dirs) — so git history never sees rewrites of unchanged files. An empty `xmlDir` gets a
direct full dump (`initial`).

Because the full path deletes whatever the dump does not contain, **`xmlDir` must hold
configuration files and nothing else**. Point it at a subdirectory (`src`), never at the
repository root — at the root a full sync takes `README.md`, `.gitattributes` and
`1c-project.json` with it. (`.git` survives only because it is hidden.)

**Lock accounting.** `lock-objects` maps file paths to repository objects
(`Mapping.ps1` / `mapping.sh`; forms and templates are separately lockable) and locks
them; each successful lock is appended to `.1c-work/locked-objects.json`. `commit-to-repo`
commits exactly that recorded set and clears it; `unlock-objects` is the abort path.
A lock conflict is a dedicated exit code (3) so Claude reliably stops before editing.

**Error handling.** Every designer call writes a `/Out` log into `.1c-work/`. Failure =
non-zero exit code OR error-marker lines in the log (the designer is known to exit 0 on
some failures). Script results are single-line JSON on the last stdout line; progress
goes to stderr.

## Design constraints

- Server infobases only; the dev base is assumed data-free, so `UpdateDBCfg` always runs.
- Requires platform 8.3.11+ (`ConfigurationRepositoryLock`/`Unlock`).
- Out of scope in v1: configuration extensions, EDT, file infobases, multi-repository
  setups, granular external-data-source parts.
