# Arena presentation: performance check (Broadcast pass 2, M5)

Measured with `tools/perf_benchmark.ps1 mode=replay3d` on the development machine only (AMD Ryzen 7 8700F, NVIDIA RTX 4060, gl_compatibility, 1920x1080, vsync off), against the limits in [PERFORMANCE_THRESHOLDS.md](PERFORMANCE_THRESHOLDS.md). Nothing was measured on weaker or integrated GPUs.

## What M5 added to the scene
Crowd on a GPU shader (`crowd.gdshader`: idle sway, cheer, groan, stadium wave, driven by three numbers per frame), four soft spotlights (no shadows), four LED boards with 16 text labels, two benches (two MultiMeshes, 12 figures), a glossier floor, floor wordmarks.

## Frame time and memory (30 s runs, 521-event benchmark game)
| Run | avg | p95 | p99 | worst | over 16.6 ms | working set | video memory | draw calls |
|---|---|---|---|---|---|---|---|---|
| standard | 2.81 ms | **3.51 ms** | **4.19 ms** | 11.9 ms | 0 | 323 MB | 55 MB | about 850 to 900 |
| camera | 2.62 ms | **3.29 ms** | **3.73 ms** | 10.3 ms | 0 | 301 MB | 55 MB | about 690 to 900 |

Limits: p95 at most 16.6 ms, p99 at most 33.3 ms, at most 1% of frames over 33.3 ms, working set at most 2,048 MB, video memory at most 1,024 MB. **Frame time and memory pass with a wide margin.** The `fast` and `soak` runs were not repeated for M5 (planned for M8).

## Leak check: NOT a clean pass (open item)
The pre-registered criterion is growth of at most 10 MB in the working set over 10 enter/exit cycles (worst after any exit minus after the first exit), nodes back to 1 and orphans 0.

| Commit | After exit 1 | Worst | Growth |
|---|---|---|---|
| B4 (original measurement) | 273 MB | 280 MB | 7 MB |
| B4 (re-run today) | 281 MB | about 282 MB | about 3 MB (run ended early in the capture) |
| M1 | 274 MB | 298 MB | 24 MB |
| M2 | 280 MB | 288 MB | 8 MB |
| M3 | 284 MB | 290 MB | 6 MB |
| M4 | 278 MB | 298 MB | 20 MB |
| M5 (twice) | 292 / 286 MB | 308 / 306 MB | 16 / 20 MB |

What this does and does not show:
- Nodes returned to 1 and orphans stayed 0 after every exit, video memory (30 MB) and engine static memory (58 to 59 MB) were constant, and the working set plateaus instead of climbing every cycle. That does not look like an object leak.
- The growth does not follow any one milestone (M1, which only reorganised the UI, shows 24 MB while M2 and M3 show 6 to 8 MB), so on this evidence it is run-to-run variation in how the operating system and allocator hold memory, not a regression caused by M5. This is an inference, not a proof.
- It exceeds the 10 MB criterion in several runs, so **the leak criterion is not met on this machine today and is recorded as open.** M8 repeats the leak check several times and reports the median, and investigates further if growth persists.
- A cheap hypothesis (the importance scores were computed three times per screen and `player_line` copied a growing array per event) was tried and fixed anyway because it is wasteful (scores are now cached per timeline), but it did not change the leak numbers.

## M8 re-measurement on the final build (all of Broadcast pass 2: modes, graphics, camera rules, replay tools, arena, commentary and production)
Same machine and procedure (`tools/perf_benchmark.ps1 mode=replay3d`, 1920x1080, vsync off, 521-event benchmark game). Runs were done one at a time.

| Run | avg | p95 | p99 | worst | over 16.6 ms | working set at the end | video memory | nodes / orphans |
|---|---|---|---|---|---|---|---|---|
| standard, 30 s | 3.34 ms | **4.43 ms** | **5.16 ms** | 12.4 ms | 0 | 302 MB | 55 MB | 1441 / 0 |
| fast, 30 s | 3.41 ms | **4.57 ms** | **8.91 ms** | 14.2 ms | 0 | 320 MB | 54 MB | 1441 / 0 |
| camera, 30 s | 3.11 ms | **4.22 ms** | **4.91 ms** | 12.8 ms | 0 | 302 MB | 55 MB | 1441 / 0 |
| soak, 300 s | 3.40 ms | **4.50 ms** | **5.13 ms** | 16.3 ms | 0 | 305 MB | 54 MB | 1441 / 0 |

**Frame time, memory and video memory pass with a wide margin** (limits: p95 16.6 ms, p99 33.3 ms, at most 1% of frames over 33.3 ms, working set 2,048 MB, video memory 1,024 MB). The soak shows no growth over 300 s (302 MB at 30 s, 305 MB at 300 s, nodes constant). The soak was 300 s, not the 600 s of the procedure (chosen to fit the session, as in B4). Frame time rose from the M5 figures (p95 3.51 ms) because M6 and M7 added per-event work (commentary and ambience models); it is still about a quarter of the limit.

### Leak check, three repeats
| Repeat | After exit 1 | After exit 10 | Growth (worst minus first) |
|---|---|---|---|
| 1 | 284 MB | 301 MB | 17 MB |
| 2 | 290 MB | 301 MB | 11 MB |
| 3 | 293 MB | 304 MB | 11 MB |

**Median growth 11 MB against the 10 MB criterion: not strictly met, recorded as open.** What the numbers show: in every repeat the working set ends at about 301 to 304 MB however low the first exit was (284 to 293 MB), nodes return to 1 with 0 orphans, video and engine-static memory are constant, and the 300 s soak is flat. That points to the first cycles still warming caches and the allocator, not to something accumulating, but this is an inference: no tool here proves it. No change was made to the criterion. If a stricter check is wanted, the next step is a longer leak run (for example 30 cycles) to see whether the plateau holds.
