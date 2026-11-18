# Plays a Career Mode player through many seasons and checks the game stays valid.
# Usage:  ./tools/career_playthrough.ps1 [seasons=20] [teams=12] [seed=7] [archetype=two_way_wing]
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --script res://tools/career_playthrough.gd -- @args
exit $LASTEXITCODE
