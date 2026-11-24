# 3D overhaul, M6: performance and validation

Written 2026-11-24. Machine for every number: AMD Ryzen 7 8700F, NVIDIA RTX 4060, gl_compatibility, vsync off, Godot 4.7.2. **Nothing was measured on a weaker or integrated GPU, a laptop, or another operating system.**

## Scene scaling (`tools/scene_benchmark.gd`, 400 frames each, broadcast camera, everything animated)
First run (every character updated every frame), then after the bench and coaches were moved to 20 updates a second (`SCENERY_STEP`):

| Case | avg ms | p95 | p99 | worst | draw calls |
|---|---|---|---|---|---|
| arena only, no crowd | 1.02 | 1.44 | 1.69 | 1.81 | 235 |
| 1 player | 1.10 | 1.49 | 1.70 | 1.91 | 263 |
| 10 players | 2.31 | 2.79 | 3.04 | 3.10 | 515 |
| 10 players + crowd 6000 | 2.52 | 3.15 | 3.46 | 3.61 | 520 |
| 31 characters (10 on court, 16 bench, 3 referees, 2 coaches), first run | 5.41 | 6.18 | 6.35 | 6.65 | 1103 |
| FULL: 31 characters + crowd 6000, 1080p, first run | 5.31 | 5.90 | 6.24 | 7.02 | 1108 |
| FULL after the 20 Hz scenery change | 3.42 | 6.38 | 7.05 | 7.92 | 1108 |
| stress: crowd 12000 after the change | 3.66 | 5.68 | 7.02 | 8.00 (one frame 17.4 ms in the first run) | 1108 |
| FULL at 1280x720 / 2560x1440 after the change | 3.66 / 4.41 | 5.07 / 8.13 | 5.89 / 9.49 | 6.89 / 10.32 | 1108 |

What it shows: the crowd costs almost nothing (6,000 fans add about 0.2 ms); cost grows with the number of animated characters, roughly 0.15 ms each on the CPU (the skeleton is posed in GDScript every frame) and eight draw calls each. Moving the bench and coaches to 20 updates a second cut the average by about a third; the p95 did not fall because a frame that carries the batch update is slower than its neighbours.

## Replay screen (`tools/perf_benchmark.gd mode=replay3d`, the 521-event benchmark game; limits: p95 16.6 ms, p99 33.3 ms, at most 1% of frames over 33.3 ms, working set 2,048 MB, video 1,024 MB)
| Run | avg | p95 | p99 | worst | over 16.6 ms | working set | video | nodes / orphans |
|---|---|---|---|---|---|---|---|---|
| standard, 30 s | 2.92 | 4.01 | 5.02 | 13.14 | 0 | 340 MB | 61 MB | 668 / 0 |
| fast 4x, 30 s | 2.66 | 3.66 | 5.91 | 12.54 | 0 | 341 MB | 60 MB | 668 / 0 |
| camera sweep, 30 s | 2.44 | 3.16 | 4.41 | 11.68 | 0 | 340 MB | 63 MB | 668 / 0 |
| soak, 300 s | 2.99 | 6.78 | 6.96 | **283.48** | 7 of 100,307 (0.01%) | 342 MB | 58 MB | 668 / 0 |

**The soak has one 283 ms hitch** and a second frame over 33.3 ms (2 of 100,307, 0.002%, under the 1% limit). I did not find the cause (the working set was flat, so it does not look like growth); an operating-system or driver stall on the development machine is the likeliest explanation but this is a guess. It is recorded, not explained. The soak was 300 s, not the 600 s of the procedure.

Leak check, 10 enter and exit cycles: working set after the first exit 329 MB, worst after any exit 331 MB, **growth 2 MB (limit 10 MB)**, nodes back to 1 and 0 orphans after every exit, video and engine static memory constant. This is a clean pass, unlike M5 of Broadcast pass 2.

## Determinism and the modes
- The simulation, event log and saves were not changed by any milestone. `FcBroadcast3DView` only reads the replay model and reconstruction; the live tests that prove rows and box scores are byte-identical after use still pass.
- Unit suite: **1,683 passed, 0 failed**. Live suite: **240 passed, 0 failed**. Creator Studio smoke: **PASS**.
- `tools/simulate_games.gd games=300 seed=2026 strict=1`: exit 0, 0 of 16 checks outside the realistic range (team rating and win percentage correlation 0.73). `tools/dynasty_check.gd`: exit 0. `tools/career_playthrough.gd seasons=5 seed=7`: 0 problems. Owner Mode is covered by the unit and live suites and the simulation run; `owner_stress`, `economy_check`, `ui_playthrough` and `career_balance` were not re-run (nothing in their code changed).

## Mobile 2D fallback
A phone-size replay screen no longer builds the 3D view at all (D-030). Proof: `test_a_phone_keeps_the_2d_replay_and_never_builds_3d` (no 3D view, the 2D court in every mode, seeking and introductions still work) and `m6/phone-2d-fallback.png` (a 412 x 915 layout). The forced-failure 2D fallback test for desktop (`FcBroadcast3DView.force_failure`) still passes. **Not tested on a real phone or the Android emulator.**

## Pictures
`COMPARISON_before_after.png` (M0 against M4 showcase), `COMPARISON_replay_screen.png` (the replay screen at the end of Broadcast pass 2 against now), `m6/broadcast-1920x1080.png`, `m6/broadcast-2560x1440.png`, and every milestone folder `m0` to `m6`.
