# Player animation pipeline

Status: built and verified on 2026-11-24. The live game still animates with the procedural pose library (`FcBroadcastPose`); the Blender clip pipeline exists, is lossless and is tested, but clips are not yet played by the game. A migration plan is in section 6. Nothing was replaced.

## 1. What exists
| Piece | File | What it does |
|---|---|---|
| The animation library | `src/ui/broadcast3d/broadcast_pose.gd` | 34 states as pure maths (the live system) |
| Retarget layer | `src/ui/broadcast3d/rig_retarget.gd` | lets any standard-bone rig wear those poses whatever its bone axes |
| Bake | `tools/export_pose_library.gd` | every state to keyframes at 30 fps, including ground contact and the two-hand ball IK, as `build_tmp/pose_library.json` (derived, git-ignored) |
| Blender import | `tools/blender/import_pose_library.py` | one Action per state on the standard armature, looping, exported as `assets/animations/source/fc_player_clips.glb` |
| Native library | `tools/bake_clip_library.gd` | converts the GLB to `assets/animations/fc_player_clips.res` (validates every clip first; writes nothing if any is wrong) |
| Loader and sampler | `src/ui/broadcast3d/pose_clips.gd` | loads the library, samples any state at any loop phase, poses a skeleton |
| Clip validator | `src/ui/broadcast3d/animation_clip_validator.gd` | the compatibility rules (section 4), run by `tools/validate_project.gd` and CI |

## 2. The animation states
Locomotion: `idle`, `walk`, `run`, `sprint`, `stop`, `turn`, `jump`, `land`, `fall`, `celebrate`, `sit`, `coach`, `intro`. With the ball: `dribble` (right hand), `dribble_l` (left hand: the right-handed clip seen in a mirror, `FcBroadcastPose.mirrored`), `dribble_run`, `crossover`, `hesitation`, `drive`, `post`, `pass`, `catch`. Scoring: `shoot`, `three`, `layup`, `dunk`. Defence: `defend`, `shuffle`, `contest`, `steal`, `block`, `rebound`, `recover`, `screen` (setting a screen). The list the founder asked for (running, walking, sprinting, dribbling with either hand, passing, catching, jump shots, layups, dunks, rebounding, defensive stances, steals, blocks, screens, celebrations) is covered. **`dribble_l`, `pass`, `catch` and `screen` exist and are tested but nothing in the replay uses them yet**: the event log has no left-handed player, no pass events (only an assist on a basket) and no screens, so wiring them would invent facts. They are there for cinematics and for animators.

## 3. The round trip (the proof)
Procedural pose, baked to keyframes, Actions in Blender, a GLB, read by Godot, converted to a native library, played on the Blender-built player: **every joint of every one of the 34 clips is within 0.0000 of the body height of the procedural pose at the sampled frames** (`test_a_clip_made_in_blender_plays_on_the_blender_rig_like_the_procedural_pose`, which fails above 1.5%). It took three fixes to get there, all recorded because they will bite an animator:
1. **glTF time is frame / fps.** A first key on Blender frame 1 lands at 0.033 s, so every key was one frame late. Key from frame 0.
2. **Godot's scene importer drops keys.** Importing the clip GLB through the editor re-fits the tracks (an optimizer tied to the `animation/fps` import setting) and removed keys at the peak of fast movements: a sprint cycle was up to 3% of the body height off. Reading the GLB directly with `GLTFDocument` keeps every key, so the GLB lives in `assets/animations/source/` (a `.gdignore` folder: not imported, not exported) and `tools/bake_clip_library.gd` writes a native `.res` library.
3. **Constant tracks become one key** on import (`remove_immutable_tracks`), so the validator asks for at least one key, not two.

## 4. Clip compatibility rules (enforced by `FcAnimationClipValidator`)
A clip is named after the state it plays (or `x_something`); it animates only the 16 standard bones (or `x_` bones) by rotation, and by position only on the `pelvis`; never by scale; 0.2 to 8 s long; every rotation track has at least one key; every value is finite and every rotation a unit quaternion; no tracks for anything but bones. Because rotations are stored per bone and the only translation is the pelvis, **a clip plays on every player whatever the proportions**; the pelvis position is scaled by the player's height (`root.y * height` in the game).

