# 3D visual fidelity and basketball authenticity: audit, recommendation and milestone plan

Written 2026-11-23. Scope: the 3D broadcast view (D-070, 3D-REDUCED, `src/ui/broadcast3d/`). Simulation, saves and the 2D/mobile paths are not touched.
Baseline pictures: `docs/validation/3d_overhaul/m0/` (made by `tools/character_showcase.gd`, the real arena lighting, five archetypes).

## Phase 0: audit (what exists today)

| # | Area | Finding | Verdict |
|---|---|---|---|
| 1 | Player model generation | `FcBroadcastCharacter` builds every body in code from `FcPlayerVisual.resolve` (skin, hair, facial hair, build class 0-2, height, weight, uniform colours, number). About 25 MeshInstance3D parts per player. | **Replace the body, keep the class API** (setup, set_state, advance, hand_position, height_feet, width_scale, identity). |
| 2 | Procedural meshes | Only Godot primitives: capsules (10 sides, 3 rings), spheres, boxes. Faceted limbs, boxes for shorts and shoes, a sphere for a head, no face at all. | Replace with lofted, smooth, skinned meshes. |
| 3 | Imported character assets | None. `assets/` holds brand, fonts, icons and shaders only. No GLB, no glTF. | Nothing to reuse. |
| 4 | Skeleton and rigging | No `Skeleton3D`. A hierarchy of Node3D "joints", 11 of them (pelvis, torso, head, 2 shoulders, 2 elbows, 2 hips, 2 knees). No neck, wrists, ankles, spine split, clavicles or fingers. | Replace with a real `Skeleton3D` (about 24 bones) with a skinned mesh. |
| 5 | Animation library, AnimationTree | No `AnimationPlayer`, no `AnimationTree`. `FcBroadcastPose` is pure maths: 6 states (idle, run, dribble, shoot, layup, defend), each a function of a loop phase, cross-faded by linear interpolation of euler angles. Well tested (no popping). | **Keep the architecture** (pure, testable, deterministic, no asset files). Extend the states and joints; add IK and ground contact on top. An AnimationTree would need authored clips we do not have. |
| 6 | Proportions and archetypes | One body for everyone: only height, a width factor from weight and the build class (0-2) change. Position is not used. | Add an archetype layer: height, wingspan, shoulder width, chest depth, muscle, leg length, head size, neck, hand size. |
| 7 | Face and hair | Head is a scaled sphere. No eyes, nose, mouth, ears. Hair is 1 to 7 spheres. Facial hair is a tinted sphere. The 2D proportions (`face_w`, `jaw`, `brow`, `nose`...) are in the identity but unused in 3D. | Rebuild: a parametric head with jaw, brow, nose, ears, eyes, mouth; real hair shapes. Use the 2D proportions. |
| 8 | Uniform | A box for the shorts, a capsule coloured like the jersey, boxes for shoes, `Label3D` for the number. No jersey cut, trim, socks. | Rebuild: jersey with armholes, neckline and trim, shorts with side stripe, socks, shoes with soles. |
| 9 | Basketball | A plain orange sphere (radius 0.45 ft; real ball is about 0.39 ft). Teleports to the holder's hand, no spin, no bounce, no dribble. | Rebuild (size, pebble and channel texture, dribble, spin, flight arc). |
| 10 | Court and hoop | Court is a 10 px/ft texture of flat boxes: no wood grain, hard-edged pixel lines, three-point arc made of squares, no logos. Hoop: box pole, box backboard, a thin torus rim, no net. Rim is 10 ft but the pole stands wrong; backboard 6 x 3.5 ft (real 6 x 3.5, ok). | Rebuild texture (grain, planks, sharp lines, logo), the hoop (stanchion, padded base, backboard with square, rim, net that moves). |
| 11 | Arena and lighting | 16 stepped tiers of flat boxes, 4 LED boards, 4 spotlights, one shadowed sun, benches as boxes, no officials, no scorer's table, no coaches. | Improve in M5. |
| 12 | Crowd and MultiMesh | One MultiMesh of 6,000 camera-facing coloured cards animated in `crowd.gdshader` (colour per fan from `FcCrowdPlan`). Excellent cost (about 0.04 ms), poor look (flat rectangles). | **Keep the architecture**; upgrade the card (a painted fan sprite in the shader: head, torso, arms) and the variation. |
| 13 | Creator Studio customization | Studio edits the same categorical appearance (skin, hair, face, facial hair) and the build rules. The 2D portraits and figures read it. | Compatible by design: the new 3D pipeline reads the same `FcPlayerVisual.resolve` result. No new stored data. |
| 14 | Performance | M8 numbers: avg 3.3 ms, p95 4.4 ms, p99 5.2 ms at 1080p (limit 16.6 / 33.3), 302 MB working set, 55 MB video memory, 1441 nodes, about 850-900 draw calls (RTX 4060 only). | Large headroom. Budget: characters may use up to about 3 ms more. Re-measure every milestone. |

