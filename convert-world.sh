#!/usr/bin/env bash
# Converts a GSPack world to the 0.5 material unification (one item per metal, AllTheOres ores).
# Usage: ./convert-world.sh [server folder or world folder]   (default: GSPackServer next to this script)
# Stop the server first. A dry run shows what will change, then it asks. Needs PowerShell 7 (pwsh).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
if ! command -v pwsh >/dev/null 2>&1; then
  echo "PowerShell 7 (pwsh) is needed: https://aka.ms/powershell" >&2
  exit 1
fi
pwsh -NoProfile -File "$here/Convert-World.ps1" -Interactive -World "${1:-$here/GSPackServer}"
