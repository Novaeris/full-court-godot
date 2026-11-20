# Renders the screenshot matrix: a set of screens at several window sizes (opens a window briefly for each picture).
# Usage:  ./tools/screenshot_matrix.ps1 -Out docs/validation/ui/milestone1 [-Sizes 412x915,1024x768,1280x800] [-Screens menu,dynasty_hub,...]
# The default screens and sizes are the baseline set in docs/UI_POLISH_PLAN.md (Phase 0). Sizes use true pixels (no stretch scaling).
param(
	[Parameter(Mandatory = $true)][string]$Out,
	[string[]]$Sizes = @("412x915", "1024x768", "1280x800"),
	[string[]]$Screens = @("menu", "Overview", "career_hub", "dynasty_hub", "dynasty_collection", "dynasty_reveal")
)
$project = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force $Out | Out-Null
$outFull = (Resolve-Path $Out).Path
foreach ($screen in $Screens) {
	foreach ($size in $Sizes) {
		$file = Join-Path $outFull ("{0}_{1}.png" -f $screen, $size)
		godot_console --path $project --script res://tools/screenshot.gd -- screen=$screen size=$size out=$file | Select-String "saved|ERROR" 
	}
}
