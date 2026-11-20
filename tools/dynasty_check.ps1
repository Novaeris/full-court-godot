# Dynasty Mode health check with timings. Usage:  ./tools/dynasty_check.ps1
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --import --quit 2>&1 | Out-Null
godot_console --headless --path $project --script res://tools/dynasty_check.gd
exit $LASTEXITCODE
