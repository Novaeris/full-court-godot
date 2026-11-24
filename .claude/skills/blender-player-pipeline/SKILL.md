---
name: blender-player-pipeline
description: Build, change, validate or animate Full Court basketball player models and animation clips with Blender and GLB. Use for any task that touches assets/players, assets/animations, tools/blender, data/player_pipeline or the imported-player code in FcBroadcastCharacter.
---

# Blender player and animation pipeline

Full documents: `docs/development/ASSET_PRODUCTION_PIPELINE.md` (players) and `docs/development/PLAYER_ANIMATION_PIPELINE.md` (animation). This is the short operating guide.

## Ground rules
- The standard is `data/player_pipeline/rig_standard.json`, generated from the game's own skeleton by `tools/export_rig_standard.gd`. Never edit it by hand; change `FcBodyBuilder` and regenerate.
- Production builds run Blender HEADLESS with scripts (`./tools/blender/run_blender.ps1 -b --python ...`). Use the Blender MCP only to look at or fix a live model, and close Blender afterwards. Never tick "Allow Remote Connections" in the add-on, never add third-party API keys.
- Blender is portable at `%LOCALAPPDATA%\Programs\Blender-4.5.10` (`./tools/blender/install_blender.ps1` recreates it; `BLENDER_PATH` overrides).
- Nothing third-party or AI-generated ships without the founder's approval and a line in `assets/ART_PROVENANCE.md`. The generated body is still the default look; an imported model is opt-in (`FcBroadcast3DView.player_model`).

## Commands
- Build the prototype player: `./tools/blender/run_blender.ps1 -b --python tools/blender/build_player.py -- --out assets/players/fc_player_proto.glb --keep-blend work.blend`
- Import into Godot and validate: `godot_console --headless --path . --import --quit` then `godot_console --headless --path . --script res://tools/validate_project.gd` (exit 0 = clean; the messages say what is wrong in words).
- See it: `godot_console --path . --script res://tools/character_showcase.gd -- out=docs/validation/player_pipeline model=res://assets/players/NAME.glb [poses=1]`; in the real replay: `tools/screenshot.gd -- screen=owner_replay mode=broadcast shot=free_throw model=res://assets/players/NAME.glb out=file.png`.
- Animation round trip: `tools/export_pose_library.gd` (bake) then `blender -b --python tools/blender/import_pose_library.py` (Actions and GLB) then `tools/bake_clip_library.gd` (native library, validates every clip). Do not let the editor import the clip GLB: its optimizer drops keys (the GLB lives in a `.gdignore` folder for that reason).
- Tests: `--filter=player_pipeline`, `--filter=project_validator`, `--filter=3d_budget`.

## Pitfalls already paid for
- Left is +X; the character faces +Z in Godot and -Y in Blender; arms hang (no T-pose); soles on y = 0.
- glTF time is frame / fps: key from frame 0.
- A Blender bone has its own rest rotation: pose rotations go through `FcRigRetarget.local_rotation`; tests that only use X-axis pitches cannot see a broken retarget, so the tests use random rotations.
- Godot collapses constant tracks to one key on import; the clip validator allows that.
- `Skeleton3D.get_bone_global_pose` is stale until refreshed: use `FcBroadcastCharacter._forward_kinematics()`.
