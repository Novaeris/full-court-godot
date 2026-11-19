# Testing

## Strategy
1. **Automated unit tests** for every system, run headlessly, fixed seeds.
2. **Simulation and economy stress tests** (built, see below): `simulate_games` (16 league averages, close games, overtime), `economy_check` (decades of AI-only leagues: profit, cash, debt, payroll, titles), `owner_stress` (careful, naive and reckless owners), `ui_playthrough` (50 seasons through the real screens) and `click_test`. They exit with code 1 on a breach, so CI and scripts can rely on the exit code.
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
| Career statistics and archiving (career rows, accumulation, no double counting, archived seasons keep history, size reduction, active seasons protected, saving) | 7 |
| GM thresholds follow the league rotation level; no bets on very old players | 2 |
| Money rules (revenue sharing and tax votable and scaled, vote direction, reasons for the smaller versions, roster limit sync regression) | 6 |
| Relocation (plan, move effects and fee, gap, struggling team, owner proposal and vote, voting, saved) | 7 |
| Expansion draft (unprotected players only, one per team, contracts move, legal rosters, owner protects, skipping, saved) | 4 |
| Expansion (plan, complete new teams and valid league, plays a season and the draft, 64 ceiling, three-quarter vote and gap, enacted through the meeting) | 6 |
| Influence and lobbying (income, costs, turning votes, own proposal, saved) | 4 |
| Owners meeting follow-ups (roster maximum trims rosters, cap changes refit contracts, a lower cap is only proposed when affordable) | 3 |
| Owners meeting (agenda stable and valid, every proposal kind changes the rules, votes follow the situation and vary by year, majorities, controller flow, skipping, saved, cap scaling) | 9 |
| Practice facility and medical center (effects, level cap, injuries shorter, saved) | 3 |
| History tab shows the ownership career | 1 |
| Playoff ticket premium (attendance falls with price, sweet spot, saved, setter) | 3 |
| Hard limit enforced after raises; old contracts forgotten (bounded growth) | 2 |
| AI trade offers (valid and stable, change every two weeks, accept swaps players, declined hidden, none in spectator/draft/playoffs) | 5 |
| Owner career (reputation recorded once a season, offers only at season end and stable, better reputation opens better teams, transfer once a season, agreements dropped, saved, old Dynasty saves load as spectator) | 7 |
| Sponsorship contracts (stable distinct offers priced from the market, two slots, fixed pay and bonuses and expiry, saved, controller) | 6 |
| Staff negotiation (price vs years, hiring with terms, keep or lose expiring staff, GM keeps good staff, saved) | 5 |
| Suggested ticket price follows demand | 1 |
| GM grade independent of season length | 1 |
| League finance comparison (empty before a season, sorted, ranks) | 1 |
| Concessions and merchandise (price sweet spot, tiers trade sales for stock costs, premium needs a strong brand, saved, setters) | 5 |
| Business executives change the books (sponsorship, overhead, interest, none = worse) | 2 |
| In-season GM injury cover (signs a replacement, weekly limit, off by default, full roster makes room) | 3 |
| Owner is told when staff change | 1 |
| GM direction (defaults/validation/save, budget limits, philosophy changes valuation and draft choice, tight budget stops re-signing, trades only when the direction calls for it, report card) | 7 |
| GM delegation (defaults, save, nobody re-signed by default, GM re-signs and runs the draft, GM signs free agents, AI free agency skips a hand-run team) | 6 |
| AI trades with picks (a pick sweetens a deal, market stays consistent) | 2 |
| Trades with full rosters (regression) | 1 |
| Draft pick trading (ownership, free gifts, refused asks, valuation order, invalid picks, used in the draft and pruned, saved) | 8 |
| Draft workouts (sharper report, character note, limited slots, saved) | 2 |
| Contract negotiation (price vs years vs loyalty, lowball refused with a counter, offered terms used, extension terms used and cleared, saved) | 5 |
| Interactive draft (user on the clock, scouted board and ranges, user pick, staff pick equals auto, save mid-draft, signings wait, unfinished draft, old saves) | 9 |
| Offseason window (pausing changes nothing, signing in the window gets a next-season contract, window survives saving) | 3 |
| Owner decides who stays (extend, leave, cleared after use, spectator mode unchanged, final-year only, state save) | 4 |
| Table alignment follows content; new games have a valuation and can borrow at once | 2 |
| Revenue sharing (zero-sum, small markets receive, big markets pay) | 1 |
| Arena projects (cost up front, time to build, effect, one at a time, needs cash, suites, save) | 3 |
| Loans, repayment, sponsorship plans (limit, borrow/repay, plans pay differently, save) | 3 |
| Draft lottery (no lottery, permutation, falling limit, odds favour bad teams, reproducible, rules save/validate, generator option) | 6 |
| Free-agent signing and releasing (market order, signing, full roster, mid-level once a season, buyout, save of the flag) | 5 |
| Records and Hall of Fame (scores, eligibility, weak careers, single-season ranking) | 4 |
| History tab builds | 1 |
| Scouts reduce draft noise | 1 |
| Human trades (refusals, accepted deal moves players and contracts, roster limits, no-trade, bad input) | 5 |
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

