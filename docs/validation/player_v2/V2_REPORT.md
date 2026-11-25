# Player visual system V2 (M2 to M9): report

Date: 2026-11-24. Decision D-075. Status: built, integrated, tested and verified in the game; opt-in until the founder approves the look (`"promoted"` flag).

## What changed
M1 built players from script-made tubes and spheres; the founder rejected it. V2 starts from a professionally modelled human: the MakeHuman base mesh (CC0), generated headlessly by the MPFB add-on (approved by the founder as the foundation). Everything basketball-specific is built by our code on top of it.

| Milestone | Result |
|---|---|
| M2 anatomy | a 13,380-vertex anatomical body (chest, back, abdominals, deltoids, arms, hands with five modelled fingers, knees, ankles, feet), eight body types from position and build, mass and muscle as morphs, height as scale, wingspan as arm length |
| M3 faces | 50 face morphs (seven head shapes, jaw, chin, cheekbones, forehead, nose, mouth, lips, eye size and spacing, brows, ears, asymmetry) chosen from the identity and the key: 100 test players give 100 different faces; real eyes with iris, brow and lash cards |
| M4 hair | buzz, low and high fade, taper, short curls, afro, cornrows, braids, dreadlocks, long; stubble, mustache, goatee, short and full beard; hair density shader for natural hairlines and fades; headband |
| M5 clothing | jersey and shorts are separate garments cut from the body and draped (armholes, scoop neckline, hem, waistband, folds, stitched seams, weave), printed number, surname and wordmark; home, away and alternate kits; they follow every build |
| M6 equipment | basketball shoes (upper, wider rubber sole, laces, heel tab), socks with cuffs, arm and knee sleeves, wristbands, headband |
| M7 rig | MakeHuman's professional weights on our rig (16 standard bones + spine, clavicles, three joints per finger, toes); torso bend shared over three spine joints; all 34 animation states verified (contact sheet), the two-hand ball grip still lands on the ball (test) |
| M8 materials | skin shader (tone-neutral detail map tinted by the identity tone, pore normals, roughness variation, scatter rim), eye, hair and cloth shaders, shoe material zones |
| M9 integration | one identity resolver for every mode; Owner replay, Owner, Career and Dynasty profiles, portraits all show V2; three levels of detail; progressive baking (no freeze); validator model standard 2; tests |

Pictures: `compare_*.png` (procedural default / M1 / V2), `compare_replay_*.png` (the real replay), `final/` (showcase, replay, three mode profiles, portraits), `m7/pose_sheet_*.png` (34 states), `m4/hair_styles_blender.png`, `m2/face_variety_blender.png`.

## Verification
- Tests: `test_player_v2` (14) plus the existing suites; totals in `docs/TESTING.md`. Project validator: 0 problems. Creator Studio smoke: PASS.
- Performance: see `perf/benchmarks.txt` and `docs/development/PLAYER_V2.md`.

## Known limitations (honest)
- Faces are generated variations of one CC0 base: believable and distinct, but not hand-sculpted likenesses; no facial animation yet (MakeHuman expression targets exist for later).
- Hair is shell and tube geometry with a density shader, not strand simulation; long hair and braids do not swing.
- Cloth is draped geometry with shader folds and seams, not cloth simulation.
- Shoes are a single generic silhouette in team or neutral colours; no logos (none are allowed).
- The build depends on MPFB and the MakeHuman asset host, so CI validates committed assets instead of rebuilding them.
- Frame cost is about twice the generated body (still well inside the 16.6 ms frame on the development machine); lower-end hardware is not measured.

## Decision for the founder
Approve the look, then set `"promoted": true` in `data/player_pipeline/asset_library.json`. That makes V2 the replay default and turns on portraits from the 3D model; the generated body stays the fallback.

## Recommended next milestone
Basketball animation production on the V2 rig: authored motion for shooting, dribbling, layups, dunks and defence, finger poses keyed to the ball, secondary motion for hair and shorts.
