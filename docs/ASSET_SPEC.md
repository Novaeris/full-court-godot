# Asset specification (Visual Identity milestone, D-057)

Three asset categories. Nothing external or AI-generated is shipped without the founder's approval and a line in `assets/ART_PROVENANCE.md`.

| Category | What | How it is made |
|---|---|---|
| A. Generated league players | Every player in Owner and Career leagues | Procedural, deterministic (`FcPlayerVisual` + `FcPlayerFigure`). No raster art. |
| B. Featured Dynasty players | Hand-made Dynasty cards | Approved custom art loaded through a card's `art_path` (tier T1). Falls back to the procedural figure if the file is missing. |
| C. Menu and mode art | Backdrops, mode cards, splash | Procedural / vector first; raster only when approved. |
| D. 3D players (GLB) | Models for the 3D replay | Built in Blender to the rig standard, validated by `FcPlayerModelValidator`; see `docs/development/ASSET_PRODUCTION_PIPELINE.md`. The generated body is the default; a GLB is optional. |

## Specifications
| Item | Spec |
|---|---|
| Player card art (B) | PNG, transparent, **512 x 640** (4:5), head and torso, 32 px safe margin, subject centred, sRGB, no baked text or rarity frame, `data/content_*/art/<player_id>.png` |
| Menu / mode art (C) | Lossless PNG or WebP; backdrops 3840 px wide (cover-scaled, never stretched) with a 1920 px variant; layered pieces as separate transparent PNGs; naming `assets/ui/menu/<mode>_<layer>.png`; a focal point noted in the file name or manifest |
| Brand lockups | PNG with alpha, **no copy larger than its master**: masters are 1667 px (Full Court) and 1360 px (Novaeris) because the supplied banners are 2172 px wide; sizes 1024, 512, 256. Larger masters need the original layered or vector files |
| Brand marks | Novaeris mark 512 / 256 / 128. Full Court has no clean stand-alone mark (the ball's lines run behind the lettering): the lockup is used instead, and the basketball tile SVG for tiny sizes |
| Icons | Windows `.ico` (256, 128, 64, 48, 32, 16), Android 192, adaptive foreground/background/monochrome 432 (artwork inside the central 66%), store icon 1024 |
| Boot splash | 1280 x 720 on brand navy `#0B1020`, Novaeris lockup centred |
| Import | UI art is imported lossless (no VRAM compression for logos or portraits); source banners live in `assets/brand/source/` with a `.gdignore` so they are neither imported nor exported |
| Fallback | A missing or invalid file never errors: brand falls back to a text wordmark, portraits to the procedural figure, mode art to a procedural composition |
| Memory budget | Menu art at most 24 MB decoded in total; any one card art at most 1 MB decoded |

## Rebuilding the brand files
`bash tools/build_brand_assets.sh` (needs ImageMagick 7). The supplied banners have the background baked in, so the transparent versions are made by keying (brightest colour channel becomes opacity), cropping and masking the stray arena lights. The artwork is not redrawn. **If the original layered or vector files exist, replace the keyed files with them.** Known limits of keying: the silver lettering's dark outline is lost, so the transparent files are meant for the dark UI; on white use the `mono_navy` version.

## Portrait pathway for generated and featured players (proposal D-059)
Generated league players use the procedural figure (category A); the proposed high-fidelity figure and its bake cache change nothing here. Featured Dynasty players (category B) keep the art spec above and are the only place approved art is used: every art file needs a line in `assets/ART_PROVENANCE.md` (source: hand-made, commissioned or generated; founder approval; legal review state) before it is committed. Note: the provenance file is `assets/ART_PROVENANCE.md`, not `docs/`.
