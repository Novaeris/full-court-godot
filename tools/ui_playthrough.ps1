# Plays Owner Mode through the real UI code for several seasons and checks the game stays valid.
# Usage:  ./tools/ui_playthrough.ps1 [seasons=3] [teams=30] [seed=7] [reprice=1]
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --script res://tools/ui_playthrough.gd -- @args
