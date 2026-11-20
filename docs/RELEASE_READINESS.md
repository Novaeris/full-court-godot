# Release readiness: UI polish and presentation (Phase 13)

Written 2026-11-20 at the end of the UI/UX Polish milestone (docs/UI_POLISH_PLAN.md, decisions D-047 to D-054). It says what was verified, by
which command, and, just as important, what was NOT verified because it needs a person, a device or a lawyer.

## What was checked, and how

| Area | Evidence |
|---|---|
| Unit tests | `godot_console --headless --path . --script res://tests/run_tests.gd` (exit 0). Both runners now fail a test on any runtime script error. |
| Live UI tests | `godot_console --headless --path . --script res://tests/run_live_tests.gd`: tweens, timers, focus, real input (touch emulated in a phone-sized viewport), pack reveal, audio voices. |
| Pack outcomes, games and saved profile unchanged | A digest of 400 pack rolls, 30 simulated Dynasty games and the saved profile for a fixed seed is **identical** on the commit before the UI work (6c963ac) and on the final commit (checked with a temporary git worktree). |
| Simulation calibration | `tools/simulate_games.ps1` with 1000 games and `strict=1`: 0 of 16 checks outside the realistic range. |
| Economy | `tools/economy_check.gd` (12 teams, 15 seasons): RESULT ok. |
| Click tests | `tools/click_test.gd` (67 real mouse clicks, 0 problems) and `tools/career_click_test.gd` (22 clicks, 0 problems; it now walks the creator's five steps). |
| Creator Studio | `studio_smoke.gd` PASS with the shared theme. |
| Dynasty health | `tools/dynasty_check.gd`: 50 games with saves, a tournament, save and reload OK. |
| Window shapes | Dynasty tabs build at 360x800, 412x915, 800x600, 1024x768, 1280x800, 1920x1080 and 2560x1080 (`test_release_readiness.gd`); screenshots in `docs/validation/ui/final/` (6 sizes, 7 screens). |
| Phone fit | Every Dynasty screen needs at most 412 px in the mobile layout (hard test), also with Large text. |
| Owner and Career minimum window | Every Owner and Career screen needs at most 800 px (D6; hard test). |
| Navigation | Every Dynasty tab is on the bar or in More; Back from every Dynasty tab reaches the main menu; every Owner tab builds. |
| Collection performance | 500 and 2,000 cards build in a time budget with one node per card (`test_ui_collection.gd`); a Dynasty screen builds in a few milliseconds. |
| Accessibility | Contrast of every text colour on every surface, rarity colours on their cards, mastery frames; every enabled button and card takes keyboard focus; reduced motion; three text sizes; hints can be turned off. |
| Audio | 17 sounds built by the game, deterministic, never clipped; a pack reveal asks for the matching sting; skipping is quiet; the game is fully usable muted. |
| Style discipline | Style lint and layout ratchets only ever tighten (`tests/support/*_baseline.json`). |

## What was NOT verified (needs a person, a device or a decision)

- **How it sounds.** The headless run has no speakers. The built sounds are checked for length, loudness and key, not taste. A listening review is
  needed; any sound can be replaced by an original recording (listed with its source and licence in `assets/audio/SOURCES.md`, enforced by a test).
- **How it feels on a real phone.** Touch is emulated, safe areas and the Android back button are wired and unit-tested but never ran on hardware. No
  iOS or Android build was made.
- **Controller and screen reader.** Focus reach is tested; a real gamepad and a screen reader were not used. Cards expose accessible text but a screen reader pass is open.
- **Frame rate on real GPUs.** Build times are measured; frame times and animation smoothness need a real window on target hardware (the gl_compatibility renderer was chosen for mobile).
- **Ultrawide (21:9).** Everything builds and is readable, but Dynasty content stretches across the full width. A maximum content width on very wide windows is a good follow-up.
- **Owner Mode tabs.** The Owner screen keeps the older table-based tabs inside the new shell (D6). The Overview uses the new KPI strips; converting the other twelve tabs to the kit is incremental work.
- **GitHub Actions.** The CI workflow now runs the live tests and links the Studio assets, but it has not been seen running on GitHub yet.
- **Legal.** Player names, cards and branding are original, the sounds are built by the game and the fonts and icons are open-licence, but a lawyer should review before any commercial release (CLAUDE.md rule 9).

## Known limits to carry forward

- Music is not included (the Music bus exists and is empty).
- Player visuals are tiers 0 to 2 (monogram, card art, procedural figure); full-body pose sprites and 3D (tiers 3 and 4) are designed slots, not built (D5).
- Engine messages such as "Lambda capture ... was freed" appear when a live test frees a pack reveal while a tween runs; they are not script errors and do not fail a test.
