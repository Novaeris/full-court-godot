# Testing

## Strategy
1. **Automated unit tests** for every system, run headlessly, fixed seeds.
2. **Simulation stress tests** (planned): thousands of games / multi-season runs checking plausibility (scores, percentages, finances, roster/contract validity).
3. **Manual playtesting** by the founder for feel, usability and fun. Claude provides step-by-step instructions with each UI feature.

## Running tests
From the project folder in PowerShell:

```powershell
./tools/run_tests.ps1
```

Or directly:

```powershell
godot_console --headless --path . --import --quit
godot_console --headless --path . --script res://tests/run_tests.gd
```

Run the `--import` line whenever a new `class_name` file is added (it refreshes Godot's class list). Exit code 0 = all passed, 1 = failures. Output ends with `Tests: N passed, M failed`.

## Writing a test
Create `tests/unit/test_<thing>.gd`:

```gdscript
extends FcTestCase

func test_something() -> void:
	assert_eq(1 + 1, 2)
```

Methods must start with `test_`. Available: `assert_true`, `assert_eq`, `assert_between`, and `before_each()` for setup. Use fixed seeds (`FcRng.new(123)`).

## Coverage
| Area | Tests |
|---|---|
| FcRng (determinism, forking, state restore, huge-seed JSON regression, distributions) | 8 |
| FcGameState (validation, round trip incl. RNG position) | 4 |
| Staff (definitions, roles, validation, retirement, round trip, contracts, world rules for unique roles / two jobs / dangling refs, old snapshots without staff) | 18 |
| Save system (round trip, slot-name safety, backups, checksum/truncation/garbage detection, interrupted-save and crash recovery, version rejection, migrations, listing, delete, autosave, integrity warnings, staff persistence) | 19 |
| FcIdGenerator (sequence, independence, save round-trip) | 3 |
| FcDate (validity, leap years, ISO round trip, age math) | 4 |
| Attribute system (shipped JSON valid, catalog errors, set validation, clamping, save compatibility, adding attributes) | 7 |
| FcPlayer (validation, positions, retirement, round trip, exact float round trip, sparse/corrupt data) | 11 |
| FcLeague / conferences / divisions / world integrity with leagues / old snapshots | 8 |
| League customization (real city data, areas, exact cities, nicknames, sizes 4-64, equal divisions for every valid size, geographic conferences and divisions, nationality mix, validation messages, save round trip) | 22 |
| News feed and stored box scores (cap, champion/award/draft news, injury news, box scores kept for the owner's team, saving, UI news tab and box score text) | 7 |
| AI trades (a clear win-win happens, rosters and contracts stay consistent, no-trade clauses, both sides must gain, salary rules, several offseasons stay valid) | 6 |
| Medical staff effects (reading staff skills, prevention reduces injuries, rehabilitation shortens them) | 3 |
| Injuries (rate and severity, switch-off, leaving the game, durability, lineup exclusion, tracking through a season, countdown by team games, saving, offseason healing, permanent loss) | 10 |
| User interface smoke tests (every screen builds with data, league creation and its errors, team choice, dashboard, all seven tabs, playing through a season and into the next, saving and loading, owner controls, dynasty mode, money formatting) | 12 |
| Game controller (new game, advancing days, playoffs flow, next season, three years valid, owner price/marketing/facilities, hiring and firing, owner report, save/load determinism mid-season and between seasons) | 11 |
| Business model (businesses exist, demand and price, best price fills the arena, markets, revenue/expense arithmetic, plausible league margins, winning builds interest, luxury tax paid and shared, debt, human vs AI pricing, facilities, saving, validation) | 14 |
| Player progression (growth, decline, physical vs mental, development rate / work ethic / coach, ranges, reproducibility, retirement odds, career arc) | 9 |
| Offseason (3 seasons in a row stay valid, legal rosters, retirements, talent stability, draft order and rookie scale, market values, reproducibility, hard cap) | 10 |
| Calendar (date arithmetic, every game placed once, pair counts match the rules, nobody twice a day, season length, back-to-backs, streaks, reproducibility) | 9 |
| Standings and tiebreakers | 10 |
| Season engine (calendar, playing days, consistency of records and statistics, playoff bracket and byes, home court pattern, awards, reproducibility, save/load, validation) | 12 |
| Simulation (ratings recipes, box-score arithmetic and plus-minus, determinism, plausibility of 16 league averages, overtime, ratings/shooting/defense/rebounding effects, home court, coach pace and three-point style, rotations and minutes, fatigue, blowouts, tuning overrides, no world mutation) | 27 |
| Extra salary rules and 80-game seasons (tax sharing, repeater tax, restriction line, rookie scale, cornerstone extension, cap holds, sign-and-trade, no-trade, validation, old-save behavior, even seasons for every size) | 20 |
| League rules (valid sizes and layouts, season arithmetic and suggestions for every size, matchup planner fairness, playoff formats and validation, soft/hard/no-cap signing and trade rules, contract rules, rules in generated leagues, payroll vs hard limit, team naming, nationality share, sensitive places) | 39 |
| Generation (data validity, names, player realism by position/level/age, tendencies, staff specialization, full league validity, reproducibility, uniqueness, contracts/payroll, free agents, custom configs, save round trip) | 27 |
| FcTeam, FcRoster, FcCity, FcArena | 8 |
| FcContract (cap hit, guarantees, options, validation, round trip) | 7 |
| FcRepository / FcMemoryRepository | 2 |
| FcWorld (integrity checks, round trip, JSON text round trip, duplicate ids) | 11 |
| Everything else (simulation, generation, save files, league ops) | not built yet |

Shared sample builders for tests live in `tests/support/test_data.gd` (`FcTestData`).

Last verified: 363 passed, 0 failed (Godot 4.7.2).

Tests that touch disk use `user://test_saves` and clean up in `after_each()`. Inspection tools: `./tools/inspect_data.ps1`, `./tools/inspect_saves.ps1`, `./tools/simulate_games.ps1 [games=1000] [seed=2026] [era=mid_2010s] [tune=key:value,...] [box] [mirror] [leaders]` (stress test: 16 league averages vs the era's realistic ranges, one full box score, home-court check, full-season individual leaders), `./tools/finances.ps1 [seasons=2] [seed=...]` (every team's revenue, expenses, profit, valuation), `./tools/play_seasons.ps1 [seasons=5]` (several seasons with offseasons and a league-health table), `./tools/play_season.ps1 [option=value ...]` (plays a whole season and prints standings, playoffs, champion, awards), `./tools/generate_league.ps1 [option=value ...]` (e.g. `areas=europe teams=16 conferences=2 divisions=2`). The runner was also verified to report failures (exit code 1).

## Known issues / limits
- Runtime script errors in a TOOL script (not the test runner) can leave Godot running forever; use `timeout` when running tools from a shell.
- Simulation tests run hundreds of games (about 25 s of the suite).
- Runner discovers methods by name only. A test file with a syntax error is reported as a FAIL (an earlier version hung forever instead; fixed).
- GDScript gotcha: `var x := <untyped value>` is a parse error in this project (warnings are errors). Annotate the type: `var x: String = ...`.
- No stress-test tooling yet (planned with the simulation engine).
