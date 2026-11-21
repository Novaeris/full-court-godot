#!/usr/bin/env bash
# Rebuilds the production brand files in assets/brand/ from the two supplied banners in assets/brand/source/.
# Needs ImageMagick 7 (`magick`). Run from the repo root:  bash tools/build_brand_assets.sh
# Why a script: the banners have the background baked in, so the transparent versions are made by "keying" (the brightest colour
# channel becomes the opacity). Keeping the recipe here means the files can be rebuilt, or rebuilt from better originals,
# without guessing. Nothing is redrawn: only cropped, keyed and resized. See docs/ASSET_SPEC.md and assets/ART_PROVENANCE.md.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=assets/brand
SRC=$OUT/source
TMP=$(mktemp -d)
NAVY="#0B1020"

# Key: brightest channel -> opacity. Black point cuts background haze, white point keeps highlights fully opaque.
key() { # input output black white
	magick "$1" -alpha off \( +clone -separate -evaluate-sequence max -level "$3","$4" \) -compose CopyAlpha -composite "$2"
}
# Resized copies: never larger than the master (no fake resolution).
sizes() { # master base widths...
	local m=$1 base=$2; shift 2
	for w in "$@"; do magick "$m" -filter Lanczos -resize "${w}x" "$OUT/${base}_${w}.png"; done
}

# ---------- Full Court ----------
# Crop to the lockup, then blank the arena lights (bokeh) that sit around it.
magick "$SRC/full_court_banner.png" -crop 1700x520+230+80 +repage \
	-fill black -draw "rectangle 0,0 400,105" -draw "rectangle 1560,0 1700,62" -draw "rectangle 0,0 32,520" -draw "rectangle 0,490 1700,520" "$TMP/fc_clean.png"
key "$TMP/fc_clean.png" "$TMP/fc.png" 16% 45%
magick "$TMP/fc.png" -trim +repage "$OUT/full_court_lockup.png"
# One-colour versions: the same shape filled with white (for dark photos) or navy (for light backgrounds).
magick "$OUT/full_court_lockup.png" -alpha extract -level 0%,60% -write mpr:a +delete \
	-size 1x1 xc:white -scale "$(magick identify -format '%wx%h!' "$OUT/full_court_lockup.png")" mpr:a -compose CopyAlpha -composite "$OUT/full_court_mono_white.png"
magick "$OUT/full_court_lockup.png" -alpha extract -level 0%,60% -write mpr:a +delete \
	-size 1x1 "xc:$NAVY" -scale "$(magick identify -format '%wx%h!' "$OUT/full_court_lockup.png")" mpr:a -compose CopyAlpha -composite "$OUT/full_court_mono_navy.png"
sizes "$OUT/full_court_lockup.png" full_court_lockup 1024 512 256

# ---------- Novaeris ----------
magick "$SRC/novaeris_banner.png" -crop 1450x500+360+80 +repage "$TMP/nv_clean.png"
key "$TMP/nv_clean.png" "$TMP/nv.png" 14% 45%
magick "$TMP/nv.png" -trim +repage "$TMP/nv_full.png"
H=$(magick identify -format '%h' "$TMP/nv_full.png")
W=$(magick identify -format '%w' "$TMP/nv_full.png")
# The horizon glow under the wordmark is part of the banner scene, not of the logo: cut it off.
magick "$TMP/nv_full.png" -crop "${W}x$((H-26))+0+0" +repage -trim +repage "$OUT/novaeris_lockup.png"
# Mark (the N with its star) = top part; wordmark = the lettering at the bottom.
LH=$(magick identify -format '%h' "$OUT/novaeris_lockup.png")
magick "$OUT/novaeris_lockup.png" -crop "x$((LH*76/100))+0+0" +repage -trim +repage "$OUT/novaeris_mark.png"
magick "$OUT/novaeris_lockup.png" -gravity south -crop "x$((LH*21/100))+0+0" +repage -trim +repage "$OUT/novaeris_wordmark.png"
sizes "$OUT/novaeris_lockup.png" novaeris_lockup 1024 512 256
sizes "$OUT/novaeris_mark.png" novaeris_mark 512 256 128

# ---------- App icons (lockup on the brand navy) ----------
# The lockup is wide, so the icon is the lockup centred on a navy tile with a soft top light; small sizes use the basketball tile SVG.
tile() { # size out padding-percent
	local s=$1 o=$2 p=$3
	local inner=$((s*p/100))
	magick -size "${s}x${s}" "xc:$NAVY" \( -size "${s}x${s}" gradient:"#1A2A4C-$NAVY" \) -compose Over -composite \
		\( "$OUT/full_court_lockup.png" -resize "${inner}x${inner}" \) -gravity center -compose Over -composite "$o"
}
tile 1024 "$OUT/app_icon_1024.png" 86
tile 512 "$OUT/app_icon_512.png" 86
tile 192 "$OUT/android_icon_192.png" 90
# Android adaptive icon: foreground has transparent margin (66% safe zone), background is plain navy; monochrome is the white lockup.
magick -size 432x432 xc:none \( "$OUT/full_court_lockup.png" -resize 280x \) -gravity center -compose Over -composite "$OUT/android_adaptive_foreground_432.png"
magick -size 432x432 "xc:$NAVY" "$OUT/android_adaptive_background_432.png"
magick -size 432x432 xc:none \( "$OUT/full_court_mono_white.png" -resize 280x \) -gravity center -compose Over -composite "$OUT/android_adaptive_monochrome_432.png"
# Windows icon: 256/128/64 from the lockup tile, 48/32/16 from the basketball tile SVG (legible when tiny).
for s in 256 128 64; do tile $s "$TMP/ico_$s.png" 88; done
for s in 48 32 16; do magick -background none -density 384 assets/icons/app_icon.svg -resize "${s}x${s}" "$TMP/ico_$s.png"; done
magick "$TMP/ico_256.png" "$TMP/ico_128.png" "$TMP/ico_64.png" "$TMP/ico_48.png" "$TMP/ico_32.png" "$TMP/ico_16.png" "$OUT/app_icon.ico"

# ---------- Boot splash: Novaeris lockup centred on navy (shown by Godot before the game starts) ----------
magick -size 1280x720 "xc:$NAVY" \( "$OUT/novaeris_lockup.png" -resize 620x \) -gravity center -compose Over -composite "$OUT/boot_splash.png"

rm -rf "$TMP"
echo "brand assets rebuilt in $OUT"
