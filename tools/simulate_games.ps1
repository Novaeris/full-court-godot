# Simulates many games and checks the results look like real basketball.
# Usage:  ./tools/simulate_games.ps1 [games=1000] [seed=2026] [box] [mirror]
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --script res://tools/simulate_games.gd -- @args
