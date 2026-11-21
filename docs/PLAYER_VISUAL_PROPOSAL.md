# Player portraits and the Dynasty visual experience: investigation, prototypes and proposal (D-059, PROPOSED)

Status: **investigation and prototypes finished, waiting for founder approval.** Nothing here is switched on in the shipped game: the new portrait is behind `FcPlayerFigure.hd_enabled` and the cinematic pack opening behind `FcPackRevealCinematic.enabled` (both `false`). Every number, picture and recording below was made by running the real Godot code (not mock-ups).

How to look at the results in two minutes:
1. Portraits: open `docs/validation/portraits/bust_current.png` and `bust_hd.png` side by side (120 seeded fictional players each).
2. Pack opening: play `docs/validation/pack_reveal/video/legendary_pack.mp4` (17 s, one pack with all five rarities), then look at `rarity_impacts.png`.
3. Decide the six questions in section 10.

## 1. Current portrait quality assessment

Files inspected: `src/ui/player/` (`player_visual`, `player_figure`, `player_portrait`, `player_cards`, `player_presentation`), `src/ui/cards/` (`card_face`, `rarity_style`, `pack_art`, `pack_reveal`), `docs/ASSET_SPEC.md`, `assets/ART_PROVENANCE.md` (note: the provenance file lives in `assets/`, not `docs/`), `tests/unit/test_player_identity*.gd`, the golden file `tests/support/player_identity_golden.json`.

Baseline pictures (made by `tools/portrait_sheet.gd mode=current`): `docs/validation/portraits/*_current.png`.

What the current figure does well
- Deterministic and shared: one resolver (`FcPlayerVisual.resolve`) feeds every screen; pinned by a 50-key golden test. This is the most valuable part and must not change.
- Clean at small sizes (24 to 48 px), cheap to draw (about 0.2 ms at 64 px, 12 to 47 draw commands), and has no file to license.
- A sensible tier chain already exists (monogram, approved art via `art_path`, procedural), so featured players can already use hand-made art.

Where it falls short (seen on the 120-player sheet)
| Area | What the picture shows |
|---|---|
| Flatness | Flat fills with a faint overlay. No form: the head reads as a disc, not a head. Jersey and skin share one light direction but little else. |
| Sameness | The head is the same shape, the eyes the same two dots, the mouth a single line. Variation comes mostly from hair and skin colour, so players of one skin and hair read as one person at a glance. |
| Hair | Eight styles, one silhouette each, no hairline, no volume, no texture. No receding hairline or grey with age. |
| Age | None. A 19 year old rookie and a 38 year old veteran share a face. |
| Body | Blocky shoulders, no neck or trapezius, arms like rectangles; the full body is a stick figure with a tiny head. |
| Uniform | A flat V-neck with a number. No straps, trim, side panels, number outline or shorts detail. |
| Recognisability | At card size the faces are not memorable; "believable player identities" is not yet met. |

Measured (this machine, `tools/portrait_bench.gd`, 200 portraits per size): current figure 81 us at 32 px, 215 us at 64 px, about 240 us at 128 px and above.

## 2. Three visual directions compared

