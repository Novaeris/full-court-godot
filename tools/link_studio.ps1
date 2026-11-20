# Creates the folder links that let Creator Studio use the game's ONE shared copy of the code and data.
# Run once after cloning (and again if a link ever goes missing). No admin rights needed.
#   creator_studio/game_src  ->  src    (Windows "junctions": the same files, not copies)
#   creator_studio/data      ->  data
#   creator_studio/assets    ->  assets (the fonts and icons of the game's look, which Studio shares)
# Studio needs all of src because the content code uses small helpers from other folders
# (version, seeded random, checks, attribute definitions) and the data/definitions files.
$project = Split-Path -Parent $PSScriptRoot
$links = @(
	@{ Link = "creator_studio\game_src"; Target = "src" },
	@{ Link = "creator_studio\data"; Target = "data" },
	@{ Link = "creator_studio\assets"; Target = "assets" }
)
foreach ($l in $links) {
	$link = Join-Path $project $l.Link
	$target = Join-Path $project $l.Target
	if (Test-Path $link) {
		Write-Host "Link already exists: $link"
	} else {
		New-Item -ItemType Junction -Path $link -Target $target | Out-Null
		Write-Host "Created link: $link -> $target"
	}
}
