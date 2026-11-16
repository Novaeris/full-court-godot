# Plays seasons as the owner of one team with a scripted strategy and prints the books.
# Usage:  ./tools/owner_playthrough.ps1 [seasons=8] [seed=2026] [teams=30] [strategy=none|builder|loans|performance]
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --script res://tools/owner_playthrough.gd -- @args
