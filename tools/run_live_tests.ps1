# Runs the live UI tests (tests/live): tweens, timers, focus and signals that only work once nodes are inside the scene tree.
# Usage:  ./tools/run_live_tests.ps1 [-Filter name]      Exit code 0 = pass.
param([string]$Filter = "")
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --import --quit 2>&1 | Out-Null
if ($Filter -ne "") {
	godot_console --headless --path $project --script res://tests/run_live_tests.gd -- "--filter=$Filter"
} else {
	godot_console --headless --path $project --script res://tests/run_live_tests.gd
}
exit $LASTEXITCODE
