# Player asset library and customisation architecture (Production Phase M1)

Status: built 2026-11-24 (decision D-074). Promotion is the `"promoted"` flag in `data/player_pipeline/asset_library.json` (false until the founder approves; it switches the replay default and the 3D portraits together). Opt-in until then: a replay wears the library players when `FcBroadcast3DView.player_model = FcPlayerAssetLibrary.library_model()` ("library") or a subject carries `"model": "library"`. The generated body remains the default look and the fallback.

## What it is
`FcPlayerVisual.resolve()` is still the ONLY source of a player's identity (skin, hair, face, facial hair, build, face proportions, team colours, number). `FcPlayerAssetLibrary` (`src/ui/broadcast3d/player_assets/`) turns that identity into the names of the pieces that draw it, loads them once, caches them and attaches them. Nothing is saved; the same key gives the same player in Owner, Career, Dynasty, Broadcast and Creator Studio.

| Identity value | Piece |
|---|---|
| archetype bulk (0 to 1) | body file `fc_player_lean`, `fc_player_athletic` or `fc_player_heavy` (thresholds in `data/player_pipeline/asset_library.json`) |
| `face` (face_1 to face_6) and `proportions.jaw` (0 round, 1 square, 2 pointed) | head `skin_head_<face><jaw>` (18 heads) |
| `proportions.nose`, `mouth`, `brow`, `eye_size` | `nose_k` + `nostrils_k`, `lips_k`, `brow_k`, `eyes_k` |
| `proportions.face_w` | head bone scaled across the body (0.94 to 1.06) |
| `hair` | `hair_<style>` (short, fade, afro, curly, long, braids, locs; bald has none) |
| `facial_hair` | `facial_<stubble, goatee, beard>_<jaw>` |
| `proportions.accessory` | `acc_headband` |
| skin, hair colour, team colours | shared `StandardMaterial3D`s by name and colour; jersey and shorts use `jersey_cloth.gdshader` |
| number, surname, team abbreviation | texture drawn once per unique graphic by `FcJerseyGraphics` (Label3D numbers remain the fallback when there is no renderer) |
| animation state and ball grip | `FcHandPoses` rotates the 20 `x_` finger bones (relaxed, open, ball grip, shooting, dribbling, catching) |

## Files
- Body and part GLBs: `assets/players/fc_player_*.glb`, `assets/players/parts/fc_parts_head.glb`, `fc_parts_hair.glb`. All use the 16-bone standard v1; the bodies add 20 `x_` finger bones (extensions only, so no version bump).
- Surface vocabulary (enforced by `FcPlayerModelValidator`, never relaxed to fit a model): required `skin features jersey shorts socks shoes sole`; optional `trim`; prefixes `hair_ facial_ brow_ skin_head_ nose_ nostrils_ eyes_ lips_ acc_`. Part files hold only prefixed meshes and are validated by `validate_part_scene`.
- Registry: `data/player_pipeline/asset_library.json`; hand poses: `data/player_pipeline/hand_poses.json`.
- Blender: `tools/blender/fc_character/` (reusable mesh, rig, material and export helpers) and `tools/blender/basketball/` (context, body, head, hair, clothing); entry `tools/blender/build_player_m1.py`; inspection renders with `tools/blender/basketball/preview.py` (never run inside the project folder: Godot imports `.blend` files).

## Build and check
```
./tools/blender/run_blender.ps1 -b --python tools/blender/build_player_m1.py -- --out-dir assets/players
godot_console --headless --path . --import --quit
godot_console --headless --path . --script res://tools/validate_project.gd
godot_console --headless --path . --script res://tests/run_tests.gd -- --filter=player_m1
godot_console --path . --script res://tools/character_showcase.gd -- out=docs/validation/player_m1/x model=library
```
