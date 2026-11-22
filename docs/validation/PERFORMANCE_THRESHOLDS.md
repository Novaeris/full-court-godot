# Performance thresholds (pre-registered before any 3D measurement)

This file is committed **before** the 3D prototype (B1b) or any later 3D viewer is measured. The commit that adds it is the pre-registration. The limits below are the ones every 3D result is judged against; changing one later needs a separate commit with written reasons, and the original verdict stays in the report (master plan 12.9, item 4). Procedure: master plan 4.7.1 and 4.7.2. Tool: `tools/perf_benchmark.ps1`.

## 1. The machine (the only machine measured)
| | |
|---|---|
| CPU | AMD Ryzen 7 8700F, 8 cores / 16 threads, up to 4.1 GHz |
| GPU | NVIDIA GeForce RTX 4060, driver 32.0.16.2124 (Windows reports 4,095 MB adapter RAM because that field is capped at 32 bits; the card has 8 GB dedicated, which is assumed below) |
| RAM | 31.6 GB |
| Storage | NVMe SSD |
| OS | Windows 11 Home build 26300 |
| Display | 2560 x 1440 at 144 Hz; the benchmark opens a **1920 x 1080 window**, **vsync off** (so a frame's time is its true cost, not the monitor's refresh interval) |
| Engine | Godot 4.7.2 stable, renderer `gl_compatibility` |

**This is the development machine and it is far stronger than a lower-end player's PC.** No claim is made that a result here holds on weaker hardware. Mobile 3D is out of scope (D-030).

## 2. The benchmark
- **Fixed benchmark game:** found by scanning simulation seeds upward from 1 for the first game that goes to overtime and has free throws and substitutions: **seed 1**, 521 events, 2 overtimes, PHI at STL in the 4-team test league (generation seed 31415). It is not chosen after looking at performance.
- **Runs (durations are shorter than the plan's proposal because they are automated here; the choice is made now, not after seeing results):**
  | Run | What | Duration |
  |---|---|---|
  | standard | 1x, automatic camera, the benchmark game looping | 120 s |
  | fast | 4x | 60 s |
  | camera | a scripted sweep: a different manual camera every 5 s | 60 s |
  | soak | standard, to expose slow growth or throttling | 300 s |
  | leak | 10 cycles: enter the replay, play 15 s, exit, settle 5 s; memory after each exit | 10 cycles |
- **Measured:** frame time (average, median, p95, p99, worst, share of frames over 16.6 ms and over 33.3 ms), the process working set (operating system), the engine's static memory, node and orphan-node counts, the engine's video memory (texture and buffer), draw calls and primitives.
- **Memory measures kept separate:** (a) total application = process working set; (b) additional memory of the 3D viewer = working set with the 3D viewer minus the 2D replay at the same settled point; (c) GPU memory = the engine's `RENDER_VIDEO_MEM_USED` (the card is a dedicated-memory GPU).

## 3. The 2D baseline (measured 2026-11-22, same machine and procedure)
| Run | Frames | Average | p50 | p95 | p99 | Worst | Over 16.6 ms | Over 33.3 ms |
|---|---|---|---|---|---|---|---|---|
| standard 120 s | 109,874 | 1.09 ms (916 fps) | 0.59 | 2.72 | 4.24 | 13.48 | 0 | 0 |
| fast 60 s | 23,765 | 2.52 ms | 2.33 | 4.02 | 4.75 | 11.11 | 0 | 0 |
| camera 60 s | 55,248 | 1.09 ms | 0.60 | 2.48 | 4.11 | 9.24 | 0 | 0 |
| soak 300 s | 259,070 | 1.16 ms | 0.59 | 3.90 | 4.19 | 11.37 | 0 | 0 |

| Memory | Value |
|---|---|
| M0 (league and game generated, no replay screen) | working set 176 MB, engine static 40 MB, video 21 MB |
| **M2D** (replay screen settled) | **working set 218 MB**, engine static 56 MB, 119 nodes, video 24 MB (texture 17, buffer 6), 171 draw calls, 6,590 primitives |
| soak end | working set 223 MB (+5 MB over 300 s) |
| leak control (10 enter/exit cycles of the 2D replay) | working set 213 to 214 MB after every exit, **growth 1 MB**, nodes back to 1, orphan nodes 0 |

The 2D benchmark also found and removed an engine error (a degenerate polygon logged every frame by the broadcast view's centre circle, fixed with a regression test).

## 4. The limits (derived from fixed rules; the numbers are filled in from section 3)
| Limit | Rule | Value for the 3D viewer |
|---|---|---|
| Frame time p95 | at most 16.6 ms | **16.6 ms** |
| Frame time p99 | at most 33.3 ms | **33.3 ms** |
| Slow frames | frames over 33.3 ms at most 1% | **1%** |
| Total application memory | at most 25% of an **assumed 8 GB** machine, whatever this machine has | **2,048 MB** working set |
| Additional 3D-viewer memory | the total limit minus M2D, rounded down to 50 MB, at most 1 GB | 2,048 - 218 = 1,830, so **1,024 MB** (the 1 GB cap applies) |
| GPU memory | the smaller of 1 GB and 25% of dedicated VRAM (assumed 8 GB = 2 GB) | **1,024 MB** engine video memory |
| Leak check | working-set growth over the 10 cycles within the 2D control's variation (1 MB) plus an allowance for larger allocations, rounded up to **10 MB**; nodes back to the baseline of 1 and orphan nodes 0 after every exit | **10 MB**, nodes 1, orphans 0 |
| Load time | the arena is built and first frame drawn within 5 s of the request, with the work visible to the player | **5 s** |
| Draw calls and primitives | **diagnostic only** in B1b: recorded, not pass or fail. B1b's report registers per-element budgets for B1c and B4 before they are measured | n/a |

## 5. Pass rule for B1b
B1b **passes** only if every limit above is met in the standard, fast, camera and soak runs and the leak check, for the production configuration (shadow-casting light on, instanced crowd, scoreboard). If a limit fails, the report says so and tries the reduced configurations named in the plan (fewer crowd cards, lower shadow quality, a static scoreboard) one at a time, and the verdict is 3D-REDUCED if one passes, otherwise 3D-FAIL. Results are reported against these values on this machine only.
