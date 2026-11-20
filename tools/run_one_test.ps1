# Runs only the test files whose name contains the given text. Usage:  ./tools/run_one_test.ps1 dynasty
param([string]$Filter = "")
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --script res://tests/run_tests.gd -- --filter=$Filter
exit $LASTEXITCODE
