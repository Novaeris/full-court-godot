# Master player baseline (D-076): report

Date: 2026-11-26. The Full Court player is now ONE master Blender file, `art_source/players/fc_master_player.blend` (Git LFS), improved in recorded
passes and exported by script. Status: the baseline is built, integrated and verified in the game; it becomes the default look only with the founder's
approval (`"promoted": true` in `data/player_pipeline/asset_library.json`).

## Phases
| Phase | Result | Evidence |
|---|---|---|
| 1 Protect the master | master file in `art_source/players/` (LFS, `.gdignore`), component collections (rig, body, head, uniform, shoes, hair, facial, equipment), versioned backups in `versions/` before every pass, read-only export with a checksum guard, `create_master.py` refuses to recreate it | `art_source/README.md`, `p1/` |
| 2 Anatomy | athletic baseline baked into the master: V-shape, chest, back, arms, legs, neck, trimmer waist | `p2/` |
| 3 Face | hero face baked (chin, jaw line, nose, lips, hooded eyes, longer face); per-player variation scaled to 0.5 so the master face carries through | `p3/` |
| 4 Hair | hair and facial-hair density softened in the master: smooth fades, soft beard edges (a scalp-sink attempt was rejected and rolled back from its backup) | `p4/` |
| 5 Uniform and equipment | the jersey hangs from the chest with vertical folds and bridges the chest hollows; straight wide shorts; side panels with piping from an exact distance field (straight edges); two-tone basketball shoes from accent zones painted in the master | `p5/`, `p6/godot/shoes.png` |
| 6 Rig and deformation | jersey top bound to chest and shoulders from torso skin only (arm raises lift the cloth cleanly; a first attempt that spiked the cloth was rolled back); arm-raise and crouch views added; contact sheet of all 34 states | `p6/` |
| 7 Export pipeline | `tools/blender/master/export_and_check.ps1`: export, import, validate, tests, Blender and game approval renders in one command; test that the game files come from the master and record its passes | `p8/` |
| 8 Godot validation | eleven standard views in the real renderer, the replay, Owner, Career and Dynasty profiles; five-way comparison with every previous version | `compare/`, `p8/game/` |
| 9 Roster | every player is the master plus deterministic morphs, hair, facial hair, equipment and kit; showcase and portraits | `p9/` |

## Performance (development machine)
Real replay (5v5, arena and crowd, 25 s): 6.6 ms average, p95 9.7 ms, worst 20.6 ms, no frame over 33 ms. Each new player is baked once while the
replay opens (about 35 ms, the engine's morph bake); LOD index lists are computed once and shared by every player (2 ms instead of 55 ms), and
players seen before come from the cache.

## Honest assessment against the visual bar
Clearly met: believable anatomy and proportions, a basketball uniform that hangs and has panels, piping, printed name and numbers, two-tone basketball
shoes, smooth fades, clean deformation of the jersey when the arms rise, consistent identity across every mode.
Not yet at a AAA close-up standard: the face is a refined MakeHuman face with shader skin (no hand-sculpted pores or micro detail); hair is shell
geometry with a density shader; cloth folds are shaped, not simulated; the jersey hem shows a small notch between the legs in a deep crouch. These are
the places where a 3D artist working on the same master file gives the largest gain; the pipeline accepts their work unchanged (open the master,
sculpt, save through a backup, run `export_and_check.ps1`).

## Decision for the founder
Approve the baseline (set `"promoted": true`) or name what to change next; every further pass is a recorded, reversible edit of the master.
