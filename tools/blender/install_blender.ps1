# Installs Blender 4.5 LTS PORTABLE for the current user: no administrator rights, no installer, nothing outside the target folder.
# Reproducible: downloads the official zip from download.blender.org, checks it against the SHA-256 blender.org publishes, unpacks it, then installs and
# enables the MCP for Blender add-on (version pinned in .mcp.json) so Claude Code can drive Blender.
#   ./tools/blender/install_blender.ps1                 # to %LOCALAPPDATA%\Programs\Blender-4.5.10
#   ./tools/blender/install_blender.ps1 -Target D:\Tools\Blender
# Blender is GPL software (free, commercial use of what you make with it is allowed). Nothing here needs an account or a key.
param([string]$Target = "$env:LOCALAPPDATA\Programs\Blender-4.5.10", [string]$Version = "4.5.10", [switch]$SkipAddon)
$ErrorActionPreference = "Stop"
$series = ($Version -split "\.")[0..1] -join "."
$name = "blender-$Version-windows-x64"
$base = "https://download.blender.org/release/Blender$series"
$exe = Join-Path $Target "$name\blender.exe"
if (Test-Path $exe) {
	Write-Host "Blender $Version is already installed at $exe"
} else {
	$work = Join-Path ([System.IO.Path]::GetTempPath()) "fc-blender-install"
	New-Item -ItemType Directory -Force $work | Out-Null
	Write-Host "Downloading the checksum list and Blender $Version (about 400 MB) ..."
	Invoke-WebRequest "$base/blender-$Version.sha256" -OutFile (Join-Path $work "sums.txt")
	$expected = ((Get-Content (Join-Path $work "sums.txt")) | Where-Object { $_ -match "$name\.zip" } | Select-Object -First 1) -split "\s+" | Select-Object -First 1
	if (-not $expected) { throw "could not find the published checksum for $name.zip" }
	$zip = Join-Path $work "$name.zip"
	Invoke-WebRequest "$base/$name.zip" -OutFile $zip
	$actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
	if ($actual -ne $expected.ToLower()) { throw "checksum mismatch: expected $expected, got $actual. The download was NOT unpacked." }
	Write-Host "Checksum verified ($actual). Unpacking ..."
	New-Item -ItemType Directory -Force $Target | Out-Null
	Expand-Archive -Path $zip -DestinationPath $Target -Force
	Remove-Item $work -Recurse -Force
}
& $exe --version | Select-Object -First 1
if (-not $SkipAddon) {
	Write-Host "Installing and enabling the MCP for Blender add-on ..."
	$env:PYTHONIOENCODING = "utf-8"
	& uvx --from mcp-for-blender==2.3.1 mcp-for-blender install-addon
	& $exe -b --python-expr "import bpy; bpy.ops.preferences.addon_enable(module='blender_mcp'); bpy.ops.wm.save_userpref(); print('MCP add-on enabled:', 'blender_mcp' in bpy.context.preferences.addons)"
}
Write-Host "Done. Set BLENDER_PATH=$exe (or leave it: tools/blender/run_blender.ps1 finds this location)."
