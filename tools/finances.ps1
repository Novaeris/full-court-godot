# Plays seasons and prints every team's revenue, expenses, profit and valuation.
# Usage:  ./tools/finances.ps1 [seasons=2] [seed=2026] [teams=30] [conferences=2] [divisions=3]
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --script res://tools/finances.gd -- @args
