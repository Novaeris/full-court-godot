# Generates a fictional league and prints a report. Usage:  ./tools/generate_league.ps1 [seed]
$project = Split-Path -Parent $PSScriptRoot
if ($args.Count -gt 0) {
    godot_console --headless --path $project --script res://tools/generate_league.gd -- $args[0]
} else {
    godot_console --headless --path $project --script res://tools/generate_league.gd
}
