# Creates the folder link that lets Creator Studio use the game's one shared copy of src/content.
# Run once after cloning (and again if the link ever goes missing). No admin rights needed.
# creator_studio/shared_content  ->  src/content   (a Windows "junction"; same files, not a copy)
$project = Split-Path -Parent $PSScriptRoot
$link = Join-Path $project "creator_studio\shared_content"
$target = Join-Path $project "src\content"
if (Test-Path $link) {
	Write-Host "Link already exists: $link"
	exit 0
}
New-Item -ItemType Junction -Path $link -Target $target | Out-Null
Write-Host "Created link: $link -> $target"
