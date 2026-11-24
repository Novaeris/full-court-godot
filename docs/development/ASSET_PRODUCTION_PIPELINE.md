# Asset production pipeline: basketball players from Blender to the game

Status: built and verified on 2026-11-24 for a prototype player (`assets/players/fc_player_proto.glb`). The generated procedural body (`FcBodyBuilder`, D-072) is still the default in the game; an imported model is used only when it is requested and passes validation.

## 1. The decision
- **Blender 4.5 LTS** is the production tool. It is free (GPL), runs headless for repeatable builds, and its glTF exporter is the one Godot documents.
- **GLB (binary glTF 2.0)** is the interchange format: one file holds the skeleton, meshes, materials, skin weights and (later) animation clips, and Godot imports it natively with no add-on. No project reason to use another format exists.
- **Blender MCP** lets Claude Code look at and fix a model in a live Blender session (see [MCP_INTEGRATIONS.md](MCP_INTEGRATIONS.md)); **production builds never depend on it**: they run `blender -b --python`, so they are repeatable, in CI, and need no window.

## 2. The player standard (version 1)
The one definition is [`data/player_pipeline/rig_standard.json`](../../data/player_pipeline/rig_standard.json), generated from the skeleton the game builds (`tools/export_rig_standard.gd`; never edit it by hand: change `FcBodyBuilder`, regenerate). `FcPlayerModelValidator` enforces it. In plain words:

| Rule | Value |
|---|---|
| Units and axes | metres; Y up; the player faces **+Z in glTF/Godot (-Y in Blender)**; the character's **left side is +X** |
| Scale | a model declares its height in the armature extra `fc_height_m`; the game scales it to the real height of each player (and a little wider for a heavier build) |
| Skeleton | exactly one `Skeleton3D` with the **16 standard bones**: `pelvis`, `torso`, `neck`, `head`, `l_/r_shoulder`, `l_/r_elbow`, `l_/r_hand` (the wrist), `l_/r_hip`, `l_/r_knee`, `l_/r_foot` (the ankle), with the standard parents. Extra bones are allowed only if named `x_something` and parented (for example future finger bones) |
| Rest pose | standing, **arms hanging straight down**, feet flat and parallel, soles on y = 0 (ankles 0.02 to 0.2 m up). **No T-pose or A-pose**: the pose maths assume hanging arms. Bone roll and axis orientation are free (the retarget layer handles them) |
| Surfaces | one mesh per surface, named exactly: `skin`, `features` (eyes and mouth), `jersey`, `shorts`, `socks`, `shoes`, `sole`, and at least one `hair_<style>` (`hair_short`, `hair_afro`, ...; the game shows the one matching the player and hides the others). Facial hair and headbands are not in the prototype |
| Materials | each mesh has a material named like the surface (`hair` for every `hair_*` mesh). The game REPLACES the colour by name: skin tone, team colours, hair colour, shoes. Textures are not required and are not used for team colours |
| Skinning | every mesh is skinned to the armature, at most 4 weights per vertex, weights sum to 1, smooth at the joints |
| Budget | at most 20,000 triangles per player (the generated body is about 5,000 to 6,000); height 1.6 to 2.45 m |
| Extras | armature custom properties `fc_standard_version = 1` and `fc_height_m` |
| Not allowed | non-uniform scale on bones, shape keys, cameras, lights, loose objects |

