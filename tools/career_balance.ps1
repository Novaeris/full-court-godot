# Career balance sweep: one career per archetype and seed, summarised. Exit code 1 if an archetype is out of band.
# Usage:  ./tools/career_balance.ps1 [seeds=3] [teams=12] [seasons=20]
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --script res://tools/career_balance.gd -- @args
exit $LASTEXITCODE
