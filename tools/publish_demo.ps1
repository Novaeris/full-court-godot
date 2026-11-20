# Demonstrates publishing, fallback and rollback of content releases in a scratch folder. Usage:  ./tools/publish_demo.ps1
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --import --quit 2>&1 | Out-Null
godot_console --headless --path $project --script res://tools/publish_demo.gd
exit $LASTEXITCODE
