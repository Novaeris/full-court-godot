# 3D overhaul, M5: broadcast integration

Written 2026-11-23. Pictures: `docs/validation/3d_overhaul/m5/` (`intro_2` a player introduction, `celebration`, `closeup`) made by `tools/screenshot.gd screen=owner_replay mode=broadcast intro=2` (new option), `shot=celebration`, `shot=closeup`; compare with `m3/replay_*.png` and `m2/replay_free_throw.png`.

## What changed
- **Main camera**: a little lower (offset 35 ft up and 58 ft back, a 31 degree look instead of 35) and looking at the chest height (3.4 ft instead of 3), so faces and numbers are seen and not only the tops of heads. The 28 ft minimum (D-070) is unchanged and tested for every angle.
- **Close shot from the front** (`FcBroadcast3DRules.camera_pose_front`): the director's "closeup" shots now frame the player nearest the focus from in front of him, a third of a turn off the line he faces, 9 ft up, looking at his chest: his face and number instead of his side or back. Never nearer than 28 ft to what it looks at (the offset is scaled up until it is), tested over seven facings, four zooms and four places including off the court. A "close-up" is still a medium shot (D-070); the 2D spotlight card is still the close-up.
- **Introductions in 3D**: the replay screen now tells the 3D view who is being introduced (`show_introduction`). That player turns to the broadcast camera and waves to the crowd (a new `intro` pose), the others stand still, a glowing ring in the team colour lies on the floor under him and a soft light shines on him from above. It ends cleanly when the introductions end or are skipped.
- **Celebrations in 3D**: when the director's shot is a celebration (a three, the end of a run, a lead change), the scorer's teammates throw both fists up (`celebrate`), the scorer gets the ring and light, and the camera takes the front shot. The director's reason is read through a new `FcCameraRig.last_shot()`; nothing in the director changed.
- **Replay and other cameras**: the replay variants (main, baseline, overhead) use the same poses, so they gain the lower main camera and the same minimum distance.

## Tests
`tests/unit/test_broadcast_integration.gd` (5): the front shot never gets nearer than 28 ft (7 facings x 4 zooms x 4 places), looks at the chest, is on the side the player faces and a little off the line; the main camera keeps its distance; celebrants celebrate a made shot and not a miss, and the intro pose loops with the arm raised; `last_shot` works. Live: `test_an_introduction_spotlights_the_player_and_ends_cleanly` (the introduced player is in the `intro` state, the ring is visible, the other nine stand idle, the camera is at least 27 ft from his chest, the ring is gone after the introductions); the 7 live 3D tests and 28 `broadcast` live tests pass. Style lint passes.

## Performance (30 s, same procedure, development machine only)
standard: avg 5.23 ms, p95 6.35 ms, p99 6.92 ms, worst 14.46 ms; camera sweep: avg 3.71 ms, p95 5.53 ms, p99 6.66 ms, worst 14.16 ms; none over 16.6 ms in either; working set 338 MB; video memory 59 MB; draw calls about 1,185. Limits p95 16.6 ms, p99 33.3 ms.

## Limits (honest)
- The introduction camera glides from the previous shot, so a picture taken a moment after the step starts can still show the glide (the screenshot waits 40 frames).
- The celebration shot from behind the basket can have the stanchion pole in the corner of the picture, since the camera stands where the basket's own support is.
- Only the introduced player waves; there are no handshakes, hugs or huddles, and the celebration is one pose for everyone.
- The ring and light are simple: a flat disc and a spotlight, no volumetric beam.
- The replay camera composition was reviewed by looking at pictures of the three replay variants, not changed beyond the shared pose changes.
