#!/usr/bin/env bash
# install.sh — install the 1c-dev skill to the user level (~/.claude/skills/1c-dev).
# Run from the repo root:  bash install.sh
set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target_dir="$HOME/.claude/skills/1c-dev"

rm -rf "$target_dir"
mkdir -p "$target_dir"

cp "$source_dir/SKILL.md" "$target_dir/"
cp -r "$source_dir/scripts" "$target_dir/scripts"
cp -r "$source_dir/references" "$target_dir/references"

echo "1c-dev skill installed to $target_dir"
echo "Restart Claude Code sessions to pick it up."
