# Creates an invented SAMPLE draft for Creator Studio so Dynasty Mode can be tried end to end. Usage:  ./tools/dynasty_sample_draft.ps1
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --import --quit 2>&1 | Out-Null
godot_console --headless --path $project --script res://tools/dynasty_sample_draft.gd
exit $LASTEXITCODE
