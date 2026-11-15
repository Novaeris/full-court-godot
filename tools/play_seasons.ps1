# Plays several seasons with offseasons between them and prints the league history.
# Usage:  ./tools/play_seasons.ps1 [seasons=5] [seed=2026] [teams=30] [conferences=2] [divisions=3]
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --script res://tools/play_seasons.gd -- @args
