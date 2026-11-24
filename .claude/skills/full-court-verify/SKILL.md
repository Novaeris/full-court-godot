---
name: full-court-verify
description: How to verify a change to Full Court the way this repository requires (import, unit, live, Creator Studio, style lint, pictures, benchmarks). Use before reporting any code change as working, and when a test run behaves oddly.
---

# Verifying Full Court changes

Never say something works until you have run the relevant check and read its result. State what was and was not verified.

## The commands (Windows, run from the repository root)
- Register new `class_name` files first: `godot_console --headless --path . --import --quit`
- One test file or a group: `godot_console --headless --path . --script res://tests/run_tests.gd -- --filter=name` (unit) and `res://tests/run_live_tests.gd -- --filter=name` (live: needs a scene tree, so uses frames).
- The whole unit suite is about 1,700 tests and takes MANY minutes. Run it in the background to a file and read the summary line (`Tests: N passed, M failed`): `(nohup godot_console --headless --path . --script res://tests/run_tests.gd > out.txt 2>&1 &)`. Output is buffered until the end, so an empty file means "still running", not "hung". Do not edit source files while it runs.
- Creator Studio: `godot_console --headless --path creator_studio --import --quit` then `... --script res://tools/studio_smoke.gd` (expects `Studio smoke: PASS`).
- Project validator (scripts compile, scenes and resources load, GLB players are valid): `godot_console --headless --path . --script res://tools/validate_project.gd` (exit 0 = clean).
- Simulation sanity: `tools/simulate_games.gd -- games=300 seed=2026 strict=1`.

## Rules of this repository (CLAUDE.md is the full list)
- The `ui_style` lint counts every `Color(` literal in `src/ui`. New colours go in a data file (`data/ui/*.json`) read through a palette class, or the baseline in `tests/support/ui_style_baseline.json` must be LOWERED when literals are removed (a stale high baseline fails a second test).
- Simulation code never touches UI; all randomness goes through `FcRng`; never change a saved shape without bumping `FcVersion.DATA_VERSION` and adding a migration.
- Every new system ships with tests; use fixed seeds.
- Godot facts that cost time before: the front face of a triangle is CLOCKWISE; `Skeleton3D.get_bone_global_pose` is stale until the skeleton refreshes (use the forward-kinematics helper in `FcBroadcastCharacter`); Godot re-enables `_process` when a node enters the tree whatever `set_process(false)` said (use the `auto_advance` flag).

## Seeing the result
- Pictures of characters, court and hoop: `godot_console --path . --script res://tools/character_showcase.gd -- out=docs/validation/...` (opens a window), animation contact sheets with `poses=1`.
- The real replay screen: `godot_console --path . --script res://tools/screenshot.gd -- screen=owner_replay mode=broadcast shot=celebration out=file.png`. Read the PNG to look at it.
- Speed: `tools/scene_benchmark.gd` (scaling) and `tools/perf_benchmark.gd -- mode=replay3d run=standard seconds=30` against the limits in `docs/validation/PERFORMANCE_THRESHOLDS.md`. Run them alone: other Godot processes distort frame times.

## Shell gotchas in this environment
- A bash heredoc that contains an apostrophe can fail to parse; write such files with the Write tool.
- `git` warns about CRLF/LF on Windows: harmless.
