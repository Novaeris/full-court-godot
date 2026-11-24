# Broadcast presentation plan (B0: audit and design)

Direction (D-069): a premium, television-style broadcast of every watched game in Owner, Career and Dynasty: automatic, manual and hybrid cameras, professional graphics, replays and highlights, pregame, halftime and postgame production, crowd and arena audio. 3D is the aim **if** three feasibility prototypes pass limits written down before they are measured; a permanent 2D presentation is the fallback and the delivery path if 3D fails. Mobile stays 2D (D-030). The sibling plan for player numbers is [BASKETBALL_AUTHENTICITY_IMPLEMENTATION_PLAN.md](BASKETBALL_AUTHENTICITY_IMPLEMENTATION_PLAN.md). Progress is recorded in [../AUTONOMOUS_WORK_LOG.md](../AUTONOMOUS_WORK_LOG.md).

## 1. What exists (updated 2026-11-23; the text written at B0 said there was no 3D, a static score bug and no audio presentation, all of which has since been built)
- **A reduced 3D viewer and a 2D fallback** (D-070): `FcBroadcast3DView` / `FcCourtScene` (stands, instanced crowd, benches, LED boards, hoops, code-built characters), `FcCourtView` (2D), `FcCourtLayout` (feet, 94 x 50), `FcReplayModel`, `FcBroadcastTimeline`, `FcReconstructor` (labelled reconstruction), `FcReplayScreen` as the one screen for Owner, Career and Dynasty.
- **Broadcast pass 2 (M1 to M8) built on top of it**: presentation modes and HUD, provenance and the identity kit, camera direction v2, replay v2 (importance, references, bookmarks, reel), arena identity, audio mixing and commentary, template-driven production and Full Court Tonight. See [BROADCAST_PASS2_PLAN.md](BROADCAST_PASS2_PLAN.md) and D-071.
- **Still true**: the simulation has no spatial model and records no positions, passes, possession starts, timeouts or shot clock; everything between events is reconstructed and labelled so.

## 2. Architecture: eight layers, each pure where it can be
| # | Layer | Owns | Exists |
|---|---|---|---|
| 1 | Simulation | the game, the box score | `FcGameSimulator` (unchanged) |
| 2 | Event delivery | the rows plus a context (teams, looks, mode) | `FcReplay.for_*`, `FcGameDay`, `FcPostGame` |
| 3 | **Broadcast timeline** | running state around each event (this milestone, B2) | **`FcBroadcastTimeline`** (built) over `FcReplayModel` |
| 4 | Spatial reconstruction | plausible positions between events, labelled "reconstructed", never stored as truth | planned (B1) |
| 5 | Camera director | which shot, target and framing, as pure data | planned (B2b option B/C) |
| 6 | Graphics | overlays that read the timeline only | `FcScoreBug` to extend; lower thirds, alerts, panels to build |
| 7 | Audio | cues and captions from events | planned (B3) |
| 8 | Replay | a cursor over the timeline | `FcReplayScreen` to extend |
Rules: layers 3 to 5 are headless; nothing here calls the simulator, changes rows, box scores or saves; one pipeline serves all three modes. A "live" game is the finished simulation played back at broadcast speed, so determinism is untouched (no incremental simulation interface).

## 3. Milestones, order and rules
Order: **B2** timeline (done), **B2b** 2D broadcast presentation (option C), **B3** audio and captions, **B1** reconstruction spike, **B1b** minimal 3D performance prototype, **B1c** player-model prototype, then the 3D decision, **J1** jersey numbers (mandatory before B4 if 3D proceeds), **B4** 3D court, players, ball and camera director, **B5** pregame/halftime/postgame, **B6** replays and highlights, **B7** crowd and arena audio and commentary, **B8** analytics (only if a concrete scope exists).
- **B2b options (cumulative):** A graphics (scorebug with clock, possession, fouls and bonus; lower thirds; scoring alerts; substitution graphic; stat cards; run and milestone callouts; period, halftime and final panels; replay badge). B adds a 2D camera (pan, zoom, follow ball or player, reset; automatic, manual, hybrid), a pseudo-perspective projected court and a team-branded floor; the camera-director logic is built once as pure code. C adds replay trails, slow motion and instant replay of a timeline window. **Chosen: C.**
- **3D outcomes:** 3D-PASS (all three prototypes meet their pre-registered limits), 3D-REDUCED (passes at lower settings or scope), 3D-FAIL (build the 2D completion path: B4-2D, B5 in 2D, B6-2D, B7 with a 2D crowd; audio and captions never depend on 3D).
- **Performance limits are committed before the first 3D measurement** (`docs/validation/PERFORMANCE_THRESHOLDS.md`): p95 frame time at most 16.6 ms, p99 at most 33.3 ms, over 33.3 ms in at most 1% of frames; total application memory at most 25% of an assumed 8 GB machine; GPU memory at most the smaller of 1 GB and 25% of dedicated VRAM; no growth over 10 enter/exit cycles beyond a 2D control; arena ready within 5 s. Measured on the development machine only, and said so.
- **Reconstruction honesty:** everything between events is presentation, labelled "reconstructed", derived from a presentation seed (no extra saved data), with a defined ball-interaction model (hold, pass, shot, rebound, loose ball, dead ball) validated for continuity and byte-identical output.
- **Shared graphics:** one implementation of each graphic must work over the 2D court and a 3D viewport; switching viewers or falling back to 2D must keep the replay position, score, clock and event context.
- **Tests by milestone:** headless milestones get unit tests; UI milestones get live tests and screenshots at fixed sizes, seeds and animation state; performance milestones get frame-time and memory captures; integrated milestones all of them. Every graphic's text must equal the play-by-play or box score for the same event.

## 4. Established limits (not to be hidden by presentation)
The picture is not tracked play; there are no timeouts, shot clock or jump ball; league players have no stored jersey number until J1; Owner and Career keep 20 watched games with events, Dynasty its last 5 replays.
