# Autonomous work log

Record of the autonomous program (master plan revision 2.4, authorized by the founder on 2026-11-22; decision D-069). One entry per milestone: what was delivered, decisions, files, commands and results, commit, push, GitHub Actions. Nothing is listed as run or passing unless it was. Current totals live only in [TESTING.md](TESTING.md). The next steps are in [AUTONOMOUS_WORK_HANDOFF.md](AUTONOMOUS_WORK_HANDOFF.md).

## Setup (2026-11-22)
- Branch `main`, baseline `e7b7e9a`, working tree clean. `gh` logged in as the repository owner account; workflows `ci.yml`, `long-checks.yml`, `release.yml` exist.
- The last CI run on `e7b7e9a` (run 45046140970) had **failed**: live test `test_a_configured_screen_shows_the_form_and_an_unreachable_service_gives_a_plain_message` (a timing-sensitive assertion). This became the first Stage 1 finding.
- A session-only watchdog (cron, every 30 minutes) re-enters the program from this log and the handoff when the session is idle. It dies if Claude Code closes (re-create it in a new session).

## Stage 1: Stabilization
**Delivered:** [STABILIZATION_AUDIT.md](STABILIZATION_AUDIT.md) with 10 fixed findings (two P1 security-relevant online defects, the JSON signature round-trip defect, the phone overflow of the post-game line score with overtimes, the red CI test, and test-infrastructure and documentation defects), a backlog of 10 items (none blocking), and the evidence for what was refuted. No saved-data format changed.

**Decisions** (D-069 and the audit): Stage 1 fixed only reproduced P0/P1 defects and test-infrastructure defects, each with a regression test that failed first; P2/P3 items went to the backlog. Test fixtures now never touch the developer's real `user://` files and never depend on the clock.

**Files changed:** `src/online/online_crypto.gd`, `src/online/online_server.gd`, `src/ui/postgame/post_game_screen.gd`, `src/sim/game_simulator.gd` (comment), `tests/unit/test_online.gd`, `tests/live/test_live_online_screen.gd`, `tests/live/test_live_screen_matrix.gd`, new `tests/live/test_live_post_game_line_score.gd`, `tools/career_playthrough.gd` (report line), and docs (`STABILIZATION_AUDIT.md`, `DECISIONS.md`, `TESTING.md`, `FEATURE_MATRIX.md`, `ONLINE_ARCHITECTURE.md`, `PROGRESS_LOG.md`, this log, the handoff).

**Commands and results (Godot 4.7.2 headless, one process at a time, base `e7b7e9a` plus the changes above):**
| Command | Result |
|---|---|
| `godot_console --headless --path . --import --quit` | exit 0 |
| `res://tests/run_tests.gd` (unit) | exit 0, **1,477 passed, 0 failed** (6 known-noise engine errors) |
| `res://tests/run_live_tests.gd` (live) | exit 0, **153 passed, 0 failed** (2 known-noise engine errors) |
| `creator_studio ... studio_smoke.gd` | exit 0, PASS |
| `simulate_games games=1000 strict=1` (seed 2026, era mid_2010s) | exit 0, 0 of 16 checks outside range |
| `career_playthrough seasons=20 seed=7` | 17 seasons, 0 problems; timeline 88 rows (cap 300) |
| `dynasty_check` | exit 0 (timings only) |
Failures along the way (all explained in the audit): the baseline live run failed locally because the developer machine has a real online config; one later live run failed on a phone-width overtime line score (seed-dependent), reproduced with a probe and fixed.

**Not run:** `economy_check`, `owner_stress`, `ui_playthrough`, `career_balance` (nothing in their code changed; weekly `long-checks.yml`).

**Commit / push / Actions:** commit `7d05455`, pushed to `main`; GitHub Actions CI run 45060877350 finished **success** (the run on the previous commit `e7b7e9a` had failed).

**Remaining:** Stage 2 (authenticity audit), then B0 and the B milestones per the plan.