## 5. How to author or change an animation
1. Regenerate the baseline if the pose maths changed: `godot_console --headless --path . --script res://tools/export_pose_library.gd`.
2. Build the Actions in Blender and keep the file: `./tools/blender/run_blender.ps1 -b --python tools/blender/import_pose_library.py -- --library build_tmp/pose_library.json --keep-blend clips.blend`.
3. Open `clips.blend`, pick an Action (named after the state), and edit it in the Dope Sheet or the Graph Editor: the armature is the standard one, so rotate bones in pose mode and key `rotation_quaternion`; keep the first and last frame equal so it loops; move only the pelvis. For a new motion (a left-hand crossover, a pump fake) duplicate an Action and name it `x_name` or add a state to `FcBroadcastPose.STATES` first.
4. Export a GLB with Animation on, Mode `Actions`, Sampling off, to `assets/animations/source/` (the script does this with the right settings).
5. Convert and validate: `godot_console --headless --path . --script res://tools/bake_clip_library.gd`.
6. `tools/validate_project.gd` and the pipeline tests must pass. The Blender MCP can be used for step 3 (look at the pose, fix a bone), but the repeatable path is the scripts.

## 6. Procedural, clips and blending: the findings and the migration plan
- **What procedural animation does better here**: it adapts to every body (a 5 ft 11 guard and a 7 ft 2 centre), cannot desynchronise from the events, needs no authored data, is unit-tested for loops and for no popping between any two states, and adds ground contact and hand-on-ball IK on top for free.
- **What clips do better**: an animator can give a move weight, timing and style the maths cannot; any motion can be authored without writing code; clips are the only way to get real motion capture.
- **Retargeting** works in both directions today: the retarget layer drives any Blender rig from the pose maths, and clips authored on the standard armature play on any standard player. Mixamo (free with an Adobe account; characters and animations may be used in commercial projects when embedded, but the raw files may not be redistributed, and downloads cannot be automated) can supply raw motion: import to Blender, retarget onto the 16 bones, bake to Actions on the standard armature, then the steps above. It is not installed or required.
- **Blending today**: `FcBroadcastPose.blend` interpolates Euler angles (proven not to pop between any two states). Euler blending is NOT safe for large rotations from clips (Euler representations flip near 90 degrees), so clip states need quaternion blending.
- **Migration plan (nothing below is done)**: (1) add an optional quaternion field to the pose dictionary and slerp it in `blend`; (2) let `FcBroadcastCharacter` take a `FcPoseClips` and, per state, use the clip for the joint rotations and pelvis while keeping the procedural `air`, `grip` and ball anchor, ground contact and IK on top (the hand-on-ball solve works on any rig already); (3) switch ONE state at a time behind a flag (start with `celebrate` and `intro`, which no simulation event depends on), keeping the procedural state as the fallback and the regression tests as the gate; (4) only when an animator's clip is judged better in pictures and in motion, make it the default for that state. Each step is small and reversible; the procedural library stays as the specification and the test oracle.

## 7. Verification that exists
`tests/unit/test_player_pipeline.gd` (14: the clip library has every state, lasts as long as the state, passes the project validator, and plays on the Blender-built player exactly like the procedural pose; a missing or wrong file is refused with reasons), `tests/unit/test_project_validator.gd` (7: each kind of bad clip is caught: wrong name, too short or long, no tracks, a bone not in the standard, a moved bone other than the pelvis, scale, no keys, a track that is not a bone), `tests/unit/test_broadcast_animation.gd` (10, including the mirror and the new pass, catch and screen states), and `.github/workflows/pipeline.yml`, which rebuilds the whole chain from the rig standard on a clean machine.

## 8. Limits (honest)
Clips are baked from the procedural poses, so they are exactly as good as those poses: an animator has not yet improved any of them. Fingers are not animated. The sampler plays loops only. Nothing was tested with a real motion-capture file.
