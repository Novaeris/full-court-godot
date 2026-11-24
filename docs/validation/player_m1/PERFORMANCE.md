# M1 library players: measured cost (development machine)

Machine: AMD Ryzen 7 8700F, NVIDIA RTX 4060, gl_compatibility, vsync off, 1080p. Raw output: `perf/scene_benchmark.txt`, `perf/replay_benchmark.txt`. Generated body = the current default.

| Case | Generated body | Library players |
|---|---|---|
| 1 player (avg frame) | 1.05 ms | 1.16 ms |
| 10 players | 2.24 ms | 3.41 ms |
| 10 players + crowd 6000 | 2.33 ms | 3.51 ms |
| 31 characters + crowd 6000 (full arena, p95) | 3.24 ms avg (5.94 p95) | 5.29 ms avg (10.31 p95) |
| full arena, 1280x720 / 2560x1440 (avg) | 2.82 / 3.74 ms | 5.30 / 5.87 ms |
| Draw calls, 31 characters | 1,103 | 1,615 |
| Real replay screen (5v5, 25 s): avg / p95 / p99 | 2.68 / 3.50 / 4.29 ms | 4.58 / 8.77 / 9.37 ms |
| Real replay screen: video memory / working set | 61 MB / 337 MB | 97 MB / 372 MB |
| Triangles per player | about 5,500 | about 12,300 body and clothes plus about 1,500 head and hair |

Reading: the library players cost about 2 ms more per frame in a full arena (still 3x under the 16.6 ms frame, no frame over 16.6 ms) and about 36 MB more video memory (mostly one 512 x 320 graphics texture per jersey). Draw calls rise because each head part, hair and the clothes are separate meshes; merging parts per player at attach time is the first optimisation if a lower-end device needs it. Not measured: lower-end hardware, phones (Dynasty is the only mobile mode and does not use 3D).