| | 1. Higher-fidelity procedural 2D | 2. Consistent illustrated artwork | 3. Stylised 3D portraits |
|---|---|---|---|
| Visual quality | High and consistent. Prototype: lit spline heads, eye shapes, hairlines, ageing, tattoos, detailed kits. Stylised, not photoreal | Highest ceiling and most "designed", but only as good as the artist and the consistency between artists | Good depth, real lighting and poses, but a believable stylised human face in 3D is a large, specialist job; weak models look worse than good 2D |
| Identity at scale | Unlimited, deterministic, one face per key forever | Only for players someone draws. Thousands of generated league players cannot be drawn | Unlimited if the model is parametric, but each parameter needs authored morph targets, hair and clothing meshes |
| Implementation complexity | Medium. Done as a prototype in this change (about 850 lines of GDScript for the figure and traits) | Low in code (the `art_path` tier exists), high in production | Very high: models, rigs, hair and cloth, a render pipeline, lighting, bake or live, import pipeline for Studio |
| Performance | 1 to 2 ms to draw one portrait, so it MUST be baked (cache prototype: 0.6 us per use) | Excellent (one texture), but memory grows with art count | Live 3D per list row is not viable on a phone; needs baking to textures anyway, plus a SubViewport per figure |
| Asset needs | None (no files, nothing to license) | 512 x 640 PNG per featured player, provenance and review per file | Meshes, textures, rigs, animations, a licence trail for all of them |
| Solo developer fit | Good: all code, all testable, all deterministic | Good only for the small featured set, and only with an artist | Poor: a different job (technical art) that would dominate the schedule |
| Mobile | Good once baked | Good | Risky |
| Save / identity risk | None: same key, same face; no new `FcPlayer` field | None | Same as direction 1 if parametric from the key |

Recommendation: **1 as the default for every generated player, 2 as the pathway for featured Dynasty players (already supported, now with a written provenance and spec flow), 3 not now.** The tier slots (3 poses, 4 render) stay reserved. This matches the stated goal: a polished, recognisable basketball-game look with believable identities, procedural for the league and approved custom artwork for featured Dynasty players.

## 3. Recommended portrait architecture

Unchanged (do not touch): `FcPlayerVisual.resolve` and everything pinned by the golden test; `FcPlayerPresentation`; the tier chain; `FcPlayerPortrait`, `FcPlayerCards`, `FcCardFace` callers; `art_path` loading; the controller contracts; the save format.