## Stage 2: Basketball authenticity audit
**Delivered:** `docs/audits/BASKETBALL_AUTHENTICITY_AUDIT.md` (15 findings), `BASKETBALL_DATA_INTEGRITY_MATRIX.md`, `docs/plans/BASKETBALL_AUTHENTICITY_IMPLEMENTATION_PLAN.md`, `tools/audit_identity.ps1` (read-only measurements). Read-only: no `src/` or `data/` change.
**Measured (20 leagues, seeds 5000-5019):** 13.3% of teams have a hashed jersey-number collision; 12.2% have primary/secondary colour contrast below 3:1; 0 `world.validate` problems; no duplicate names, abbreviations or arena names; plausible heights, weights and ages. Correction of an earlier assumption: `FcWorld.validate` already checks one roster per player, retired players on rosters, contracts and the roster maximum.
**Commits:** `a09e7a9` (Stage 2) and `febbfac` (B0 plan, `docs/plans/BROADCAST_PRESENTATION_PLAN.md`), pushed together; GitHub Actions CI run 45061971778 on `febbfac` finished **success**.

## B2: broadcast timeline, and B2b option A: 2D broadcast graphics
**Delivered:** `src/ui/replay/broadcast_timeline.gd` (B2), `broadcast_graphics.gd`, `broadcast_overlay.gd`, `FcScoreBug.show_broadcast`, the team comparison card and overlay wiring in `replay_screen.gd` (B2b A). Tests: `test_broadcast_timeline` (12), `test_broadcast_graphics` (10), `test_live_broadcast_graphics` (7).
**Decisions:** the timeline is a separate pure class over `FcReplayModel` (the model stays small); clutch time is the fourth quarter or overtime, 5 minutes or less, margin 5 or less (D-069, presentation only, constants in the class); the bonus threshold is read from `data/simulation/tuning.json`; a graphic's text never states a fact the events do not hold (no shot clock, timeouts or tip-off).
**Local results (base `febbfac` plus these changes):** import exit 0; unit exit 0, **1,499 passed**; live exit 0, **160 passed**; Studio smoke PASS.
**Screenshot checked by eye:** the owner replay shows the scorebug second line (possession dot, fouls), the scoring strip over the court and the team comparison card.
**Commits:** `e2f1bc9` (B2) and `18872d3` (B2b A), pushed together; CI run 45063748507 on `18872d3` finished **success**.
**Remaining for B2b:** option B (2D camera, projected branded court, camera director logic) and C (replay trails, slow motion, instant replay), lower thirds for lineups (with B5).

## B3: audio infrastructure and captions
**Delivered:** `src/ui/replay/broadcast_audio.gd` (pure mapping from an event to at most three sounds, plus captions), ten procedural sounds in `data/ui/audio.json` on `SFX` and a new `Crowd` bus, `audio_crowd` and `sound_captions` preferences (older settings files get the defaults), a crowd slider and a captions toggle in Settings, and sounds and captions in `FcReplayScreen` (on play and stepping forward; scrubbing and stepping back are silent).
**Decisions:** no recorded or licensed audio (D-069); the crowd favours the home team and groans at a home loss (a presentation choice, documented in the class); captions still show when the game is muted (they exist for players without sound); voice commentary is not part of B3 and stays a later, optional step that would use the operating system's speech only if its quality is acceptable (B7).
**Existing tests changed (extended, not weakened):** `test_audio.gd` now expects the `Crowd` bus and five volume sliders (it checks the crowd volume too).
**Tests:** `test_broadcast_audio` (7), `test_live_broadcast_audio` (4).
**Local results (base `18872d3` plus these changes):** import exit 0; unit exit 0, **1,506 passed**; live exit 0, **164 passed**; Studio smoke PASS.
**Commit / push / Actions:** `ec439b4`, pushed; CI run 45065912855 finished **success**.
**Remaining:** none for B3.

