# Career balance sweep: one career per archetype and seed, summarised. Exit code 1 if an archetype's average peak is outside 64-86,
# focused careers peak more than 3 below potential, archetypes differ by more than 10 overall points, or a run breaks a rule.
# Usage:  ./tools/career_balance.ps1 [seeds=3] [teams=12] [seasons=20] [strategy=focused|even|template|low_weight]
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --script res://tools/career_balance.gd -- @args
exit $LASTEXITCODE
