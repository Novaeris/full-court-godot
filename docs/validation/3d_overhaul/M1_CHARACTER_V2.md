# 3D overhaul, M1: character v2

Written 2026-11-23. Pictures: `docs/validation/3d_overhaul/m1/` (made by `tools/character_showcase.gd`, real arena lighting). Baseline for comparison: `m0/`.

## What changed
- `FcBodyArchetype` (pure): the body of a player as numbers (fractions of the height) from the identity, height, weight, position and key. Height, mass (weight for the height), muscle, wingspan, shoulders, chest, waist, hips, limb radii, head height (taller bodies have relatively smaller heads), neck, hands, feet, and the face proportions the 2D portraits already use (face width, jaw, eye gap and size, brow, nose, mouth, headband). Nothing is stored and nothing is random.
- `FcBodyBuilder`: a real `Skeleton3D` (16 bones) and one skinned `ArrayMesh` generated from lofted smooth rings: torso and neck, arms (deltoid, biceps, forearm taper), hands with four fingers and a thumb, legs (thigh, calf), a parametric head (jaw type, ears, nose, brow, eyes with iris, mouth), eight hair styles, facial hair, and a uniform (tank-top jersey with neckline and trim, shorts with a side stripe and hem trim, socks, basketball shoes with soles and an accent stripe, an optional headband).
- `FcMeshSurface`: surface data with smooth normals and a validity check. Godot's front face is clockwise; the helper takes triangles counter-clockwise from outside and stores them reversed (found and fixed during this milestone: the first render showed bodies inside out).
- `FcBroadcastCharacter`: same public API (`setup`, `set_state`, `advance`, `current_pose`, `hand_position`, `part_count`, `joint_names`, `height_feet`, `width_scale`, `identity`, `uniform`, `jersey_number`); the joint Node3D tree became bones. Pose rotations are applied to bones whose rest transforms are pure translations, so `FcBroadcastPose` is unchanged and its tests still hold.
- Anatomical sides: `l_` bones are now at +x (the character's left when facing +z) and `r_` at -x. The previous prototype had them reversed, which turned the defensive arms across the body. The shooting hand is the right hand.
- Number labels ride on a `BoneAttachment3D` on the torso bone.

## Compatibility
Appearance data (skin, hair, face, facial hair), build rules, Creator Studio and saves are unchanged: the pipeline reads only `FcPlayerVisual.resolve`. No data version bump.

## Decision on glTF and Blender
Not adopted in this milestone (no Blender on this machine, and a hand-made GLB cannot be varied for every generated player). The skeleton bone names and surface names are stable, so authored GLB heads, hair or shoes can replace generated parts later.

## Known limits (honest)
- Faces are readable only close up (a showcase camera, not the 28 ft broadcast limit of D-070). At broadcast distance a head is a few pixels; the silhouette, skin tone, hair shape, numbers and builds carry the identity there.
- Fingers are fixed geometry (no finger bones); the hand is rigid, so it will not wrap the ball until M2 adds a grip pose.
- Skin is flat-shaded vertex colour with no texture detail; clothing has no fabric texture or lettering.
- Shorts and jersey are simple shells.

## Verification (2026-11-23, development machine only: Ryzen 7 8700F, RTX 4060, gl_compatibility, 1920x1080, vsync off)
- Unit suite: 1,656 passed, 1 failed on the first full run; the one failure was the style lint (literal colours in the new builder). Fixed by moving the fixed colours to `data/ui/character_palette.json`; the lint, the 6 new `test_body_archetype` tests, and all 87 `broadcast` unit tests pass after the fix. The full suite was NOT re-run in one piece after that last fix.
- Live: `test_live_broadcast3d` 6 passed.
- Benchmark `perf_benchmark mode=replay3d run=standard seconds=30` (the M8 procedure, but 30 s): avg 3.21 ms, p95 4.10 ms, p99 4.65 ms, worst 11.57 ms, 0 frames over 16.6 ms; working set 306 MB; video memory 57 MB; nodes 558; draw calls 587 to 501 (M8: about 850 to 900, because each body is now one skinned mesh instead of about 25 parts). Limits: p95 16.6 ms, p99 33.3 ms.
- Triangles per character: not recorded exactly; a unit test only checks each body stays between 3,000 and 20,000.