Last verified: see `docs/STABILITY_REPORT.md` for the dated count and run time (the unit suite takes about 7 minutes locally and 9-14 minutes in CI; the older table above lists only the first systems).

Tests that touch disk use `user://test_saves` and clean up in `after_each()`. Inspection tools: `./tools/inspect_data.ps1`, `./tools/inspect_saves.ps1`, `./tools/simulate_games.ps1 [games=1000] [seed=2026] [era=mid_2010s] [tune=key:value,...] [box] [mirror] [leaders]` (stress test: 16 league averages vs the era's realistic ranges, one full box score, home-court check, full-season individual leaders), `./tools/finances.ps1 [seasons=2] [seed=...]` (every team's revenue, expenses, profit, valuation), `./tools/play_seasons.ps1 [seasons=5]` (several seasons with offseasons and a league-health table), `./tools/play_season.ps1 [option=value ...]` (plays a whole season and prints standings, playoffs, champion, awards), `./tools/generate_league.ps1 [option=value ...]` (e.g. `areas=europe teams=16 conferences=2 divisions=2`). The runner was also verified to report failures (exit code 1).

## Known issues / limits
- Runtime script errors in a TOOL script (not the test runner) can leave Godot running forever; use `timeout` when running tools from a shell.
- The whole suite takes about 7 minutes locally, 9-14 in CI (simulation tests run thousands of games and several tests play whole seasons). Use `timeout` generously when running it from a shell.
- Runner discovers methods by name only. A test file with a syntax error is reported as a FAIL (an earlier version hung forever instead; fixed).
- GDScript gotcha: `var x := <untyped value>` is a parse error in this project (warnings are errors). Annotate the type: `var x: String = ...`.
- The stress tools are listed in the "Added 2026-11-17" section below and run on GitHub Actions (`.github/workflows/`).


## Mouse-click test (tools/click_test.ps1)
`tools/click_test.gd` hosts the app in its own 1280x800 viewport and sends real mouse press and release events at the positions of the controls (so it needs no window and also works with one). It clicks through: New Game, a drop-down, Create League, a table row to choose a team, Start Game, Next Week, every tab, Borrow/Repay, Use suggestion, Start project, a roster row and the profile popup, Release (and Release with nothing selected shows a hint), a free agent row and Sign, a trade list and Check the offer, To End of Regular Season, Play All Playoffs, Begin Offseason (with the warning), a draft row and a workout, Draft selected prospect, Finish Offseason; after each click it checks that the game state really changed. 67 clicks in the latest version (it also opens the owners meeting, votes, and the Finances pages), 0 problems; the first version, 54 clicks, was repeated 3 times in both headless and windowed modes. Limits: the entries inside a drop-down list are chosen directly after a real click on the drop-down (the list is a separate pop-up window); typing into text boxes is not simulated; layout and looks are still checked by screenshots (`tools/screenshot.ps1`).

## Added 2026-11-17
| Area | Test file |
|---|---|
| Long-run economy: seeded growth, the cap following profit and never falling, AI projects and dividends, the new arena, the owner's dividend, re-signings agreed before the minimum rose | `test_economy.gd` |
| Staff chemistry parts, hire preview, development effect, GM negotiation in contracts and trades | `test_staff_chemistry.gd` |
| Season tickets, promotion nights, saving of the plan | `test_ticket_plan.gd` |
| AI trade wariness, meeting rapport, neighbours losing fans, saving of relations | `test_ai_reactions.gd` |
| The owner's choice of city and team name when relocating | `test_relocation.gd` |
| The first-time tutorial, preferences, text size | `test_tutorial.gd` |
| Overtime rate | `test_simulation.gd` |

