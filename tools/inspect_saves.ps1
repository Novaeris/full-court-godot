# Demonstrates save, list, load and corruption recovery. Usage:  ./tools/inspect_saves.ps1
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --script res://tools/inspect_saves.gd
