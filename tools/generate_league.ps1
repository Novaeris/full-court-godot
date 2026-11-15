# Generates a customizable league and prints a report.
# Usage:  ./tools/generate_league.ps1 [option=value ...]
# Examples:
#   ./tools/generate_league.ps1 seed=12345
#   ./tools/generate_league.ps1 areas=europe teams=20 conferences=2 divisions=2
#   ./tools/generate_league.ps1 cities=london,paris,madrid,berlin,rome,milan conferences=1 divisions=1
# See the top of tools/generate_league.gd for all options.
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --script res://tools/generate_league.gd -- @args
