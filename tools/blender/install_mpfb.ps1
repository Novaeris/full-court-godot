# Installs the MPFB add-on (MakeHuman for Blender, GPL; a build tool only) and the CC0 MakeHuman system asset pack into the portable Blender's USER profile,
# never into this repository. Both downloads are checked against pinned SHA-256 checksums (D-075, docs/development/PLAYER_V2_ASSESSMENT.md).
#   ./tools/blender/install_mpfb.ps1
$ErrorActionPreference = "Stop"
$addonUrl = "https://extensions.blender.org/download/sha256:c075b3e9b94b8e5556a5f03f4653602d02ea306de08126e8f55ed6dee28a2dad/add-on-mpfb-v2.0.18.zip?repository=%2Fapi%2Fv1%2Fextensions%2F&blender_version_min=4.2.0"
$addonSha = "c075b3e9b94b8e5556a5f03f4653602d02ea306de08126e8f55ed6dee28a2dad"
$assetsUrls = @("https://files.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip",
                "https://files2.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip")
$assetsSha = "b542127a8e25547c7c29c19f2d1d2adb9a664c80396ecd694095dbc8028a0107"
$work = Join-Path $env:LOCALAPPDATA "FullCourtTools\mpfb_download"
New-Item -ItemType Directory -Force $work | Out-Null

function Get-Verified($urls, $file, $sha) {
    $path = Join-Path $work $file
    if (-not (Test-Path $path) -or (Get-FileHash $path -Algorithm SHA256).Hash.ToLower() -ne $sha) {
        foreach ($u in $urls) { try { Invoke-WebRequest -Uri $u -OutFile $path; break } catch { Write-Warning "download failed: $u" } }
    }
    $got = (Get-FileHash $path -Algorithm SHA256).Hash.ToLower()
    if ($got -ne $sha) { throw "checksum mismatch for $file ($got)" }
    return $path
}

$addon = Get-Verified @($addonUrl) "add-on-mpfb-v2.0.18.zip" $addonSha
$assets = Get-Verified $assetsUrls "makehuman_system_assets_cc0.zip" $assetsSha
& (Join-Path $PSScriptRoot "run_blender.ps1") --command extension install-file -r user_default -e $addon
$userData = Join-Path $env:APPDATA "Blender Foundation\Blender\4.5\extensions\.user\user_default\mpfb\data"
New-Item -ItemType Directory -Force $userData | Out-Null
Expand-Archive -Path $assets -DestinationPath $userData -Force
Write-Output "MPFB 2.0.18 and the CC0 system assets are installed (user data: $userData)"
