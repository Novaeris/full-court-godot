# Full Court

A basketball management simulation (Godot 4.7, GDScript). Three modes are planned (Owner, Career, Dynasty); Owner Mode is being built first.
Real cities and countries; original franchises, players and staff.

## Play it
1. Open **Godot 4.7** (standard edition) and choose **Import**, then select `project.godot` in this folder.
2. Press **F5** (or the Play button). The main menu opens.
3. **New Game**: choose the league name, where the teams are from, the number of teams (only sizes that divide into even divisions are offered), the salary cap style, the style of play (early / mid / late 2010s NBA) and Owner or Dynasty mode. Then choose your team.
4. On the dashboard use **Next Day / Next Week / To End of Regular Season**, then the playoffs, then **Start Next Season**. Tabs: Overview, Standings, Schedule, Roster, Finances (set ticket price and marketing, invest in the arena), Staff (fire and hire), League (leaders and champions).
5. **Save** writes `slot_1`; a new season autosaves. **Continue** on the main menu loads the latest save.

The screens are a first version built for testing the game rules. They are plain tables and buttons.

## Tools (PowerShell, from this folder)
| Command | What it does |
|---|---|
| `./tools/run_tests.ps1` | Runs all automated tests (about 1 minute) |
| `./tools/generate_league.ps1 [options]` | Builds a league and prints teams, rules, top players |
| `./tools/play_season.ps1 [options]` | Plays one full season and prints standings, playoffs, awards |
| `./tools/play_seasons.ps1 seasons=6` | Plays several seasons with offseasons and a health table |
| `./tools/simulate_games.ps1 [games=1000] [leaders]` | Checks game statistics against real-league ranges |
| `./tools/finances.ps1` | Every team's revenue, expenses, profit and value |

## Where things are
- `docs/` design, architecture, decisions, roadmap, testing, progress log (start with `docs/PROGRESS_LOG.md`)
- `data/` balance and content as JSON (attributes, cities, names, rules, simulation tuning, finance)
- `src/` code: `core`, `data`, `gen`, `sim`, `league`, `save`, `game`, `ui`
- `tests/` automated tests

Nothing is published: this is a local Git repository with no remote.
