# Measures identity and roster facts over several generated leagues (evidence for the authenticity audit). Read-only.
# Usage:  ./tools/audit_identity.ps1 [leagues=20] [seed=5000]
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --import --quit 2>&1 | Out-Null
godot_console --headless --path $project --script res://tools/audit_identity.gd -- @args
exit $LASTEXITCODE
