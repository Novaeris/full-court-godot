# Production Phase M1: professional player visuals, final report

Date: 2026-11-24. Decision: D-074. Status: **M1.0 to M1.7 complete; M1.8 complete except the one step reserved for the founder (promotion to the default look).**

## Executive summary
The 3D players were mannequins: lofted tubes, a tube jersey, mitten hands, a bare face. M1 built a Blender production kit and a library of production players: three body types with fingers, 18 swappable heads with nose, lips, brow and eye variants, seven hair styles, facial hair, a headband, a real basketball uniform (armholes, scoop neckline, trim, shorts, socks, shoes), and the number, surname and team wordmark printed by a shader. Every piece is chosen from the identity the game already has (`FcPlayerVisual.resolve()`), so a player looks the same in every mode, and the same 3D model now also renders portraits. It is fully integrated, tested and verified on a clean machine in CI, and is opt-in until the founder approves the art direction.

## Milestones
| Milestone | Result | Commit |
|---|---|---|
| M1.0 audit and art direction | `docs/development/PLAYER_VISUAL_SPEC.md`, baseline pictures (`before_procedural/`, `before_proto/`) | ca73803 |
| M1.1 to M1.5 head and face, body and hands, hair, clothing and branding, game integration | `tools/blender/fc_character/`, `tools/blender/basketball/`, `build_player_m1.py`, `FcPlayerAssetLibrary`, `FcHandPoses`, `FcJerseyGraphics`, `jersey_cloth.gdshader`, part validator, CI | e899bd7 |
| M1.6 to M1.7 portraits and real-game validation | `FcPlayerRender`, screens, benchmarks, comparisons, contact sheet | e036d62 |
| M1.8 final review | fixes (cloth seen from inside, shorts fit, hem trim, neck), finger-on-ball test, one-flag promotion, this report | this commit |

## Quality gates (revised gates from the founder brief)
| # | Gate | Verdict | Evidence |
|---|---|---|---|
| 1 | Visibly better than the procedural player | Met in our judgement; **the founder decides** | `compare_*.png`, `compare_replay_*.png` |
| 2 | Believable and distinctive faces and bodies | Met at broadcast and portrait distance; close-ups remain stylised | `portraits.png`; 200 similar players give at least 150 distinct looks (test) |
| 3 | All hairstyles, facial hair and accessories | Met: 8 hair values x 4 facial values all attach (test); headband | `test_every_hair_and_facial_hair_style_attaches` |
| 4 | Uniforms, branding, numbers, colours | Met: team colours, trim in the secondary colour, number front and back, surname, wordmark; Label3D fallback without a renderer | `after_library/`, `game/` |
| 5 | All 34 states incl. ball interaction and hand poses | Met: contact sheet of all 34 states; fingers stay on the hand in every state and lie on the ball surface (0.65 to 1.3 radii) in every two-hand grip | `poses/`, tests |
| 6 | Same identity data in every mode | Met: one resolver, deterministic spec, portraits from the same model in Owner, Career and Dynasty screens; Studio smoke passes | `game/*_profile.png`, tests |
| 7 | Performance in full 5v5 with arena and crowd | Met on the development machine (about +2 ms per frame, no frame over 16.6 ms). Not measured on lower-end hardware | `PERFORMANCE.md` |
| 8 | Tests, asset validation, screenshots | Met: unit and live suites pass (totals in `docs/TESTING.md`), project validator 0 problems, CI rebuilt and validated the players on a clean machine | GitHub Actions "Player pipeline" runs |

## Customisation and animation demonstrations
- Customisation: `after_library/front.png` (five archetypes: fade, braids with stubble, short with goatee and headband, bald with beard, afro), `portraits.png` (twelve generated players, four teams).
- Animation: `poses/pose_sheet_0.png` to `pose_sheet_5.png` (all 34 states on the library player), `game/replay_*.png` (the real replay screen).

## Known limitations (honest)
- Forms are sculpted by script, not by hand: faces are clean and readable but stylised; no texture painting, no normal maps beyond a cloth weave.
- Cloth has no simulated folds; hair is solid shapes (no strands or cards).
- Two bones per finger; poses are data, not motion capture.
- Each head part and hair is its own mesh, so draw calls rise about 45%. Merging a player's parts at attach time is the first optimisation if a weaker device needs it.
- Portraits from the 3D model replace the 2D figure only where the shared figure drawing is used, and only when enabled.

## The one remaining decision (founder)
Approve the art direction, then set `"promoted": true` in `data/player_pipeline/asset_library.json`. That single flag makes the library players the default in the replay and turns on 3D-rendered portraits; the generated body stays the fallback. Until then everything is opt-in (`model = "library"`, `render3d=1` in the screenshot tool).

## Recommended next milestone: M2 Basketball Animation Production
Authored motion for the most visible actions (jump shot, dribble moves, layup, dunk, rebound, defensive stance) on the library rig, played through the existing clip pipeline (`docs/development/PLAYER_ANIMATION_PIPELINE.md`), with finger poses keyed to the ball, and the same test, CI and picture gates as M1.
