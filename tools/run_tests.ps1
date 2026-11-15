# Runs the full automated test suite headlessly. Usage:  ./tools/run_tests.ps1
$project = Split-Path -Parent $PSScriptRoot
# Refresh step so Godot registers class_name scripts without opening the editor.
godot_console --headless --path $project --import --quit 2>&1 | Out-Null
godot_console --headless --path $project --script res://tests/run_tests.gd
exit $LASTEXITCODE
