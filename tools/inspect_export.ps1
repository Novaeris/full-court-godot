# Lists and checks the contents of an exported package. Usage:  ./tools/inspect_export.ps1 builds/windows/FullCourt.exe
param([Parameter(Mandatory = $true)][string]$Package)
$project = Split-Path -Parent $PSScriptRoot
$full = (Resolve-Path $Package).Path
godot_console --headless --path "$project/tools/export_inspector" --script res://inspect.gd -- $full
exit $LASTEXITCODE