## B2b options B and C: 2D camera, projected court, replay presentation
**Delivered:** `court_projection.gd`, `camera_director.gd`, `camera_rig.gd` (all pure), the broadcast view and ball trail in `src/ui/art/court_view.gd`, the camera and view controls, slow motion, instant replay and REPLAY badge in `replay_screen.gd`, `FcBroadcastTimeline.replay_window`, the gold edge in `broadcast_overlay.gd`.
**Decisions:** the camera director is written once as pure code returning shots as data (court feet, zoom, hold, priority) so a 3D viewer can reuse it; default camera mode is hybrid; the flat view stays selectable; the ball trail and the camera use the replay's illustrative positions and say so in the code docs (no reconstruction yet, B1); an instant replay shows the possession that led to the event, at most 10 events, at half speed, every event whatever the feed filter is; clutch and run emphasis use gold.
**Tests:** `test_camera_director` (13), `test_live_camera` (7), `test_live_instant_replay` (7), replay window tests in `test_broadcast_timeline`. Two test flaws found and fixed while writing them (a vacuous assertion removed, an assertion relying on window length).
**Screenshot checked by eye:** the broadcast view shows the projected court with a home-coloured paint, the camera framing a made shot, the scoring strip, and the camera controls.
**Local results (base `ec439b4` plus these changes):** import exit 0; unit exit 0, **1,520 passed**; live exit 0, **178 passed**; Studio smoke PASS.
**Commit / push / Actions:** `9ab8d52`, pushed; CI run 45068460597 finished **success**.
**Remaining:** none for B2b.

## B1: reconstruction feasibility spike (headless)
**Delivered:** `src/ui/replay/reconstructor.gd`, `reconstruction_validator.gd`, `tools/reconstruct_spike.ps1/.gd`, `tests/unit/test_reconstruction.gd` (6), `docs/validation/B1_RECONSTRUCTION_SPIKE.md`.
**Verdict: PASS.** 40 games, 17,102 events, 28,374 keyframes, 0 validator problems, 40 of 40 repeat builds byte-identical; 19.5% of steps are clock-compressed (rebound 87.9%, dead 37.4%, loose 32.5%, shots/passes/free throws 0%).
**Decisions:** limits chosen before the verdict (22 ft/s players, 45 ft/s ball, 1.5 ft spacing, 0.4 s minimum step); no saved data (the presentation seed comes from the scores, teams and event count); the reconstruction's own time axis, with the planned B4/B6 handling of compressed steps documented.
**Bug found by the validator and fixed:** substituted-out players stayed placed (11 on court).
**Local results (base `9ab8d52` plus these changes):** import exit 0; unit exit 0, **1,526 passed**; live exit 0, **178 passed**; Studio smoke PASS.
**Remaining:** B1b 3D performance prototype, B1c player-model prototype, then the 3D decision.
**Commit / push / Actions (B1):** `f5593b4`, pushed; CI run 45070695237 finished **success**.

## B1b: minimal 3D performance prototype
**Step 1 (pre-registration), commit `baa3a43`:** `docs/validation/PERFORMANCE_THRESHOLDS.md` (machine, fixed benchmark game seed 1, run definitions, measured 2D baseline, limits by the fixed rules), `tools/perf_benchmark.ps1/.gd`, and a fix for a per-frame engine error found by the benchmark in the B2b broadcast view (degenerate centre-circle polygon; `FcCourtView.circle_polygon` plus a regression test, unit 14 passed in `test_camera_director`). CI run 45072291597 on `baa3a43` (result recorded below).
**Step 2:** the prototype `prototypes/b1b/arena_prototype.gd`, the 3D mode of the benchmark tool, and `docs/validation/B1B_3D_PERFORMANCE_PROTOTYPE.md`.
**Verdict: PASS (rendering budget, development machine only).** Frame time p95 0.76 ms and p99 0.88 ms (limits 16.6 and 33.3); one slow frame in 237,778; working set 202 to 280 MB (limit 2,048); video memory 26 to 32 MB (limit 1,024); leak growth 8 MB (limit 10); warm load 35 ms, cold 2.1 s (limit 5 s). Assumption confirmed: instanced crowd cards, a shadow-casting light and a live `SubViewport` scoreboard all work under `gl_compatibility`.
**Not hidden:** one 176.67 ms frame, working-set growth to 280 MB in the first run, leak growth close to its limit, strong hardware.
**Decisions:** budgets for B1c and B4 registered before they are measured (ten characters at most 6 ms p95 added, 200 MB working set, 150 MB video).
**Test status:** the prototype is throwaway and not covered by the suites; only tools, a prototype folder and docs changed in this step, so the suites were not re-run locally (CI runs them).
**Remaining:** B1c player-model and animation prototype, then the 3D decision.