### What I could and could not do
- **Blender is not installed** on this machine and nothing can be exported from it here. Hand-modelled glTF characters are therefore not an option today.
- **No licensed or third-party art is used.** Everything is original and generated.

## Technical recommendation

**Generate the characters as skinned meshes from code** (a "parametric body kit"), keeping the code-only, deterministic, offline and original-IP stance already chosen in D-070. Concretely:

1. One shared **skeleton definition** (about 24 bones, Godot `Skeleton3D`) with bone lengths set by the archetype.
2. One **body builder** that lofts smooth cross-section rings along bone chains into a single skinned `ArrayMesh` (torso, arms, legs, hands with fingers) and builds a parametric head, ears, hair, facial hair, jersey, shorts, socks and shoes as extra surfaces. Bones and weights are written at build time (4 per vertex).
3. An **archetype** record (pure, tested): derived only from `FcPlayerVisual.resolve` + height + weight + position, never random, never stored.
4. **Pure animation maths stays** (`FcBroadcastPose`), extended with new states and joints; a pure two-bone **IK** solver puts the hand on the ball, and a **ground-contact** pass keeps the lower foot on the floor.
5. **Blender and glTF**: evaluated, not adopted now. The skeleton, bone names and surface order are designed so authored GLB parts (heads, hair, shoes) can replace the generated ones later without touching data, Creator Studio or saves.

Why not an AnimationTree: it needs authored clips; we have none and no tool to make them. The pure-maths poses are deterministic and unit-testable, and the cross-fade is already proven.

## Milestones (each: scope, tests, screenshots, benchmark, docs, commit and push)

| M | Scope | Acceptance |
|---|---|---|
| M0 | Audit, plan, showcase tool, baseline pictures | This document and `docs/validation/3d_overhaul/m0/` |
| M1 | Character v2: archetypes, skeleton, skinned body, head, hair, uniform | Showcase shows 5 distinct archetypes (front, side, three-quarter) in game lighting; existing character tests still pass; new tests for archetype maths and mesh validity |
| M2 | Animation: more states, neck/wrist/ankle, IK for the ball hand, ground contact | New states valid and non-popping (same tests extended); hand within 0.15 ft of the ball when dribbling; no foot below floor |
| M3 | Ball, court, hoop | Ball textured with spin, dribble and flight; court with grain, crisp lines, logo; hoop with net |
| M4 | Arena | Seating variation, courtside, scorer's table, officials, coaches, better crowd card, per-arena identity |
| M5 | Broadcast integration | Camera framing, intros and celebrations use the new characters; 28 ft minimum (D-070) still enforced by tests |
| M6 | Validation | Performance matrix (1, 10 players, full arena, replay camera, resolutions, soak), determinism, mode checks, mobile 2D fallback |

Rules for every milestone: the simulation is not changed (the 3D view only reads events), determinism tests must stay green, `FcBroadcastCharacter`'s public API stays compatible, and the full suite (`tools/run_tests.ps1`) must pass before the commit.
