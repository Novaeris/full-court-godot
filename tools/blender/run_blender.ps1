# Runs Blender with the arguments you give it. Finds Blender in this order: the BLENDER_PATH environment variable, the portable install made by
# tools/blender/install_blender.ps1, a blender.exe on the PATH.
#   ./tools/blender/run_blender.ps1 -b --python tools/blender/build_player.py -- --out assets/players/fc_player_proto.glb
# With no arguments it opens Blender with its window; the MCP for Blender add-on then listens on localhost:9876 (loopback only) for Claude Code.
$candidates = @($env:BLENDER_PATH, "$env:LOCALAPPDATA\Programs\Blender-4.5.10\blender-4.5.10-windows-x64\blender.exe", (Get-Command blender -ErrorAction SilentlyContinue).Source) | Where-Object { $_ -and (Test-Path $_) }
if (-not $candidates) { Write-Error "Blender was not found. Run ./tools/blender/install_blender.ps1 first."; exit 1 }
& ($candidates | Select-Object -First 1) @args
exit $LASTEXITCODE
