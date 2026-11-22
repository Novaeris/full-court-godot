# B1c: player-model and animation prototype

Question (master plan 4.12): can convincing basketball players be produced **without external assets and without spending**, driven by the identity data the game already has, and do ten of them fit the registered budget? Date 2026-11-22. Code (throwaway, wired into no shipped screen): `prototypes/b1c/pose.gd` (`FcB1cPose`, pure animation maths), `character.gd` (`FcB1cCharacter`), `showcase.gd` (`FcB1cShowcase`, ten characters on the B1b arena). Tests: `tests/unit/test_b1c_prototype.gd` (6). Measurement: `tools/perf_benchmark.ps1 mode=b1c`. Screenshots reviewed by eye by the author (Claude); the founder has not reviewed them, so the visual judgement below is mine and is stated as such.

**Verdict: PASS for broadcast and medium distance as a stylised, code-built look; NOT good enough for close-ups.** That leads to a **3D-REDUCED** decision (section 5).

## 1. What was built
- **Identity to body (no portrait, no model file):** `FcPlayerVisual.resolve` already gives skin tone, hair style (bald, short, fade, afro, braids, locs, curly, long), hair colour, facial hair (none, stubble, goatee, beard), a build class 0 to 2, face proportions, team colours and the jersey number; height and weight come from `FcPlayerPhysical`. The character builder maps them to: body height (cm to feet), body width (weight for the height, widened by the build class), skin colour, a hair mesh per style, a facial-hair mesh per kind, a jersey and shorts in the team's primary colour with a secondary trim and shoes, and the number as 3D text on the back (large) and front (small). **2D portraits are not used**: they have no depth and cannot become 3D.
- **Body:** about 19 parts (capsules, spheres, boxes) on an 11-joint hierarchy (pelvis, torso, head, two shoulders, two elbows, two hips, two knees).
- **Animation, all procedural:** idle, run, dribble, shoot, layup, defend, with cross-fades. A state machine blends every joint linearly over 0.2 s.
- **Showcase:** ten characters, five a side, heights 178 to 221 cm, weights 74 to 128 kg, every hair style and facial hair kind, numbers 0, 1, 7, 8, 10, 12, 23, 34, 45, 99, each in a different state, half facing the sideline camera and half showing their backs.

## 2. Pass conditions (set in the plan before the prototype) and results
| Condition | Result |
|---|---|
| Silhouettes read as basketball players at broadcast distance | **Yes, with a caveat.** At the elevated sideline distance the ten figures read as players of different heights, builds and skin tones in team colours, with running, layup and defensive poses recognisable. They are small in the frame and detail is low |
| The jersey number is legible at the agreed distance | **Yes for what was tested.** Agreed distance: the broadcast preset (camera 40 ft up and 60 ft off the near sideline). Two-digit numbers (34, 45, 10) and 23 read clearly from that distance and at medium range; single digits are small. Close up (9 ft behind a player) the number is large and crisp |
| Ten characters stay inside the registered budget (at most 6 ms p95 added, 200 MB working set, 150 MB video) | **Yes.** Production scene with ten characters: average 0.90 ms, p95 1.25 ms, p99 1.41 ms (the capsule scene was 0.50 ms and 0.76 ms): about 0.5 ms added at p95. Working set 227 MB settled (capsule scene 202 MB): +25 MB. Video 31 MB (+5 MB). Draw calls 719 against 145: about 57 per character (many small parts), 817,000 primitives. Camera run 0.84 ms average. Leak check: orphans 0 after every exit, working-set growth 1 MB (limit 10) |
| Blend artifacts recorded and acceptable | **Yes, after two defects were found and fixed** (section 3) |
| Effort per animation and per body type recorded | Section 4 |

## 3. Blend artifacts (measured, not judged by eye)
The unit tests blend every state into every other from four starting phases over 12 frames (0.2 s at 60 fps) and require that no joint turns more than 0.6 rad in one frame, that each looping state closes its loop (start equals end) and that no joint turns more than 0.42 rad between hundredths of a loop. **They found two real defects, both fixed:** the `shoot` loop did not return to its ready position (elbows 1.6 rad apart, torso 0.1 rad), so wrapping from the end of the loop to the start popped, and every blend out of a late `shoot` phase popped with it. The run's stride is 1.3 body heights per loop for every body, so the feet do not slide for tall or short players (about 12 ft/s for a 6.5 ft player, under the reconstruction's 22 ft/s limit). Not measured: foot contact against the floor during `dribble`, `defend` and `layup`, and ball-in-hand alignment (the dribbled ball bounces from the hand's height approximately).
Other defects found by measurement: the first leak run showed orphan nodes growing by one per cycle (a prototype ball created and never added to the tree); fixed and re-measured.

## 4. Effort record (engineering cost versus asset cost)
- **Asset cost: zero.** No model, texture, animation clip, font or audio was bought, downloaded or licensed. Everything is built in code from primitives; the number uses the engine's default font.
- **Engineering cost (this prototype):** the pose maths about 150 lines (six animations, about 15 to 35 lines each, written and corrected in one pass plus two fixes found by the tests), the character builder about 280 lines (body, 8 hair styles, 3 facial-hair kinds, uniform, number, joint hierarchy, state machine), the showcase about 120 lines. A new animation is about 20 to 30 lines of joint formulas plus a blend test; a new body type is data (height, weight, build) and costs nothing; a new hair style is 5 to 15 lines.
- **What this approach cannot do** and a hand-made asset pipeline would be needed for: faces and expressions, hands that grip the ball, cloth, a neck and shoulders that read as anatomy, motion-captured realism, and any look beyond "stylised mannequin".

## 5. Honest visual judgement and the 3D decision
At **broadcast and medium distance** the result is a clean, readable, stylised look and the identity data visibly drives it. At **close range** (head and shoulders) it is plainly a blocky toy figure: a blank sphere head, no neck, a box for shorts, blob hands. A premium television look at close range is **not** achievable with this approach and would need hand-made assets, which D-069 does not allow without spending.

**Decision (D-069, plan 12.9): 3D-REDUCED.** B1 passed, B1b passed, B1c passed its written conditions, but only at broadcast and medium distance. B4 therefore proceeds with a reduced scope:
- 3D cameras are limited to the broadcast (elevated sideline), wide and medium presets; **no 3D close-up preset**. Close-ups, player introductions and lower thirds keep using the existing 2D portrait cards over the 3D picture.
- Characters are the stylised code-built ones; the 2D replay remains selectable and is the automatic fallback.
- Jersey numbers on 3D uniforms use **display numbers assigned per game** (a pure, deterministic assigner, no saved data), not stored tenure numbers (decision recorded with B4): the full J1 migration is not undertaken now.

## 6. Limits
Measured on the development machine only. The prototype's motion is scripted, not driven by the reconstruction (B4 does that). No collision handling beyond the reconstruction's own spacing. No cloth, no face, no hand-ball interaction.
