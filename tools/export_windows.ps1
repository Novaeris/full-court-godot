# Builds the Windows game: builds/windows/FullCourt.exe (one file, the data is packed inside).
# Needs Godot's export templates for this engine version (Editor > Manage Export Templates, or see docs/RELEASE.md).
# Usage:  ./tools/export_windows.ps1            (release build)
#         ./tools/export_windows.ps1 -Debug      (debug build, shows errors in a console)
param([switch]$Debug)
$project = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force "$project/builds/windows" | Out-Null
# make sure Godot has registered every class before packing
godot_console --headless --path $project --import --quit 2>&1 | Out-Null
$mode = if ($Debug) { "--export-debug" } else { "--export-release" }
godot_console --headless --path $project $mode "Windows Desktop" "builds/windows/FullCourt.exe"
exit $LASTEXITCODE
