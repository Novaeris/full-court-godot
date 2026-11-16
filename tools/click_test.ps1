# Drives the real UI with simulated mouse clicks (new game, tabs, buttons, draft, offseason) and checks the game changed.
# Usage:  ./tools/click_test.ps1            (no window needed)
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --script res://tools/click_test.gd
