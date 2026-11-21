# Checkpoint 4: Owner Overview and Roster (Visual Identity Phase F1)

Date 2026-11-21. Screenshots in `phase_f/`: `owner_Overview_1280x800.png`, `owner_Roster_1280x800.png`, `owner_Standings_1280x800.png`, `owner_Schedule_1280x800.png` (a real league after 20 days; regenerate with `tools/screenshot.gd screen=<Tab> days=20`).

## What changed
- **Architecture:** the four tabs are built in `src/ui/owner/` (`FcOwnerOverview`, `FcOwnerRoster`, `FcOwnerStandings`, `FcOwnerSchedule`) from a small `FcOwnerContext` (the controller plus say / refresh / open-dialog callables and a per-team look cache). `app.gd` keeps `_tab_overview`, `_tab_roster`, `_tab_standings`, `_tab_schedule` and `build_tab` as one-line delegates, so every public name tests and tools use still exists. app.gd lost another 250 lines (sized-label baseline 80 to 69).
- **Roster:** an `FcTable` with each player's portrait (head crop), position, age, height, overall and potential as rating badges, salary, contract end plus a bar of the contract played, per-game stats and health. All 13 old columns and all three actions (extend, release, profile) are kept; double-clicking a row opens the profile. Sorting works on every column.
- **Standings:** one table per conference with the team crest and name, W, L, Pct, GB, L10, Strk; the user's team carries a "You" tag.
- **Schedule:** crest and name of each opponent, the result as a W or L tag with the score (never colour alone), the box-score button, double-click for the box score.
- **Overview:** a dashboard: record tiles, the next game as two crests facing each other, the owner report with an approval meter and a profit trend, your conference snapshot with crests, the latest news, the owner career and job offers (a table plus the take-the-job button), the league rules. Every old number and sentence is still there. The **profit trend only draws from at least two settled seasons** (`FcSparkline`, fed by a new read-only `controller.finance_series()`); with fewer it shows nothing rather than inventing a line.
- **Shared parts added:** `FcSparkline`, `FcTeamChip` (crest plus name), `FcStatusChip.set_tone`, FcTable gained `fill` cells and a header-padding fix.

## Existing tests changed (D-058)
`test_every_tab_shows_data` reads FcTable rows instead of Tree items for Roster, Standings and Schedule; the layout baseline for `owner_roster` and `owner_schedule` height grew (273 to 550 and 277 to 431: the tables now have a real minimum height, still inside the 800x600 Owner minimum window); `tools/click_test.gd` clicks FcTable rows. New: `test_ui_owner` (11 tests: every old column and action is still present, best player first, selection, results carry a letter, the overview keeps every section and shows the owner report and approval after a season, sparkline draws only real points, finance_series order).

## Reviewed in the screenshots, fixed
Team names were missing (cells were narrower than their column): custom cells can now fill their column. A late-bound row kept the first layout: the table now re-windows when its height settles. Header titles ("Contract", "MPG") were clipped by button padding: header buttons got their own padding. The KPI strip stacked into a column: the top row is now a box with the strip expanding.
Not verified: nothing here has been tried with a real mouse wheel or on the 800x600 window by eye (the layout test and matrix cover the size).
