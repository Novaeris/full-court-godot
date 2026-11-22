# B4: the 3D broadcast viewer (decision D-070, 3D-REDUCED)

Written 2026-11-22. Measured on the development machine only (AMD Ryzen 7 8700F, NVIDIA GeForce RTX 4060, `gl_compatibility`, 1920x1080, vsync off); nothing here claims anything about lower-end hardware. Limits are the ones pre-registered in [PERFORMANCE_THRESHOLDS.md](PERFORMANCE_THRESHOLDS.md).

## What was delivered
- `src/ui/broadcast3d/`: `FcCourtScene` (arena, court, hoops, instanced crowd, scoreboard), `FcBroadcastCharacter` and `FcBroadcastPose` (code-built characters and procedural poses promoted from the B1c prototype), `FcBroadcast3DRules` (pure: camera pose, facing, body from position, state per event), `FcJerseyNumbers` (display numbers per game, nothing stored), `FcBroadcast3DView` (the view).
- `FcReplayScreen`: a stage that holds the 2D court or the 3D view with the same graphic strip, score bug and REPLAY badge on top; view choices Broadcast 3D, Broadcast 2D, Flat view. One `FcCameraRig` drives both views.
- The 3D view is only a view: replay position, score and clock belong to the screen. If it cannot be built (`FcBroadcast3DView.force_failure` in tests) the screen shows the 2D court and says so in words.
- Scope limits from D-070: broadcast, wide and medium framings only, the camera never closer than 28 ft to what it looks at (no 3D close-up), no mobile 3D, characters labelled as reconstructed (never tracked play).

## Defects found while integrating, and fixed
- Defenders were drawn seated or lying (the defensive stance bent the hips backwards). Fixed in `broadcast_pose.gd`; the blend and loop tests still pass.

## Tests
- Unit `tests/unit/test_broadcast3d_rules.gd` (10): display numbers unique, in range, independent of listing order, skip retired numbers, terminate when none is free; camera minimum distance and on-court target; facing; bodies by position; state per event; travel speed under the reconstruction limit.
- Live `tests/live/test_live_broadcast3d.gd` (6): ten characters shown; switching views (3D, 2D, flat, repeatedly) keeps the event, score, caption, speed and play state; characters stand at the reconstructed keyframe positions; forced failure leaves a working 2D screen with the replay position kept; camera never closer than the minimum under repeated zoom and obeys manual moves; rows and box score byte-identical after use.

## Performance (replay screen in 3D, benchmark game seed 1)
| Run | Frames | avg ms | p95 | p99 | worst | over 16.6 ms | Limit |
|---|---|---|---|---|---|---|---|
| standard 60 s | 30,675 | 1.96 | 2.28 | 2.65 | 7.66 | 0 | p95 16.6, p99 33.3 |
| fast (4x) 60 s | 30,145 | 1.99 | 2.34 | 2.93 | 9.86 | 0 | same |
| camera 60 s | 31,436 | 1.91 | 2.28 | 2.63 | 7.37 | 0 | same |
| soak 300 s | 163,248 | 1.84 | 2.19 | 2.53 | 10.81 | 0 | same |

The 2D baseline in the same tool averages about 1.09 ms. Memory: working set 284 to 289 MB (limit 2,048 MB), engine video memory 52 MB (limit 1,024 MB), nodes 1,301 and orphan nodes 0 while the replay is shown, draw calls about 800 to 930 (diagnostic only).
Leak check, 10 enter/exit cycles: working set after the first exit 273 MB, worst 280 MB, **growth 7 MB (limit 10 MB)**, nodes back to 1 and orphans 0 after every exit.

**Verdict: PASS against every pre-registered limit on this machine.** Honest notes: the soak was 300 s (the benchmark default is 600 s, chosen shorter for the session); the leak growth is within, but not far from, the limit; hardware is strong.

## Not done, by design
Soak at the full 600 s, lower-end hardware, 3D close-ups, mobile 3D, real stored jersey numbers (display numbers only), commentary of the 3D view (B7).
