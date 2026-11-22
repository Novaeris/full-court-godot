# Stabilization audit (Stage 1 of the master plan)

Baseline commit: `e7b7e9a` (2026-11-22). Scope fence: code was changed only to fix reproduced P0/P1 defects (and test-infrastructure defects), each with a regression test; no saved-data shape changed (`FcVersion.DATA_VERSION` and `DYNASTY_DATA_VERSION` untouched). Fresh totals are in [TESTING.md](TESTING.md) only.

Labels: **Confirmed defect** (reproduced), **Architectural risk**, **Recommendation**, **Unverified**, **Decision**. Severity: P0 critical, P1 significant correctness, P2 improve/document, P3 cosmetic or debt.

## 1. Baseline and evidence
- Working tree clean at start. `main` at `e7b7e9a`; the last GitHub Actions run on it (CI, run 45046140970) was **red**: unit 1471 passed, live 151 passed and 1 failed.
- Fresh local runs at the baseline (HEAD plus one test fix): import exit 0; unit 1471 passed, 0 failed (6 known-noise engine errors); live 151 passed, 1 failed; Creator Studio smoke PASS.
- `simulate_games games=1000 seed=2026 era=mid_2010s strict=1`: exit 0, **0 of 16 checks outside the realistic range** (ranges in `data/simulation/eras.json`). No golden output file exists for this tool (none committed); the unit "determinism" and "16 averages" tests are the guard.
- Tools not run, with reason: `economy_check`, `owner_stress`, `ui_playthrough`, `career_balance` (nothing in the Owner economy or Career balance code changed in Stage 1; they run weekly in `long-checks.yml`). No Dynasty long-run economy tool exists (S1-D-gap).
- Tools run: `career_playthrough seasons=20 seed=7` (17 seasons, 0 problems), `dynasty_check` (exit 0, timings only).

## 2. Confirmed defects, fixed (each with a regression test)
| ID | P | Finding | Fix | Regression test |
|---|---|---|---|---|
| S1-CI-1 | P1 | CI on `main` was red: `test_a_configured_screen_shows_the_form...` checked the "busy" indicator two frames after the click; on a fast machine a refused connection answers before that, so the test failed on GitHub (passed locally) | Check the busy state at the click, which is synchronous (`online_screen.gd:_run`) | the same test, now timing-independent |
| S1-TEST-1 | P2 | Live online tests were not isolated from the developer's real `user://online_config.json` and `online_session.json`: on a machine set up for online, "no config" failed and a test could touch a real session | `before_each` injects `FcOnlineController.new(null, test_path)` | `test_live_online_screen.gd` (5/5) |
| S1-UI-2 | P1 | The post-game **line score** was fixed-width per period: a game with an overtime (7 columns) is 348 px, 2 OT 400 px, wider than a 360 px phone, pushing the whole Dynasty play tab sideways | The grid sits in a centred, sideways-scrolling holder (`post_game_screen.gd:_line_score`) | new `test_live_post_game_line_score.gd` (failed before at 348/400/504 px; passes after) |
| S1-TEST-2 | P2 | `test_every_dynasty_screen_fits_every_window_shape_and_text_size` failed about one run in twenty: the Dynasty profile seed is time-based, so the first game's result (an overtime) varied | Fixed seed in the test; the overtime case has its own test above | the matrix test (now repeatable) |
| S1-ONL-1 | P1 | **Signatures did not survive a JSON round trip.** Godot reads every JSON number as a float, so `{"n": 5}` signed by the client became `{"n": 5.0}` on the server and failed verification: a real transport would reject valid requests | `FcOnlineCrypto.canonical` writes whole numbers as integers | `test_a_signed_request_still_verifies_after_a_json_round_trip` (failed before) |
| S1-ONL-2 | P1 | **Replay after nonce eviction.** Nonce memory was the newest 200 per account; after 200 newer requests inside the 120-second window, a captured request could be replayed and run again | Nonces are held until `issued_at + MAX_SKEW` has passed; a hard cap of 2000 refuses new requests (`rate_limited`) instead of forgetting old nonces | `test_an_old_nonce_is_remembered...`, `test_nonce_memory_is_released...`, `test_a_flood_of_distinct_nonces...` (failed before) |
| S1-ONL-3 | P2 | A `request_id` reused for a **different** command returned the cached answer (and receipt) of the first command | The cache stores a fingerprint of command and params; a mismatch is refused (`request_conflict`) | `test_a_request_id_cannot_be_reused_for_a_different_command` (failed before) |
| S1-ONL-4 | P2 | Nonce and request id had no length limit | 64-character limit, `bad_request` | `test_oversized_nonces_and_request_ids_are_refused` (failed before) |
| S1-SIM-1 | P3 | The `game_simulator.gd` header said injuries and intentional fouling were not simulated; both are (`EV_INJURY`, `FOUL_INTENTIONAL`) | Comment corrected | none (comment) |
| S1-DOC-1 | P2 | D-066 text ("recommended, not yet approved", "nothing is built yet") disagreed with D-068 and the feature matrix; D-060 to D-062 lived only in PROGRESS_LOG | Append-only status notes and pointers in DECISIONS.md; one status sentence used in ONLINE_ARCHITECTURE and FEATURE_MATRIX | docs |