## 3. Workflow
1. **Regenerate the standard** after any change to the skeleton: `godot_console --headless --path . --script res://tools/export_rig_standard.gd`.
2. **Build or edit in Blender.** The prototype is built by `tools/blender/build_player.py`, which reads the standard and writes the armature, the surface meshes with explicit weights and the GLB: `./tools/blender/run_blender.ps1 -b --python tools/blender/build_player.py -- --out assets/players/fc_player_proto.glb --keep-blend work.blend`. An artist can open the `.blend`, sculpt or replace any part (keeping the names, the weights and the armature) and re-export with the settings below. To explore or fix a model live, open Blender and let Claude Code use the Blender MCP.
3. **Export settings** (when exporting by hand): Format glTF Binary (.glb); Include: Custom Properties on; Transform: +Y Up; Mesh: Apply Modifiers off for the skinned meshes; Skinning on; Animation off for a model, on for a clip file (see [PLAYER_ANIMATION_PIPELINE.md](PLAYER_ANIMATION_PIPELINE.md)); materials exported; compression off.
4. **Put the file in `assets/players/`**, run `godot_console --headless --path . --import --quit` (creates the `.glb.import` file: commit it).
5. **Validate**: `godot_console --headless --path . --script res://tools/validate_project.gd` (exit 0 = clean; it lists every problem in words, for example "bone l_knee is missing", "the left side must be +X", "mesh jersey must have a material named 'jersey'").
6. **See it**: `godot_console --path . --script res://tools/character_showcase.gd -- out=docs/validation/player_pipeline model=res://assets/players/NAME.glb` (five players in the arena lighting; add `poses=1` for the contact sheet of all 34 animation states), and in the real replay: `godot_console --path . --script res://tools/screenshot.gd -- screen=owner_replay mode=broadcast shot=free_throw model=res://assets/players/NAME.glb out=file.png`.
7. **Provenance**: a line in `assets/ART_PROVENANCE.md` (who made it, from what, review state). Nothing third-party or AI-generated ships without the founder's approval.
8. **Use it**: set `FcBroadcast3DView.player_model` (a `res://` path) to make the players of the 3D replay wear it; the default is empty (generated body). A model that fails validation is refused and the generated body is used instead, with the reasons in `FcBroadcastCharacter.model_problems`. Making a model the default is a product decision for the founder once it looks better than the generated body.

## 4. How a Blender rig is driven by the existing animations (the retarget layer)
The pose library (`FcBroadcastPose`) describes each bone rotation in a frame whose axes are aligned with the world at rest. A Blender rig has its own rest rotation on each bone (its bones point along their own axis; Godot imports the arms with a 180-degree rest flip). `FcRigRetarget.local_rotation` gives each bone `(G^-1 * q * G) * R` (q the pose rotation, R the bone's local rest rotation, G the global rest rotation of its parent), which provably (unit-tested with random rests and random rotations, and checked to fail if the rule is broken) ends every bone in the world-aligned pose on top of its own rest. Ground contact, the hand-on-ball IK and the ball anchor work on the imported rig unchanged, in the units of the model.

## 5. Verification that exists
- `tests/unit/test_player_pipeline.gd` (14): the standard equals the game's skeleton; the prototype passes; the validator catches a renamed bone, a wrong parent, an extension bone rule, a left/right swap, an arm that does not hang, a floating model, a missing surface, no hair mesh, a wrong material name, an unskinned mesh, a wrong standard version, a wrong declared height and badly normalised weights; the imported rig matches the generated body within 1.2% of the height in all 34 states; feet stay on the floor; the wrists reach the ball; a bad model falls back to the generated body and says why; the model wears the team colours and the hair style; the retarget rule holds for any rest and any rotation.
- `tests/unit/test_project_validator.gd` (7) and `tools/validate_project.gd`: GDScript that does not compile, scenes and resources with a missing dependency, assets that are not imported, invalid JSON, invalid player models, incompatible animation clips.
- `.github/workflows/pipeline.yml`: a clean machine downloads Blender (checksum verified), rebuilds the prototype from the standard, imports it and validates it. (It runs only when pipeline files change.)
- `docs/validation/player_pipeline/`: pictures of five Blender-built players in the arena, the contact sheet of the animation states on the Blender rig, and the real replay screen with Blender-built players.

## 6. What the prototype is, and is not (honest)
It is a **script-built** model made to prove the whole chain; it has the same body kit as the generated player (so it looks about the same: smooth, simple, no sculpted detail), a simpler face (eyes and mouth only, no nose bridge details beyond one bump and ears), two hair styles, no facial hair and no headband, and rigid hands. It does not look better than the generated body. The value now is the PIPELINE: an artist can replace any part in Blender under the same names and weights and the game, the validator and CI accept it. Not done: hand-sculpted heads and hair, texture painting, finger bones, a body-type blend (morph targets) pipeline, LODs, and the founder's art direction.