Added by the prototype (all in `src/ui/player/`):
- `FcPlayerTraits`: extra face and body variation (eye shape and tilt, iris colour, brow arch, nose width and bridge, lip fullness, ear size, neck, shoulder slope, undertone, hairline, grey, tattoos, shooting sleeve, chain, earring, forehead, cheek, chin, cleft). Derived from the key by FNV hash in a separate salt space (`|t_`), so no existing identity value can change. **Never stored.** All values are small integers.
- `age`: an optional input on the visual (`visual["age"]`, set by callers that know the player's age: Owner and Career players age every season). The same face then gains lines, a higher hairline and grey temples. With no age given a stable age 19 to 38 is derived from the key. Age is not part of `resolve`'s identity, so the golden test is untouched.
- `FcPlayerFigureHd`: the new renderer. Same contract as `FcPlayerFigure` (draw a resolved visual into a rectangle); detail grows with size (silhouette below 30 px, eyes below 56, all features below 90, fine shading below 150, hero detail above).
- `FcPortraitBake`: bakes a figure once into a small SubViewport texture, keyed by everything that changes the picture (key, age, tier, team colours, number, crop, size, which figure), bounded and least-recently-used. This is what makes the richer figure affordable on a phone.
- Switch: `FcPlayerFigure.hd_enabled` (default off). When on, the old entry points (`draw`, `draw_headshot`) route to the new renderer, so every screen, card and the profile change together, never one at a time.

Featured Dynasty players (approved artwork pathway), already built, to be documented and enforced:
- A card's art is `data/content_*/art/<player_id>.png` (512 x 640 PNG, transparent, 4:5, head and torso, no baked text or frame), loaded as tier 1 via `art_path`; a missing or unreadable file falls back to the procedural figure.
- Every file must be listed in `assets/ART_PROVENANCE.md` with source (hand-made, commissioned or generated), the founder's approval and the legal review state **before** it is committed. Proposed addition: a content-validator warning for any art file without a provenance line (Phase 5).
- The HD figure is the fallback for those players, so a featured player whose art is not ready yet still looks good.

What is deliberately not done: no new field on `FcPlayer`, no change to `DATA_VERSION`, no migration, no change to the controller contracts, no new dependency.

## 4. Prototype results (portraits)

Contact sheets (120 seeded fictional players `sheet:0` to `sheet:119`, ages 19 to 38, 12 team kits), current beside HD, made with `tools/portrait_sheet.gd`:
| Picture | What it shows |
|---|---|
| `bust_current.png`, `bust_hd.png` | 120 busts at 120 px |
| `headshot_*.png` | 120 head crops at 120 px |
| `full_*.png` | 24 full bodies standing |
| `sizes_*.png` | the size ladder 24 to 256 px (and head crops) for 6 players |
| `uniforms_*.png` | one player in 12 team kits at 240 px |
| `ages_*.png` | two faces from age 19 to 37 |
| `baked_hd.png` | 24 players served from the bake cache |
| `collection_hd0.png` / `collection_hd1.png` | the real Dynasty collection screen, shipped vs HD |

What the HD figure demonstrates (requirement by requirement)
- Improved facial geometry: a smooth spline head with cheek, jaw and chin shapes (round, square, pointed times narrow, mid, broad), forehead height via the hairline, ears of three sizes, a neck.
- Wider feature variation: three eye shapes and tilts, five iris colours (rare light eyes), arched or flat brows in three weights, nose width and tip, lip fullness, expression (smile, neutral, smirk), cleft chin.
- Hair and silhouettes: the same eight style ids as the identity (so no identity change) with three variants each (buzz, crop, side-part pompadour; high top, curls on top, taper; round, wide, small afro; cornrows, box braids, top bun; locs hanging, long, twists; straight, long and ponytail), a real hairline.
- Skin tone and undertone: the six tones plus five undertones (olive, neutral, golden, rosy, cool), kept within a small shift of the tone.
- Age: lines (forehead, nasolabial, crow's feet, under-eye) from about 29, a receding hairline and grey temples with age and a per-player tendency to grey early.
- Body and shoulders: three builds times square or sloped shoulders, neck thickness, deltoid shape, arms.
- Lighting and shading: one key light from the upper left on every shape (an exact linear gradient), soft shadow under the chin and on the lower right, forehead and cheek highlights, cheek warmth.
- Detailed uniforms: straps, double V trim, armhole trim, side panels, folds, a number with a dark outline; full-body shorts with waistband and side stripes, socks and shoes. Accessories: headband, shooting sleeve, chain, ear stud, arm tattoo (the last four are hash-derived and rare).
- Headshot, bust and full-body: all three, plus `backdrop()` for a hero spotlight.

Honest limits (what a person should still judge)
- It is a polished **stylised illustration**, not a likeness; at 256 px and above a face reads as a clean cartoon with believable proportions. The current figure is a few shapes; this is a visible step up, not a photograph.
- The full-body figure is stiff (front-facing idle). Poses are the reserved tier 3.
- Some hair styles (long, locs) are blocky at the bottom edge and would take another polish pass; the proposal budgets one.
- Lighting is a pseudo-light: no real normal maps. That is the right trade for a solo developer.

Performance (this machine; `tools/portrait_bench.gd`)
| Size | Current | HD (live draw) | HD baked |
|---|---|---|---|
| 32 px | 81 us, 12 cmds | 239 us, 14 cmds | 0.6 us, 1 cmd |
| 64 px | 215 us, 38 cmds | 968 us, 116 cmds | 0.6 us, 1 cmd |
| 128 px | 241 us, 47 cmds | 1,751 us, 209 cmds | 0.6 us, 1 cmd |
| 256 px | 242 us, 47 cmds | 2,278 us, 264 cmds | 0.6 us, 1 cmd |
So HD drawn live is 4 to 9 times dearer: fine for one hero portrait, too slow for a collection grid redraw (100 cards at 1.8 ms is a 180 ms hitch). **Therefore the HD figure is only recommended together with the bake cache**; the bake pays the cost once per player, size and crop. Memory: about 64 KB per 128 px picture, cap 320 pictures (about 20 MB), tunable.

## 5. Pack-opening: what exists, what the prototype changes

Inspected: `FcPackReveal`, `FcPackArt`, `FcCardFace`, `FcRarityStyle`, `data/ui/audio.json`, `FcAudio`, `FcMotion`.

Integrity (unchanged and re-tested): cards are rolled, paid for and saved by `FcDynastyPacks` before any of this exists. The reveal only READS the committed opening, in the order rolled. Nothing in the new code can change a result, odds, a reward or the order: `entries` and `opening` are never written (tested by deep comparison).

Findings in the shipped reveal
| Finding | Action |
|---|---|
| It simulated a mouse event (`face.mouse_entered.emit()`) to start the light sweep and set `lift` directly for the glow | **Fixed now**: explicit `FcCardFace.play_sweep()` and `set_glow()`; shipped reveal uses them; old behaviour otherwise identical (all 105 live tests pass) |
| Particles are one `CPUParticles2D` node per burst (up to 72 particles), freed by a timer | Prototype replaces with one drawn node and a hard cap of 160 (`FcRevealFx`) |
| Flash rate: one per card, player-paced | Prototype enforces at most 3 flashes per second in code, not by convention |
| Audio: 8 round-robin voices, a legendary sting lasts 1.1 s | Prototype adds a gate: a small sting is not layered under a big one for 0.9 s; two new synthesised sounds (`reveal_swell`, `reveal_hit`, no recorded audio) |
| Skip | Already correct (same result). Prototype keeps it and also kills every tween and effect at once |

### Storyboard (five stages; `docs/validation/pack_reveal/storyboard_stages.png` and the video)
1. **Pack presentation** (until tapped): the pack stands large (225 x 315) in its tier colour with a slow pulsing halo. Status: "Tap the pack to open it." Buttons: Open pack, Skip.
2. **Wrapper opening and card emergence** (about 1.7 s): a quick shake (4 wobbles), the tear sound, the top strip peels away with a burst of tier-coloured sparks, light rays and a faint flash (tier colour, strength 0.1); the pack fades and the face-down cards pop out one after another (70 ms apart) into a row along the bottom.
3. **Individual card reveal** (player-paced): a tap brings the next card forward to a large spotlight (225 x 321), the card back glows in the rarity colour (the build-up, longer for bigger rarities), the card turns, and the impact plays. A tap again lands the card in its place in the row (it turns face up there) and brings the next one forward. After the last, the tap is "See your pull".
4. **Special high-rarity presentation**: epic and legendary also dim the room, fan light rays behind the card, tremble, shake on impact, show a name plate (player name and rating) and play a low swell during the build-up. Legendary adds a banner ("LEGENDARY!"), a deep hit, a bigger burst and the longest build-up.
5. **Collection summary**: the shipped summary, unchanged (best first, NEW and DUPLICATE marks, shard values, collection progress bar).

### Rarity effects specification (data: `data/ui/reveal_effects.json`, read by `FcRevealSpec`)
| Rarity | Build-up | Dim | Glow | Sweep | Sparks | Flash | Shake | Rays | Ring | Banner | Name plate | Sound | Haptic |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Common | none | 0 | none | no | 0 | 0 | 0 | 0 | no | no | no | tap | none |
| Uncommon | none | 0 | 0.6 | no | 14 | 0 | 0 | 0 | no | no | no | bounce | none |
| Rare | 0.15 s | 0.15 | 0.9 | yes | 30 | 0.18 | 0 | 0 | yes | no | no | chime | none |
| Epic | 0.4 s | 0.35 | 1 | yes | 60 | 0.30 | 4 px | 10 | yes | no | yes | horn + swell | 40 ms |
| Legendary | 0.85 s | 0.62 | 1 | yes | 120 | 0.55 | 8 px | 16 | yes | yes | yes | arena horn + swell + deep hit | 80 ms |
Caps (data): 160 particles at once, 3 flashes per second, 2 ray fans, 1 banner. An unknown rarity (a future content release) uses the common spec, so new rarities can be published without a game update. Reduced motion: no pack show, no spotlight, no particles, rays, ring, flash, dim, shake or banner; cards simply turn over in place; sounds are unaffected (they have their own setting). Skip: `reveal_all()` stops every tween and effect, turns every remaining card in place, shows the same summary. Tested: same cards in the same order with the same intensities and the same NEW and DUPLICATE counts as watching.

Design intent for the legendary pull: the room goes dark, the card back burns gold, beams turn behind it while a swell rises, then a hit and a flash as it turns, with the name rising under it and a banner above. It should be the only thing on the screen for about three seconds.

Review results (code and tests)
- Particle limits: hard cap, drops extra (tested with 2,400 requested).
- Animation cleanup: every tween belongs to the reveal node; `stop_all()` and `_kill_presentation()` clear all of them; the effects node stops processing by itself when idle (tested).
- Audio overlap: gated (tested); the show asks for about four cues in the first second of a legendary (flip, sting, hit, swell earlier), under the 8 voices the audio layer has.
- Performance: the effects layer is one `_draw` node; no textures, no shaders besides the existing card sweep; the only per-frame work is while something is alive.

## 6. Performance and asset requirements (summary)
- Portraits: bake cache required with the HD figure. Budget (a target, to be measured on a phone): a first-time bake costs about one live draw (1 to 2 ms at 128 px) plus the viewport; 0.6 us per use afterwards (measured), at most about 20 MB of baked pictures.
- Pack reveal: 160 particles maximum, one effects node, no new textures; at most 2 full-screen translucent layers (dim and flash).
- Assets: none for the default look. Featured art: 512 x 640 PNG (`docs/ASSET_SPEC.md`), at most 1 MB decoded each, with a provenance line first.
- Audio: two new synthesised cues (no files).
- Mobile: all of the above is 2D canvas drawing (the compatibility renderer), no 3D, no compute.

## 7. Other visual opportunities (ranked by visible benefit per effort)
| Rank | Opportunity | Today | Proposal | Effort | Benefit |
|---|---|---|---|---|---|
| 1 | Player portraits everywhere | flat figure | HD figure plus bake (this proposal) | M | Very high: touches every screen |
| 2 | Dynasty collection and card variants | rarity frames exist; one look per rarity | Card variants as presentation only: foil and holo treatments per edition, a "featured art" frame, a hover tilt (no new gameplay or odds) | M | High |
| 3 | Pack opening | shipped, decent | cinematic five stages (this proposal) | M, prototype done | High at each pack, the most repeated emotional moment |
| 4 | Player inspection and profile | a stage with an idle bob, tabs | HD hero figure with backdrop spotlight and the name lower-third; the existing `FcShowcaseStage` gets the HD full body | S | High |
| 5 | Championship celebration | `FcCelebration`: banner, 80 confetti | add the title-winning roster as HD portraits in a line, the trophy, team crest and colours on the confetti | S | High at the biggest moment |
| 6 | Team uniforms | `FcUniformPreview`, jersey in the figure | the HD kit detail applied to the preview; alternate (away) kit colours from the same team branding | S | Medium |
| 7 | Team branding | crests and emblems are procedural and good | no change now; a wordmark and crest on the jersey chest for a hero kit | S | Medium |
| 8 | Post-game presentation | score bug, lower-thirds, HD faces for the three stars | player of the game with the HD bust in a lower-third | S | Medium |
| 9 | Matchup introductions | none exists | a short versus card (two team crests and the two best players as HD busts) before a Dynasty game; skippable; data only, no new mechanic | M | Medium |
| 10 | Draft presentations | tables | a "pick is in" card: crest, HD bust, name, position, overall as a lower-third; the draft class is generated, so every pick is a distinct face | M | Medium |
No gameplay mechanic is introduced by any of these.

## 8. Proposed implementation phases (each: tests green, commit, push)
- **Phase 0 (done in this change)**: assessment, three directions, prototypes (HD figure, traits, bake cache, cinematic reveal, effects layer, spec data), contact sheets, storyboard, video, benchmark, tests.
- **Phase 1: portraits to production quality.** Another polish pass on the weakest hair (long, locs), eyes at 56 to 90 px, jersey chest detail; tune the detail thresholds with the benchmark; wire `FcPortraitBake` into `FcPlayerPortrait`, `FcCardFace`, `FcPlayerTile`, `FcPlayerChip` and the showcase stage (live figure for the first frame, baked afterwards); pass the real `age` from the presentation view-model (Owner, Career); `hd_enabled` becomes true. Regenerate nothing: golden stays. Tests: determinism, identity untouched, bake correctness, style lint.
- **Phase 2: featured Dynasty art pathway.** Provenance enforcement: a content-validator warning for art without a line in `assets/ART_PROVENANCE.md`; a Creator Studio preview that shows the card with the art and with the HD fallback; a style guide page (framing, lighting, colour) so commissioned pieces match the HD figure.
- **Phase 3: cinematic pack opening to production.** `FcPackRevealCinematic` becomes the default behind a settings choice ("Pack opening: Cinematic or Quick", Quick = today's reveal); touch layout for 412 px; the haptics through `FcAudio`; a listening review of `reveal_swell` and `reveal_hit`; sound rebalancing on a real device.
- **Phase 4: celebrations and moments.** Championship with the roster line-up, post-game stars, player inspection hero, card variants (foil and holo per edition).
- **Phase 5: matchup and draft presentations.**
- Gate before each phase: the founder reviews pictures and recordings produced by that phase.

## 9. Risks and what I could not verify
- Whether the new look matches the founder's taste is a judgement only a person can make; the sheets exist for that.
- Timing and sound of the pack opening cannot be judged from stills: watch the video; the sounds are synthesised and have not been listened to by a person on real speakers.
- No phone or Android emulator run of the cinematic reveal; the effects layer is small, but the tap targets and a 412 px layout need a device check (Phase 3).
- The headless test runner cannot read rendered pixels; the baked-picture pixel check is a windowed tool run (`portrait_sheet.gd` job `baked`), not an automated test.
- `docs/ART_PROVENANCE.md` named in the request does not exist; the real one is `assets/ART_PROVENANCE.md`.

## 10. Decisions needed from the founder
1. Is the HD portrait style approved as the new default for generated players (Phase 1)? If you want it pushed further toward "illustrated" or "more realistic", say which sheet looks closest.
2. Approve the bake cache (a small memory cost, about 20 MB) as part of it?
3. Approve the cinematic pack opening as the default, with a "Quick" setting (Phase 3)?
4. Should the legendary banner say the rarity word ("LEGENDARY!") or the player's name?
5. Which of the section 7 items first after the portraits and pack opening (suggested order: 4, 5, 2)?
6. For featured Dynasty players: will art be hand-made, commissioned or generated? (This decides how strict the provenance check is.)

## 11. How to reproduce
- Portrait sheets: `godot_console --path . --script res://tools/portrait_sheet.gd -- out=docs/validation/portraits mode=current` (and `mode=hd`). A window opens briefly.
- Real screens with the new look: `./tools/screenshot.ps1 screen=dynasty_collection hd=1 out=...`.
- Pack opening storyboard: `godot_console --path . --fixed-fps 30 --script res://tools/pack_reveal_demo.gd -- out=docs/validation/pack_reveal/x cards=common,rare,epic,legendary` (add `reduced=1`, `skip_at=9.0`, `cinematic=0 hd=0` for the shipped one).
- Video: add `--write-movie file.avi` and `movie=1`, then convert with ffmpeg.
- Benchmark: `godot_console --path . --script res://tools/portrait_bench.gd`.
- Tests: `tests/unit/test_player_traits.gd`, `tests/live/test_live_player_hd.gd`, `tests/live/test_live_portrait_bake.gd`, `tests/live/test_live_pack_cinematic.gd` (the live ones: `./tools/run_live_tests.ps1 -Filter <name>`).
