# Packs the Windows build and (only with -Publish) uploads it as a GitHub Release of THIS repo (Novaeris/full-court-godot).
# Default is a DRY RUN: it builds the zip and prints what it would publish. Publishing is public, so run it yourself on purpose.
# Usage:  ./tools/publish_release.ps1                 (dry run)
#         ./tools/publish_release.ps1 -Publish        (create the release and upload the zip)
param([switch]$Publish)
$project = Split-Path -Parent $PSScriptRoot
$version = (Select-String -Path "$project/src/core/version.gd" -Pattern 'GAME_VERSION := "([^"]+)"').Matches[0].Groups[1].Value
$tag = "v$version"

$dirty = git -C $project status --porcelain
if ($dirty) { Write-Host "The working tree has uncommitted changes; commit them first so the release matches a commit."; exit 1 }
$branch = git -C $project rev-parse --abbrev-ref HEAD
if ($branch -ne "main") { Write-Host "Release from main (you are on $branch)."; exit 1 }

& "$PSScriptRoot/package_windows.ps1"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$zip = "$project/builds/FullCourt-$version-windows.zip"
if (-not (Test-Path $zip)) { Write-Host "Missing $zip"; exit 1 }
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
$notes = "Full Court $version for Windows.`n`nUnzip and double-click FullCourt.exe. This early build is not code-signed, so Windows may warn: choose More info, then Run anyway.`n`nSHA-256: $hash"

if (-not $Publish) {
	Write-Host "DRY RUN. Would create release $tag with $zip"
	Write-Host $notes
	exit 0
}
gh release create $tag $zip --repo Novaeris/full-court-godot --title "Full Court $version" --notes $notes
exit $LASTEXITCODE
