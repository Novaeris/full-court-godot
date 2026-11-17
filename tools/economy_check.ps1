# Long-run economy check: plays many AI-only seasons and prints the league's money picture.
# Usage:  ./tools/economy_check.ps1 [seasons=50] [seed=2026] [teams=12] [every=5]
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --script res://tools/economy_check.gd -- @args
