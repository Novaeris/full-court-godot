# Measures the B1 reconstruction spike over many games (validity, repeatability, clock compression). Read-only.
# Usage:  ./tools/reconstruct_spike.ps1 [games=40] [seed=7000]     Exit code 1 if any game fails validation or is not repeatable.
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --import --quit 2>&1 | Out-Null
godot_console --headless --path $project --script res://tools/reconstruct_spike.gd -- @args
exit $LASTEXITCODE
