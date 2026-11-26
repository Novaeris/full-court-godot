# The master player export pipeline in one command (D-076): export the master read-only, import into Godot, validate, run the player tests and render the
# approval views (Blender and the game). The master is never written. Stops at the first failure.
#   ./tools/blender/master/export_and_check.ps1 [-Out docs/validation/player_master/latest]
param([string]$Out = "docs/validation/player_master/latest")
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
Set-Location $root
$blender = Join-Path $PSScriptRoot "..\run_blender.ps1"
$master = "art_source/players/fc_master_player.blend"

function Step($name, [scriptblock]$block) {
    Write-Output "== $name"
    & $block
    if ($LASTEXITCODE -ne 0) { throw "$name failed (exit $LASTEXITCODE)" }
}

Step "export (read-only)" { & $blender -b $master --python tools/blender/master/export_master.py | Select-String "FC_EXPORT_OK|FC_MASTER_CHANGED|Traceback" }
Step "godot import" { godot_console --headless --path . --import --quit | Out-Null }
Step "project validation" { godot_console --headless --path . --script res://tools/validate_project.gd | Select-Object -Last 1 }
Step "player tests" { godot_console --headless --path . --script res://tests/run_tests.gd -- --filter=player_v2 | Select-String "Tests:|FAIL" }
New-Item -ItemType Directory -Force "$Out/blender", "$Out/godot" | Out-Null
Step "blender approval renders" { & $blender -b $master --python tools/blender/master/render_master.py '--' --out (Join-Path $root "$Out/blender") | Select-String "FC_RENDER_OK|Traceback" }
Step "game approval renders" { godot_console --path . --script res://tools/reference_scene.gd -- out=$Out/godot model=v2 | Select-String "saved" | Measure-Object | ForEach-Object { "$($_.Count) views" } }
Write-Output "FC_PIPELINE_OK $Out"
