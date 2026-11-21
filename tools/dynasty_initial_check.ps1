# End-to-end check of the bundled Founding Series Dynasty release through the normal loader. Usage:  ./tools/dynasty_initial_check.ps1
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --import --quit 2>&1 | Out-Null
godot_console --headless --path $project --script res://tools/dynasty_initial_check.gd
exit $LASTEXITCODE
