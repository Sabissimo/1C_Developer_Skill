# install.ps1 — install the 1c-dev skill to the user level (~/.claude/skills/1c-dev).
# Run from the repo root:  powershell -NoProfile -File install.ps1
$ErrorActionPreference = 'Stop'

$sourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$targetDir = Join-Path $HOME '.claude\skills\1c-dev'

if (Test-Path -LiteralPath $targetDir) {
    Remove-Item -LiteralPath $targetDir -Recurse -Force
}
New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $sourceDir 'SKILL.md') -Destination $targetDir
Copy-Item -LiteralPath (Join-Path $sourceDir 'scripts') -Destination $targetDir -Recurse
Copy-Item -LiteralPath (Join-Path $sourceDir 'references') -Destination $targetDir -Recurse

Write-Host "1c-dev skill installed to $targetDir"
Write-Host 'Restart Claude Code sessions to pick it up.'
