# 1c-dev — Claude Code skill for 1C:Enterprise development

Automates the painful part of AI-assisted 1C development: the round-trip between the
**configuration repository (хранилище конфигурации)**, a **dev infobase**, and the
**XML dump** that Claude actually edits.

With this skill installed, you tell Claude "this project is 1C", answer a short setup
interview once, and then just give it tasks. Claude will, on its own:

- check the repository for new versions and pull them (`ConfigurationRepositoryUpdateCfg`),
- keep an XML dump in sync without touching unchanged files (incremental dump with a
  full-dump diff fallback),
- **lock the objects it is about to edit** — and hard-stop if someone else holds them,
- edit the XML/BSL sources,
- load exactly the changed files back (`LoadConfigFromFiles -listFile`), update the DB
  configuration, and **commit to the repository** with a task comment.

## Requirements

- Windows, 1C:Enterprise platform **8.3.11+** installed under `Program Files\1cv8`
- A **server** infobase dedicated to development (no data, no other users), bound to
  the configuration repository under a **dedicated repository user**
- Claude Code (the scripts run in PowerShell 5.1/7 **or** Git Bash — both variants ship
  and behave identically)

## Install

**Option A — as a Claude Code plugin (recommended):**

```
/plugin marketplace add Sabissimo/1C_Developer_Skill
/plugin install 1c-dev@1c-developer-skill
```

Updates later: `/plugin marketplace update 1c-developer-skill`.

**Option B — manual, as a user-level skill:**

```powershell
git clone https://github.com/Sabissimo/1C_Developer_Skill.git
cd 1C_Developer_Skill
powershell -NoProfile -File install.ps1   # or: bash install.sh
```

This copies `skills/1c-dev` to `~/.claude/skills/1c-dev` (use one option, not both, or
Claude will see the skill twice). Either way, restart your Claude Code session, open
your 1C project directory, and say something like: *"Это 1С-проект, настрой его"*.

## What gets created in your project

| File | Purpose | Git |
|---|---|---|
| `1c-project.json` | connection settings **incl. passwords** | ignored — never commit |
| `.1c-state.json` | last synced repository version | ignored |
| `src/` (configurable) | the XML dump Claude edits | commit it |
| `.1c-temp/`, `.1c-work/` | scratch: full dumps, logs, reports | ignored |

## How it works

Scripts in `skills/1c-dev/scripts/ps` (PowerShell) and `skills/1c-dev/scripts/sh`
(Git Bash) — same CLI contract, same exit codes, last stdout line is a JSON result.
They drive `1cv8.exe DESIGNER` in batch mode with full log checking (the designer is
known to exit 0 on some failures).
Details: [docs/architecture.md](docs/architecture.md) ·
[script-contract.md](skills/1c-dev/references/script-contract.md) ·
[designer-cli.md](skills/1c-dev/references/designer-cli.md).

Change detection is version-based: the skill remembers the last consumed repository
version and asks the designer for a report from `N+1` — a non-empty report means
"update before you start".

## Testing

```bash
bash skills/1c-dev/scripts/tests/run-tests.sh        # bash variant + parity with PowerShell
pwsh -NoProfile skills/1c-dev/scripts/tests/run-tests.ps1
```

Anything touching a real infobase can't run in CI — see the live smoke-test checklist
in [troubleshooting.md](skills/1c-dev/references/troubleshooting.md): the full cycle
(including the lock-conflict path) has been verified live on 8.3.19.1351, and its
"first live run" section lists what to re-verify on a different platform build.

## Limitations (v1)

File infobases, configuration extensions, EDT projects and multi-repository setups are
out of scope. Passwords are stored in plain text in `1c-project.json` — keep it out of
git (the skill adds it to `.gitignore` automatically).

## License

MIT
