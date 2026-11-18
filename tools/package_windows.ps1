# Builds the Windows game and packs it as builds/FullCourt-<version>-windows.zip (the exe, a short how-to and the licenses).
# Usage:  ./tools/package_windows.ps1
$project = Split-Path -Parent $PSScriptRoot
& "$PSScriptRoot/export_windows.ps1"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$version = (Select-String -Path "$project/src/core/version.gd" -Pattern 'GAME_VERSION := "([^"]+)"').Matches[0].Groups[1].Value
$stage = "$project/builds/package"
Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item "$project/builds/windows/FullCourt.exe" $stage
Copy-Item "$project/LICENSE" "$stage/LICENSE.txt"
@"
Full Court $version

Double-click FullCourt.exe to play. Nothing needs to be installed.
Windows may show a SmartScreen warning because this early build is not code-signed: choose "More info", then "Run anyway".
Your saved games and settings are kept in %APPDATA%\Godot\app_userdata\Full Court.
If something goes wrong, open the game's About screen, choose "Open the logs folder" and send the newest log file.
Made with the Godot Engine (MIT license), see the About screen in the game.
"@ | Set-Content -Encoding utf8 "$stage/READ ME FIRST.txt"
$zip = "$project/builds/FullCourt-$version-windows.zip"
Remove-Item $zip -ErrorAction SilentlyContinue
Compress-Archive -Path "$stage/*" -DestinationPath $zip
Write-Host "Packed $zip"
