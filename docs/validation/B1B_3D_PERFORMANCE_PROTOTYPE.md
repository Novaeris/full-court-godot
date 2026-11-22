# B1b: minimal 3D performance prototype

Question (master plan 4.12a): can a 3D basketball presentation run inside the hardware budget with the project's `gl_compatibility` renderer? Limits were committed **before** any 3D measurement in [PERFORMANCE_THRESHOLDS.md](PERFORMANCE_THRESHOLDS.md) (commit `baa3a43`); the results below are judged against exactly those values. Date 2026-11-22. Code: `prototypes/b1b/arena_prototype.gd` (`FcB1bArena`, throwaway, wired into no shipped screen); measurement: `tools/perf_benchmark.ps1 mode=3d`.

**Verdict: PASS on this machine, for the production configuration (shadow-casting light, instanced crowd, viewport scoreboard). That is a rendering-budget result only: the scene has placeholder capsules, no player models, no animation and a plain arena.** It says nothing about weaker hardware (this machine: Ryzen 7 8700F, RTX 4060, 31.6 GB, 1920 x 1080 window, vsync off) and nothing about mobile (out of scope, D-030).

## What the prototype contains (and nothing more)
One court (a 94 x 50 ft plane with a procedurally drawn texture, two hoops), **ten placeholder players** (capsules, two team colours, scripted motion), one ball (scripted flight), one `Camera3D`, a basic arena (16 stepped tiers on four sides, courtside LED boards), **one shadow-casting directional light** plus ambient light, an **instanced crowd** (one `MultiMesh` of camera-facing cards with a colour each, about 6,000 instances; seated and standing are two heights and one section at a time stands at event times) and a **scoreboard** that shows a live `SubViewport` texture updated once a second. Built entirely in code, no assets. A screenshot was checked by eye: the scene renders as described (court, players, crowd, boards, the scoreboard's shadow).

## Results against the pre-registered limits
| Limit | Value | Measured (production configuration) | Result |
|---|---|---|---|
| Frame time p95 | at most 16.6 ms | 0.76 ms (standard), 0.62 (fast), 0.62 (camera), 0.62 (soak) | pass |
| Frame time p99 | at most 33.3 ms | 0.88, 0.70, 0.70, 0.70 ms | pass |
| Frames over 33.3 ms | at most 1% | 1 of 237,778 in the standard run (0.0004%), none in the other runs | pass |
| Total application memory | at most 2,048 MB | working set 202 MB settled, up to 280 MB at the end of the standard run, 219 MB after the 300 s soak | pass |
| Additional 3D-viewer memory | at most 1,024 MB | the scene alone is 202 MB settled against 218 MB for the 2D replay screen (so none beyond the 2D UI); against the empty engine (M0, 177 MB) it adds 25 MB settled and 103 MB at the peak | pass |
| GPU memory (engine video memory) | at most 1,024 MB | 26 MB settled, 30 to 32 MB at the end of runs | pass |
| Leak check, 10 enter/exit cycles | growth at most 10 MB, nodes back to 1, orphans 0 | 205 MB after the first exit, worst 213 MB, **growth 8 MB**; back to 205 MB after the tenth; nodes 1 and orphans 0 after every exit | pass (close to the limit) |
| Load time | at most 5 s | 35 ms after the request in a warm run; **2,117 ms** in the first, cold-cache run (the engine compiling shaders) | pass |

Frame-time runs: standard 237,778 frames, average 0.50 ms (1,981 fps); fast 124,468 frames, 0.48 ms; camera 124,592 frames, 0.48 ms; soak 624,445 frames over 300 s, 0.48 ms. For comparison the 2D replay averaged 1.09 ms in the same procedure: the 3D prototype is cheaper because it is almost all GPU work on a few draw calls, while the 2D replay is many small Control draws.

**Things that were not clean and are not hidden:** one 176.67 ms frame in the standard run and a 28.49 ms frame in one element run (single hitches, causes not identified; the run's p99 was unaffected); the working set grew from 202 MB to 280 MB during that first standard run and was 219 MB after the soak, so memory is not perfectly steady and should be watched in B4; the leak growth is 8 of 10 MB allowed.

## Per-element costs (diagnostic, 30 s each; the pre-registered pass rule does not use them)
| Configuration | Average frame | Draw calls | Primitives | Note |
|---|---|---|---|---|
| Production (crowd 6,000, shadows, viewport scoreboard) | 0.50 ms | 145 | 202,020 | |
| No crowd | 0.46 ms | 140 | 142,020 | the crowd costs about 0.04 ms for 6,000 cards (60,000 primitives) |
| Crowd requested at 20,000 | 0.48 ms | 145 | 219,020 | only 7,700 were placed (the stands hold that many at this spacing); a larger crowd needs more tiers |
| No shadows | 0.32 ms | 47 | 59,352 | the shadow-casting light costs about 0.18 ms and about 98 draw calls |
| Static scoreboard instead of the live texture | 0.47 ms | 145 | 202,020 | the live `SubViewport` costs about 0.03 ms |

## Decisions (D-069)
- **Crowd technique:** one instanced `MultiMesh` of billboard cards with per-instance colours, a few draw calls whatever the count, works under `gl_compatibility`. State changes (seated or standing) by section at event times work and cost nothing measurable. The assumption "instancing works under gl_compatibility" is **confirmed**.
- **Live scoreboard texture:** affordable (0.03 ms); the static alternative is not needed.
- **Shadows:** one shadow-casting directional light is affordable; shadow quality stays a setting.
- **Budgets registered for B1c and B4 (set now, before they are measured, as fractions of the pre-registered limits and not from this machine's headroom):** the ten characters with their animation may add at most **6 ms** of frame time at p95 (the scene above uses 0.5 ms, the limit is 16.6 ms), at most **200 MB** of working set and **150 MB** of video memory; the whole viewer must still meet every limit in `PERFORMANCE_THRESHOLDS.md`. Draw calls and primitives stay diagnostic.

## What this does and does not settle
It settles that the **rendering architecture is viable** on a modern desktop GPU with this renderer. It does not settle: whether production-quality characters, animation and a branded arena stay inside the limits (B1c and B4 measure that), behaviour on integrated or older GPUs (not measured), or the single hitches above. The overall 3D decision needs B1c.
