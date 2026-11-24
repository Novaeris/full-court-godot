# 3D overhaul, M3: basketball, court and hoop

Written 2026-11-23. Pictures: `docs/validation/3d_overhaul/m3/` (`ball_close`, `hoop`, `board_front`, `hoop_side`, `court_key`, `court_wide`, and the real replay screen: `replay_free_throw`, `replay_baseline`). Made by `tools/character_showcase.gd` and `tools/screenshot.gd`.

## Ball (`FcBasketball`, `basketball.gdshader`, `FcBallMotion`)
- Real size: 0.39 ft radius (a size 7 ball, 9.4 in). It was 0.45 ft and plain orange.
- Pebbled leather and the black channels (equator, meridian, two side curves) are computed per pixel in a shader from the position on the sphere: no texture is loaded or generated, the pattern turns with the ball, the pebbles perturb the lighting normal.
- Motion (pure maths, unit-tested): a dribble bounces between the floor and the hand twice per loop in time with the dribbling arm (it reaches the hand when the arm is fully extended); a pass or shot flies in an arc (a shot higher than a pass), with backspin on shots; a made shot drops through the net and swings it; a missed shot rattles off the rim into the court. Where the ball is at an event still comes from the reconstruction; this only decides how it travels between two known places.
- Two-hand holds (shots, rebounds, dunks) use the arm IK of M2, so the ball is in the shooter's hands.

## Court (`court_floor.gdshader`)
- The old floor was a 10 pixels-per-foot picture of flat boxes with square dots for the arc. The new one is a shader working in court feet: 3-inch planks, 8 ft boards staggered, per-board tone, grain, seams; razor-sharp antialiased lines at any zoom; real dimensions (94 x 50 ft, 16 ft lane 19 ft long, 6 ft free-throw circle dashed inside the lane, 23.75 ft three-point arc with 22 ft corner lines, 4 ft restricted arc, 6 ft centre circle, hash marks, 2-inch lines); the lane, centre circle and border take the home team's colours; surface gloss from the arena identity. It is one material and no image generation (the old `_court_image` pixel loop is gone).
- The team mark and nickname are still 3D text on the floor (the same as before); no crest bitmap yet.

## Hoop (`FcHoopBuilder`, `net.gdshader`)
- A padded stanchion, pole and support arm; a 6 x 3.5 ft glass backboard in a white frame with the 24 x 18 in shooter's square; a 10 ft rim with an 18 in inside diameter on a bracket 15 in from the board; a 5-level diamond net of lines (1.5 ft deep) that swings when a shot goes through (`swish`), done in the vertex shader. About ten draw calls per hoop. Built facing the court, the far hoop turned 180 degrees.
- A bug I made and found in the first picture: the structure was written with heights above the floor under a node at rim height, so the board floated 10 ft too high. Fixed with a structure node at the floor.

## Fixed colours
`data/ui/scene_palette.json` (`FcScenePalette`): wood, rim, glass, furniture, officials, concrete. Keeps the style lint satisfied (its baselines for `court_scene.gd` and `broadcast3d_view.gd` were lowered to match: 17 to 10 and 3 to 2).

## Tests
`tests/unit/test_ball_court_hoop.gd` (8): ball size and shader; dribble touches floor and hand in turn and is at the hand when the arm is extended; flight arc (start, end, above the line, lob higher, capped, finite); spin axis; hoop proportions (10 ft, 18 in, 6 x 3.5 ft, 15 in, board 4 ft from the baseline); the net mesh (node count, 1.5 ft depth, never wider than the rim); both hoops build facing the court and the swing is clamped; every shader loads and every palette colour parses; the scene builds with two hoops at the right places. Style lint passes. Live: 28 `broadcast` live tests passed.

## Performance (30 s, same procedure, development machine only)
avg 2.31 ms, p95 2.95 ms, p99 3.43 ms, worst 10.37 ms, none over 16.6 ms; working set 333 MB; video memory 50 MB; draw calls about 610. (Lower than M2: no large floor texture.) Limits p95 16.6 ms, p99 33.3 ms.

## Limits (honest)
- The floor has no true reflection of the players or the arena (the compatibility renderer has no screen-space reflections); it gets gloss from the lights only.
- No team logo bitmap on the court; no half-court logo artwork.
- The ball-rim interaction is a staged drop or a staged bounce, not a physics simulation; a rim that vibrates, or a ball that rolls round the rim, is not drawn.
- The net swing is a vertex wave, not cloth.
- Full unit suite not re-run in one piece for this milestone alone (targeted: ball/court/hoop 8, style lint 3, broadcast live 28); the full run is done with M4.
