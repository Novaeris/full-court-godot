# 3D overhaul, M4: arena

Written 2026-11-23. Pictures: `docs/validation/3d_overhaul/m4/` (`court_wide`, `court_key`, `front`, and the real replay screen: `replay_baseline`, `replay_overhead`). Made by `tools/character_showcase.gd` and `tools/screenshot.gd`.

## What changed
- **Crowd** (`crowd.gdshader`): the same single MultiMesh of camera-facing cards, but each card is now DRAWN as a person (head, eyes, ears, hair, a cap or an afro, neck, shoulders, a striped or plain top) with a skin tone (5), hair colour (4) and hair style (5) chosen per fan from its instance id, clothing in the loyalty colour from `FcCrowdPlan`, and upper rows darker. When the crowd cheers, fans throw their ARMS UP (each at a slightly different moment), in the wave too. Cost per spectator on the CPU is still nothing.
- **Seating** (`FcArenaDressing`): the lower bowl in the home team's colour (the visitors' end in theirs), the upper bowl neutral, alternate rows a shade apart; four aisles on every tier of every side (one MultiMesh of 256 slabs).
- **Branding**: back walls with 3 to 6 banners (the count comes from the arena key) in the home colours, each carrying the team nickname; a scrolling LED ribbon of home, accent and away chevrons round the lower bowl (`led_ribbon.gdshader`); the existing rotating LED boards kept.
- **Lighting**: a lighting truss with 16 glowing lamps high above the court (casting no shadows), ambient light lowered and glow switched on so the LED parts bloom; the existing sun and four soft spotlights kept.
- **Scorer's table** on the far sideline between the benches, its front lit in the home colour, laptops, five seated staff.
- **Courtside**: rows of chairs with spectators behind both baskets and along the near sideline.
- **Bench**: the real players who are not on court now SIT on their bench (a new `sit` pose, up to eight per team, the hips land at seat height through the ground-contact pass), walking out to the court when they are subbed in. The stand-in bench figures are hidden when the viewer seats the real ones.
- **Officials and coaches** (`FcBroadcastCharacter` with an `attire` of `referee` or `suit`): three referees in black shirts with white trim and long trousers who follow the play (lead at the baseline, trail and centre on the sidelines), and a head coach per team in a suit standing with arms folded (a new `coach` pose). Same skeleton and mesh builder as the players; no number, dark shoes, long sleeves or trousers drawn as extra cloth over the arms and legs. They are scenery: not in the game data, never read or written back.
- Different home teams get different arenas (seat colours, banner count and colours, ribbon colours, light tint) from one scene.

## Tests
`tests/unit/test_arena_dressing.gd` (5): seat colours follow teams and the bowl; the scene is dressed with the expected counts and another team gets another arena; officials and coaches have valid surfaces, no socks, no number, longer sleeves for a coach and more cloth than shorts while a player keeps a number; sit and coach poses are valid and a seated player's hips are at bench height and much lower than standing; the crowd shader draws people. `ui_style` lint baseline for `court_scene.gd` lowered 10 to 8. Live: 28 `broadcast` and 8 `arena` live tests pass (the earlier live test that expected ten characters on court still passes because seated players are not counted as on court).

## Performance (30 s, same procedure, development machine only)
avg 5.39 ms, p95 6.33 ms, p99 6.98 ms, worst 13.48 ms, none over 16.6 ms; working set 339 MB; video memory 61 MB; draw calls about 1,185 (M3: about 610). Limits: p95 16.6 ms, p99 33.3 ms. It is about twice the M3 cost: 17 more characters (bench, referees, coaches), the dressing, and a heavier crowd fragment shader. Still a third of the budget on this strong GPU; **nothing was measured on a weak or integrated GPU**, where the per-pixel crowd shader is the first suspect.

## Limits (honest)
- The crowd is still flat cards turned to the camera (painted people, not 3D people), so a close shot from inside the stands would look flat. The 28 ft rule of D-070 keeps the broadcast camera away from them.
- The spectators in the courtside and at the table are the old box-and-ball people, not the new characters.
- Coaches stand still with folded arms (no gestures); referees only walk and run (no whistle or signals).
- Banners carry only the team nickname; no retired-number or championship-year art.
- The roof, catwalks and light beams are simple: a truss and glowing lamps.
- A bench longer than eight leaves the extra players out of the picture.
