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

**Commit / push / Actions:** see the entry below once pushed.

**Remaining:** Stage 2 (authenticity audit), then B0 and the B milestones per the plan.
