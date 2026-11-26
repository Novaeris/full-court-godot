# Franchise Experience Overhaul: validation record

Evidence for each milestone of [the programme](../roadmap/franchise-experience-overhaul.md).

- **Test totals** are in [TESTING.md](../TESTING.md) only.
- **Pictures** live in `docs/validation/franchise/` (that folder has a `.gdignore`):
  - `before/`: the code before the programme (commit `37d86a9`), at 1280x720 and 1920x1080
  - `after/`: the final state (M16)
  - one folder per milestone for its own screens

## Visual review checklist (applied to every new or redesigned screen)
| Check | Pass condition |
|---|---|
| Hierarchy | One clear hero. The eye reaches the most important number first. |
| Identity | Team colours, crest and wordmark where the screen belongs to a team |
| Density | No large empty areas at 1280x720. At 1920x1080, content uses the width up to the 1600 px maximum. |
| Spacing and type | Token spacing only. At most 3 type sizes per region. |
| States | Hover, focus, selected, disabled and empty states all present |
| Motion | Screen, tab and selection transitions; reduced motion respected |
| Resize | Viewport audit passes from 800x600 to 2560x1080 at 3 text sizes; no overflow |
| Honesty | No invented data. Future dates show no results. Actions match the stored data. |

## Milestone records
### M0
- **Before pictures:** `franchise/before/`. 19 screens at 1280x720 and 1920x1080 (menu, the 13 Owner tabs, Owner game day, post-game, replay, Career hub, Dynasty hub).

### M1
- Pictures: `franchise/m1/gallery_season_1600x1900.png` (every new component), and Overview, Trades, Finances, Staff and Market at 1280x720, showing the extracted tabs unchanged under the new franchise backdrop.
- Reviewed by eye. Two defects were found and fixed before the commit:
  - The team header band drew white (a gradient texture built inside `_draw` is not ready on its first frame). It now uses vertex colours.
  - The shot chart showed grid lines (overlapping translucent cells). It now uses pixel-aligned cells.
- Tests: unit 1,756 passed, live 241 passed, `validate_project` 0 problems, Studio smoke PASS.

### M2
- `test_franchise_data` (15 tests) covers ids, lines, day logs, the integrity check (including tampering), game logs, columns, transactions, ratings, numbers, objectives, preferences, the ledger, availability, and migration of the real v4 fixture with an exact save round trip.
- Simulation unchanged: `tools/simulate_games.gd games=400 strict=1` gives identical output at M1 and M2, apart from timing. All 16 checks are in range.
- Save size: `tools/play_seasons.ps1 seasons=50 teams=12 seed=7` gives a 6.1 MB save (5.2 MB before; the limit is 1.5x). Written in 0.9 s, loaded in 1.1 s.
- Fixed during M2: two reputation tests and two version tests were updated. Objectives now count in the one place a season counts (`_record_owner_season`), so they can never be counted twice.

### M3
- Pictures: `franchise/m3/hq_1280x720.png` and `hq_1920x1080.png` (30 days into a season).
- Reviewed by eye. Fixed before the commit:
  - Wrapping labels inside a flow container collapsed into vertical text.
  - A tie with the last playoff team read "0.0 games behind".
  - A duplicate "Game day" button.
- `test_franchise_hq` checks every snapshot number against the game's own records: the standings, the real playoff builder, the stored result line, stats leaders, payroll. It also checks that the featured matchup opens that game.

### M4
- Pictures: `franchise/m4/` has the roster cards, and the player page Overview at 1280 and 1920, Shooting and Game Log.
- Fixed by eye before the commit:
  - The card grid scrolled inside the scrolling page and showed one row. It now grows to fit.
  - Jersey numbers bunched in the 50s; the preference now uses FNV-1a with a realistic spread.
  - Shooting labels were truncated.
- `test_player_page` (6) checks:
  - the game log equals games played, with real results;
  - the three shot kinds add up to all field-goal attempts;
  - no tabs are invented for a player without data;
  - the full page opens from the roster and Back returns;
  - the card view's actions use the selected card.

### M5
- Pictures: `franchise/m5/` (the Game Center before and after a game at 1920x1080, the schedule at 1280x720).
- `test_game_center` (6) checks the following:
  - The actions match the availability rules: the user's next game, another team's game (follow, then a replay), and an unrecorded game (result line only, no summary is invented).
  - Playing through a game advances only up to its day, and integrity stays clean.
  - Routes come from the schedule and the Game day button.
- The live test `test_live_game_day` now follows Game day into the Game Center, then "Play and watch".
