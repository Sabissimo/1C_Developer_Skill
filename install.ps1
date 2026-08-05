# install.ps1 — install the 1c-dev skill to the user level (~/.claude/skills/1c-dev).
# Run from the repo root:  powershell -NoProfile -File install.ps1
$ErrorActionPreference = 'Stop'

$sourceDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'skills\1c-dev'
$targetDir = Join-Path $HOME '.claude\skills\1c-dev'

if (Test-Path -LiteralPath $targetDir) {
    Remove-Item -LiteralPath $targetDir -Recurse -Force
}
New-Item -ItemType Directory -Path (Split-Path -Parent $targetDir) -Force | Out-Null
Copy-Item -LiteralPath $sourceDir -Destination $targetDir -Recurse

Write-Host "1c-dev skill installed to $targetDir"
Write-Host 'Restart Claude Code sessions to pick it up.'