Long checks (not part of the unit suite): `./tools/economy_check.ps1 seasons=50 teams=12|30|64` (exit code 1 if profit, cash or payroll-to-cap runs away), `./tools/ui_playthrough.ps1`, `./tools/click_test.ps1`.

Further tools and tests added 2026-11-18 (stability sign-off):
| Area | File or tool |
|---|---|
| Debt restructuring, valuation floor, cooldown, loan freeze, reputation, a club that never recovers keeps its owner in control (D-029), AI clubs in debt | `test_distress.gd` |
| Hard-limit cuts leave room for the minimum players who refill the roster (regression) | `test_offseason.gd` |
| Careful / naive / reckless owners, fixed seeds, results with restructurings and operating profit | `./tools/owner_stress.ps1 [seasons=30] [teams=12] [seeds=101,102]` |
| Pricing modes of the owner playthrough (`pricing=inflation|suggested`) and the run line that records every setting | `./tools/ui_playthrough.ps1` |
| Strict mode for the simulation check (exit code 1 if any average is out of range) | `./tools/simulate_games.ps1 games=1000 strict=1` |
| Separate DEBT, CASH, PROFIT, VALUATION and TITLES lines and a leverage breach rule | `./tools/economy_check.ps1` |
| GitHub Actions: `ci.yml` (tests, strict sim check, short economy check on every push), `long-checks.yml` (weekly or by hand: 50-season economy at 12 and 30 teams, owner stress), `release.yml` (Windows build and packaged self-test on a version tag or by hand) | `.github/workflows/` |

Career Mode (2026-11-18): `test_career_foundation.gd` (archetypes valid and within budget, hybrid builds, every validation boundary, body-dependent ceilings, garbage input, player and profile creation with seeded ids, profile and state round trips, version 1 to 2 migration, Owner states unaffected) and the main-menu mode buttons in `test_tutorial.gd`. Run one file with a scratch runner or the whole suite with `./tools/run_tests.ps1`.
`test_career_creator.gd` (phase 2): career creation, seeds, invalid builds, save and resume, the creator form (errors, archetype templates, hybrids and points, body-limited potential) and the screens end to end.
`test_career_progression.gd` (phase 3, 16 tests, no randomness): XP and level curve inverse, level rewards, points granted once per level, deterministic replay (identical checksum), game XP floor and cap, milestones pay once, training limits and diminishing returns, attribute costs and the ceiling as a hard limit, badge data consistency (real composites and attributes, cap), unlock requirements and prerequisites, equip limit and capped bonus, save and load of progression, controller views, the hub tabs.
`test_career_season.gd` (phase 4, 13 tests): joining a team, seeded draft team, rewards from real box scores paid once, a recorded season and the next one starting, determinism of whole careers, save and resume mid-season without re-paying, badge bonuses touch only the career player's composites, normal games bit-for-bit unchanged, the hub's Season tab, and the three defects the 20-season playthrough found. Long check: `./tools/career_playthrough.ps1 [seasons=20] [teams=12] [seed=7] [archetype=...]` (17 seasons to retirement, 0 problems at seed 7).
`test_career_events.gd` (phase 5 slice, 8 tests): event data well formed with real choices, eligibility by level and no quick repeats, seeded picks, choices change XP/points/reputation/currency/tags and are logged, no negative balances and refused answers change nothing, a waiting decision blocks play, new seasons bring new decisions and save and load, and determinism.
`test_career_role.gd` (8 tests): a starter request starts a reserve every game and a bench request keeps a starter out, more minutes and shoot-first change the box score, neutral requests are bit-for-bit identical, the coach's refusals and their exceptions, controller application and clearing, saving. `test_career_contract.gd` (6 tests): offer scaling and agent/reputation ceilings, talks only when the contract ends, accept gives exactly the offered deal, counters (refused above the ceiling, reputation cost for hard bargaining), free agency without AI re-signing, talks survive saving and continue identically.
`test_career_relationships.gd` (5 tests): season scoring by rank, games, wins and tags, the 0-100 limits and the chemistry bonus, trust changing role limits and contract ceilings, scored once across saving, determinism.
