# Prints a tour of the data model with sample data. Usage:  ./tools/inspect_data.ps1
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --script res://tools/inspect_data.gd
