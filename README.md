# Full Court

A basketball management simulation (Godot 4.7, GDScript). Three modes are planned: Owner Mode (being built first), Career Mode (create a player, RPG progression) and Dynasty Mode (a card-collecting game). A watch-only Spectator mode also exists for testing.
Real cities and countries; original franchises, players and staff.

## Play it
1. Open **Godot 4.7** (standard edition) and choose **Import**, then select `project.godot` in this folder.
2. Press **F5** (or the Play button). The main menu opens.
3. **New Game**: choose the league name, where the teams are from, the number of teams (only sizes that divide into even divisions are offered), the salary cap style, the style of play, the season length, the draft lottery and the game mode (Owner Mode is the one being built). Then choose your team.
4. On the dashboard use **Next Day / Next Week / Next Month / To End of Regular Season**, then **Play All Playoffs**, then **Begin Offseason** (draft, then free agency) and **Finish Offseason and Start Next Season**.
5. Tabs: Overview, Standings, Schedule (box scores), Roster (profiles, extensions, release), Finances (prices, loans, shop, arena projects, league comparison), Staff (your GM's duties and direction, hire and fire), Draft (scouted board), Market (free agents and offers), Trades (players and draft picks), History (Hall of Fame, records), News, League (leaders, champions).
6. **Save** writes `slot_1`; the game autosaves at the start of each offseason stage. **Continue** on the main menu loads the latest save.

The screens are plain tables and buttons, built to test the game. `docs/PROGRESS_LOG.md` lists what to try first.

## Tools (PowerShell, from this folder)
| Command | What it does |
|---|---|
| `./tools/run_tests.ps1` | Runs all automated tests (about 1 minute) |
| `./tools/generate_league.ps1 [options]` | Builds a league and prints teams, rules, top players |
| `./tools/play_season.ps1 [options]` | Plays one full season and prints standings, playoffs, awards |
| `./tools/play_seasons.ps1 seasons=6` | Plays several seasons with offseasons and a health table |
| `./tools/simulate_games.ps1 [games=1000] [leaders]` | Checks game statistics against real-league ranges |
| `./tools/finances.ps1` | Every team's revenue, expenses, profit and value |
| `./tools/owner_playthrough.ps1 strategy=builder` | Plays seasons as an owner with a scripted strategy and prints the books |
| `./tools/ui_playthrough.ps1 seasons=3` | Plays Owner Mode through the real screens and checks nothing breaks |
| `./tools/click_test.ps1` | Clicks through the game with simulated mouse clicks |
| `godot_console --path . --script res://tools/screenshot.gd -- screen=Roster out=shot.png` | Saves a picture of a screen (opens a window) |

## Where things are
- `docs/` design, architecture, decisions, roadmap, testing, progress log (start with `docs/PROGRESS_LOG.md`)
- `data/` balance and content as JSON (attributes, cities, names, rules, simulation tuning, finance)
- `src/` code: `core`, `data`, `gen`, `sim`, `league`, `save`, `game`, `ui`
- `tests/` automated tests

Nothing is published: this is a local Git repository with no remote.
