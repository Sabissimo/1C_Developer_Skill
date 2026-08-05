# Project: 1C Developer Skill

This repository IS a Claude Code skill (`1c-dev`) that automates the 1C:Enterprise
configuration-repository round-trip: update from хранилище → dump to XML → lock objects →
edit XML/BSL → partial load back → commit. It targets **server infobases only** and drives
the 1C Designer in batch mode (`1cv8.exe DESIGNER /...`).

The skill itself lives in `skills/1c-dev/` (SKILL.md + scripts + references); the repo
root additionally carries the Claude Code plugin-marketplace manifests
(`.claude-plugin/marketplace.json`, `.claude-plugin/plugin.json`), installers and docs.

# Tech Stack

- **PowerShell 5.1-compatible scripts** in `skills/1c-dev/scripts/ps/` (must also run on pwsh 7).
- **Git Bash (POSIX sh/bash) scripts** in `skills/1c-dev/scripts/sh/` — a 1:1 mirror of `scripts/ps/`.
- No other runtimes. `jq`/`python` may be used in bash scripts only behind availability
  checks with fallbacks (final fallback: `powershell.exe -Command`).

# Cross-Shell Parity — THE core rule

- Every operation exists in BOTH `scripts/ps/*.ps1` and `scripts/sh/*.sh` (under `skills/1c-dev/`).
- Both variants follow the contract in `skills/1c-dev/references/script-contract.md`: same
  behavior, same exit codes, same final-line JSON on stdout, human progress on stderr.
- Any behavior change MUST be applied to both variants and to `script-contract.md` in the
  same commit. Never let the variants drift.

# Code Quality

- Always handle errors explicitly — never ignore or silently swallow them.
- No magic strings or numbers — use named constants/variables at the top of scripts.
- Keep functions small and single-purpose.
- Designer calls: always `/DisableStartupDialogs /DisableStartupMessages /Out <log>`;
  check the exit code AND scan the log — the designer sometimes exits 0 on failure.
- All text output files the designer consumes (objects.xml, list files) are UTF-8 with BOM.
- All `.ps1` files must be saved as UTF-8 **with BOM** — they contain Cyrillic patterns
  and Windows PowerShell 5.1 misreads BOM-less UTF-8 as ANSI. `.sh` files must stay
  BOM-less LF.
- Logs/reports from the designer may be UTF-8, UTF-16 or CP1251 — always read through the
  encoding-detection helpers in `Common.ps1` / `common.sh`.

# Testing

- Parity tests live in `skills/1c-dev/scripts/tests/` — the same case table runs against
  both variants and diffs their outputs. Run them after any script change:
  `pwsh -NoProfile skills/1c-dev/scripts/tests/run-tests.ps1` and
  `bash skills/1c-dev/scripts/tests/run-tests.sh`.
- Anything touching a real infobase/repository cannot run in CI — mark it clearly and
  verify via the live smoke-test checklist in `skills/1c-dev/references/troubleshooting.md`.

# Docs

- `docs/architecture.md` describes the end-to-end flow — update it whenever a workflow or
  script contract changes, in the same session.
- `SKILL.md` is the skill entry point; keep its workflow steps in sync with the scripts.

# Rules

- Think first, read relevant files before answering. Never speculate about code you haven't opened.
- If a file is referenced, read it before responding.
- Give a high-level explanation of changes at every step.
- Commit locally whenever a phase of work is complete. Never push unless asked in that turn.

# Kanban Board — MANDATORY EVERY SESSION

GitHub Project: https://github.com/users/Sabissimo/projects/9 (linked to this repo).

## Session start protocol — BEFORE ANY CODE, EVERY TIME:

1. Read the board state (`gh project item-list 9 --owner Sabissimo`, `gh issue list`).
2. Review what's Done and what's in Todo.
3. Update the board: new issues for newly discovered work, break down upcoming tasks,
   close stale issues.
4. Move the next batch from Backlog to Todo.
5. Tell the user what's done, what's next, and what you updated.
6. Only then start coding.

## While coding:

- Move issues to In Progress when starting, Done (and close them) immediately when finished.
- New work requested by the user mid-session → create issues on the board BEFORE coding
  (1–2 levels for small fixes, 3 levels for features).
- After every sub-agent completes, update the board before doing anything else.
- Never leave the board stale.