## 3. Hypotheses tested and refuted
- **S1-CAR-1** (the Career timeline cap of 300 rows drops early moments): a 17-season career holds 88 rows with every kind present from the first year (`career_playthrough`, with a report line added to the tool). Not a defect at this scale. Unverified for other archetypes and seeds.
- Ladder: a season is paid once (request id `ladder_season:<season>`), tier credits once per season (`reached` list plus request id `ladder_tier:...`), the floor is respected, history is capped at `history_limit`. Skipping seasons does not create phantom payments. Covered by `test_dynasty_ladder.gd` (11 tests).
- Economy: `FcDynastyEconomy.apply` is idempotent by request id and refuses a different transaction under the same id (`request_conflict`); failed commits roll back through `FcDynastySession.commit`.

## 4. Backlog (not fixed in Stage 1; none blocks the next milestone)
| ID | P | Finding | Why deferred |
|---|---|---|---|
| S1-ONL-5 | P2 | An identical envelope re-sent after a lost response is refused (`replayed`); the client must re-sign with a **new nonce** and the **same** request_id | By design, now documented in the server header; a client library will do it |
| S1-ONL-6 | P2 | `play_match` mutates two profiles in sequence with no rollback and no concurrency control | Safe in one process; a real server needs per-account serialisation (persistence section) |
| S1-ONL-7 | P2 | `register` has no rate limit or proof of identity | Sign-in is Supabase (D-068); a deployment requirement |
| S1-ONL-8 | P2 | The matchmaker's match counter restarts at 1 and the server key is regenerated on restart, so match ids and seeds repeat or change after a restart | Needs the persistence design |
| S1-ONL-9 | P3 | Session keys are held in plaintext on the server (needed for HMAC) | Deployment: encrypt at rest |
| S1-ONL-10 | P3 | Display names are not unique | Product decision |
| S1-DYN-1 | P3 | `profile.processed_requests` is never trimmed (about 40 bytes per request in every save) | Harmless at current sizes; trimming would weaken idempotency |
| S1-DYN-2 | P3 | A ranked rating at the floor is not zero-sum online (the loser clamps to the floor, the winner gains in full) | Plausibly intended; documented |
| S1-DYN-3 | P3 | Flipping the active Dynasty season back and forth pays once but soft-resets the rating each time and repeats history rows | Needs a content-release scenario |
| S1-D-gap | P2 | No tool measures Dynasty reward inflation or goal reachability over a long run | A later milestone |

## 5. Areas not verifiable automatically
Visual quality of the screens, real Supabase behaviour (no project exists; the client is unverified against one), mobile devices, concurrency (no transport), and Phase 3 historical accuracy beyond the existing invariants tests.

## 6. Phase summary
- **Phase 2 (replay):** recording never changes a game (`test_game_events.gd`), the log survives save/load and ignores damaged rows, a missing log gives an empty model (`FcReplayModel.build`). Not exhaustively re-audited across the three modes' screens.
- **Phase 3 (history):** invariant tests on a real played league (`test_franchise_history`, `test_rivalries`, `test_storylines`). Known limits kept: league players have no stored jersey number (hashed display number only), regular-season rivalry history is limited, rivalries come mostly from playoffs and shared divisions.
- **Phase 4 (Career):** timeline rows dedupe on year, kind and text; legacy and timeline tests pass; a 17-season playthrough has no problems.
- **Phase 5 (Dynasty):** see section 3 and the backlog.
- **Phase 6 (online):** four defects fixed (two security-relevant); see ONLINE_ARCHITECTURE.md for the security review, persistence requirements and deployment gaps.

## 7. Stage 1 acceptance
0 open P0. Every P1 found is fixed with a regression test that failed first. No blocking P1 remains for B2. Save versions unchanged. Fresh results are in TESTING.md; the record is in AUTONOMOUS_WORK_LOG.md.
