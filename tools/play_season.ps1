# Plays a full season (regular season, playoffs, awards) and prints the story.
# Usage:  ./tools/play_season.ps1 [seed=2026] [teams=30] [conferences=2] [divisions=3] [era=mid_2010s] [playoffs=16] ...
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --script res://tools/play_season.gd -- @args
