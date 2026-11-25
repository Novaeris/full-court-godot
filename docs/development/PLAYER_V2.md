# Player visual system V2 (D-075)

Status: built 2026-11-24 (M2 to M9). Opt-in: a replay wears V2 players with `model = "v2"` (or `FcBroadcast3DView.player_model = "v2"`); portraits come from V2 when `FcPlayerRender.enabled`. The founder's single switch is `"promoted": true` in `data/player_pipeline/asset_library.json` (it makes V2 the replay default and turns on 3D portraits). Until then the generated body stays the default and the fallback.

## Build (Blender, headless, reproducible)
```
./tools/blender/install_mpfb.ps1                        # once: MPFB 2.0.18 + the CC0 MakeHuman system assets, checksums pinned, into the user profile
python tools/blender/v2/make_textures.py                # skin detail and pore maps, irises, brow and lash cards (only when the sources change)
./tools/blender/run_blender.ps1 -b --python tools/blender/v2/build_v2.py -- --out assets/players/v2/fc_v2_body.glb
godot_console --headless --path . --import --quit
godot_console --headless --path . --script res://tools/validate_project.gd
godot_console --headless --path . --script res://tests/run_tests.gd -- --filter=player_v2
```
Inspection (outputs OUTSIDE the project: Godot imports `.blend` files): `--keep-blend <dir>` then `tools/blender/v2/preview_v2.py` (front, side, back, face, faces and body morph sheets) and `preview_hair.py` (every hair and facial-hair style). CI validates and tests the committed V2 files; it does not rebuild them (MPFB and its asset host are not reliable CI dependencies).

| Module | Role |
|---|---|
| `v2/mh.py` | MPFB services (create, macros, targets, assets, refit) |
| `v2/morphs.py` | the base build (male, about 2.0 m, athletic) and the 64 named morphs: 14 body (`fcb_`), 50 face (`fcf_`: head shapes, jaw, chin, cheeks, forehead, nose, mouth, lips, eyes, brows, ears, asymmetry) |
| `v2/rig_convert.py` | `game_engine` rig (53 bones, MakeHuman weights) -> the 16 standard names + `x_` extensions (spine, clavicles, three joints per finger, toes); arms posed down as the rest |
| `v2/garments.py` | garments cut from the body surface and DRAPED (jersey with armholes and scoop neck, shorts per leg, socks with a level cuff), trim, shoes (hull upper, wider rubber sole, laces, heel tab), sleeves and wristbands; weights transferred from the body; body morphs captured through Surface Deform |
| `v2/hair.py` | ten hair styles and five facial-hair styles on scalp and face shells carrying a hair density (vertex colour), volume styles, strand tubes for cornrows, braids and dreadlocks, the headband |
| `v2/build_v2.py` | the whole build; writes the body file and `parts/fc_v2_parts.glb` |

Body macros (mass, muscle) are masked out of the head so heavy players keep athletic faces. The MakeHuman cornea shell is removed (the game eye shader gives the gloss).

## Game side
- `FcPlayerMorphs` (pure): eight body types from position and build (lean and athletic guards, standard and muscular wings, athletic and strong forwards, traditional and heavy centres) plus continuous mass and muscle; face morphs from the identity (face, jaw, nose, mouth, brow, eye size, width) and the key; hair, facial hair, headband and equipment choices. Data: `data/player_pipeline/v2_bodies.json`.
- `FcBroadcastCharacter` (V2 path): loads the body, attaches the chosen parts, sets the morph weights, bakes them ONCE (no per-frame morph cost), dresses (`FcPlayerV2Materials`, `player_skin.gdshader`, `player_hair.gdshader`, `jersey_cloth.gdshader` with printed number, surname and wordmark and stitched seams), scales the arms by wingspan, shares the torso bend over three spine joints, drives 15 finger joints per hand (`FcHandPoses`). Kits: home (team colour), away (light, team-colour trim), alternate (dark).
- `FcPlayerLod`: three tiers: automatic LOD chains (meshoptimizer) on the big meshes, distance cut-offs for lashes and laces (medium) and brows, wristbands and trim (low); results cached per player. The replay builds characters with the bake deferred and `FcPlayerBaker` bakes a few milliseconds per frame, so the screen opens at once.
- Validator: model standard 2 (`fc_model_version` 2): the x_ chain rule for standard parents, the V2 surface vocabulary, `fcb_`/`fcf_` morph names, per-level and per-part triangle budgets. Version-1 models are checked exactly as before.

## Measured (development machine; `docs/validation/player_v2/perf/benchmarks.txt`)
Full arena, 31 characters + 6,000 crowd, 1080p: 6.3 ms average, p95 about 9 ms, no frame over 16.6 ms (generated body: 3.2 ms). Real replay screen: 6.0 ms average. Video memory about 195 MB. A player is about 47,000 triangles at the closest level (LOD chains reduce it with distance). Not measured: lower-end hardware.

## V2.1 refinement (2026-11-25)
The founder kept the V2 direction and asked for a reference player at a professional standard before the roster. Built:
- **Standardized comparison scene** `tools/reference_scene.gd` (one reference player, studio lighting, nine views: front, side, back, face, upper body, hands, shoes, neutral and action pose); identical for every model version (`model=""` procedural, `library` M1, `v2`). Sheets in `docs/validation/player_v21/compare_*.png`.
- **Jersey:** rounded scoop neckline, curved armholes with 6 cm straps, a fitted athletic drape (at most 4.5 cm off the body), bound to the spine and pelvis only (an arm raising no longer lifts the sides), small holes from the cut filled.
- **Hems:** jersey, shorts, socks, sleeves and wristbands are cut by exact horizontal planes, so every hem and cuff is level and clean.
- **Shoes:** rebuilt as a basketball shoe from measured foot slices: a rubber cupsole wider than the foot with toe spring, a padded upper rising to a high collar, a tongue, six laces, a heel tab; the bare foot inside is removed from the skin. Matte materials.
- **Shorts:** straighter, less balloon-like legs.
- **Facial hair and fades:** soft-edged mustache and goatee masks, thinner shells, a facial-hair shader that breaks the edges into strands; wider fade gradients.
- **Skin:** calibrated detail map, roughness from the detail, filmic studio check.
Everything is part of the generator, so every player of the roster gets it (`docs/validation/player_v21/roster/`).
