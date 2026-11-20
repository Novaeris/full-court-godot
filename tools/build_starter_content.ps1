# Rebuilds data/content_starter (the bundled fallback content release). Usage:  ./tools/build_starter_content.ps1
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --import --quit 2>&1 | Out-Null
godot_console --headless --path $project --script res://tools/build_starter_content.gd
exit $LASTEXITCODE
