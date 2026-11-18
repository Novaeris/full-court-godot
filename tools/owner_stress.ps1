# Plays the same league with three fixed owner strategies (careful, naive, reckless) and prints the books.
# Usage:  ./tools/owner_stress.ps1 [seasons=30] [teams=12] [seeds=101,102]      (exit code 1 if a run breaks)
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --script res://tools/owner_stress.gd -- @args
exit $LASTEXITCODE
