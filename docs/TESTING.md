# Testing

## Strategy
1. **Automated unit tests** for every system, run headlessly, fixed seeds.
2. **Simulation and economy stress tests** (built, see below): `simulate_games` (16 league averages, close games, overtime), `economy_check` (decades of AI-only leagues: profit, cash, debt, payroll, titles), `owner_stress` (careful, naive and reckless owners), `ui_playthrough` (50 seasons through the real screens) and `click_test`. They exit with code 1 on a breach, so CI and scripts can rely on the exit code.
3. **Manual playtesting** by the founder for feel, usability and fun. Claude provides step-by-step instructions with each UI feature.

## Current totals (the one authoritative place)
Every other document points here instead of repeating numbers. These come only from fresh runs, never from older documents. The last verified run was on 2026-11-24 (AI-assisted development ecosystem, final; `tools/validate_project.gd` 0 problems; also clean: simulate_games games=300 seed=2026 strict=1, dynasty_check, career_playthrough seasons=5 seed=7, Creator Studio smoke; earlier text below describes the prior run), after the 3D feasibility prototypes (B1b and B1c; base commit `d732f82` plus the changes in the commits that record this run; see `AUTONOMOUS_WORK_LOG.md`). The stabilization fixes before it are in `STABILIZATION_AUDIT.md`, with Godot 4.7.2 headless, one process at a time. Also run in that session: `simulate_games games=1000 seed=2026 strict=1` (exit 0, 0 of 16 checks outside the range), `career_playthrough seasons=20 seed=7` (0 problems), `dynasty_check` (exit 0). Not run: `economy_check`, `owner_stress`, `ui_playthrough`, `career_balance` (nothing in their code changed; they run in `long-checks.yml`).

| Kind | What it is | Last result | How to run |
|---|---|---|---|
| Unit | `tests/unit/test_*.gd`, headless, fixed seeds | **1,771 passed, 0 failed** (full run after Franchise Experience M2, D-077; adds `test_ui_franchise_kit`, 15 tests, and `test_franchise_data`, 15) | `./tools/run_tests.ps1` |
| Live | `tests/live/test_live_*.gd`, real scene tree, awaits frames | **241 passed, 0 failed** | `./tools/run_live_tests.ps1` |
| Creator Studio smoke | separate project, `creator_studio/tools/studio_smoke.gd` | **PASS** (run `--import --quit` on `creator_studio` first after adding new game class files, or the smoke test can hang on a stale cache) | `godot_console --headless --path creator_studio --script res://tools/studio_smoke.gd` |
| Simulation and stress | `simulate_games`, `economy_check`, `owner_stress`, `ui_playthrough`, `career_balance` and similar tools in `tools/` | **Not re-run in Phase 1** (nothing in the simulation changed). Results are in `STABILITY_REPORT.md` and `RELEASE_READINESS.md` as historical records with their own dates. | `tools/*.ps1` |
| Manual validation | founder playtests, Android device checklist, screenshot review | **Not automated.** Outstanding items are in `DEVICE_VALIDATION.md` and `RELEASE_READINESS.md` section 3 to 4. | by hand |

Notes on reading the numbers:
- Each number is a count of passing test methods, not files. They are not comparable with a raw count of `func test_` lines.
- Known noise that is not a failure: the unit runner reports 7 "engine errors" (an intentional bad-image test, an intentional damaged-bookmark-file test and two `!is_inside_tree()` messages from existing UI tests) and the live runner reports 2 ("Lambda capture ... was freed"); both runners print them as non-failures. The exit-time lines about leaked RIDs and ObjectDB instances come from the headless renderer. All of this was the same before Phase 1; the Lambda messages are tracked in `INTEGRATION_AUDIT.md` (finding 16).
- When these numbers change, update this table with the date and commit, and nothing else.

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
| Content publishing (manifest, canonical checksums, safe paths, validator, revision rules, publisher, approval, immutability, crash-safe pointer, draft workspace, loader, fallback chain with cycle detection, rollback, ownership by id, preferences, service, studio link) | 48 |
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
| Dynasty domain (profile round trip, ledger and no negative balances, idempotent requests, ownership and editions, duplicates and mastery, atomic commit, store recovery and migration chain, roster record) | 8 |
| Dynasty content (extended schema validation and rejection cases, editions, card views and badges, market/pack listings, unavailable owned cards, revision flags, starter grant, empty content) | 11 |
| Dynasty team building and simulation (13-slot validity, positions, one edition per player, swaps, rotation persistence, team overall, recommendations, roster to FcGameTeam mapping, starters honoured, determinism, opponents, games update records) | 12 |
| Dynasty packs and economy (deterministic rolls, guarantees, odds, pity, reveal order, purchase, idempotency, insufficient funds, failed save, reward packs, direct acquisition, duplicates, collection challenges) | 12 |
| Dynasty progression (challenge progress from results, restrictions, one-time claims, season points and milestones, new-season keeps collection, tournament bracket, save/load mid-run, reproducibility, whole-profile save/load) | 10 |
| Dynasty screens (onboarding, every tab builds, validation messages, pack reveal and skip, full loop, card detail, unavailable cards) | 6 |
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
| GitHub Actions: `ci.yml` (tests, strict sim check, short economy check on every push), `long-checks.yml` (weekly or by hand: 50-season economy at 12 and 30 teams, owner stress, and a `career` job: `career_playthrough` for 20 seasons and `career_balance` with 2 seeds), `release.yml` (Windows build and packaged self-test on a version tag or by hand) | `.github/workflows/` |

Career Mode (2026-11-18): `test_career_foundation.gd` (archetypes valid and within budget, hybrid builds, every validation boundary, body-dependent ceilings, garbage input, player and profile creation with seeded ids, profile and state round trips, version 1 to 2 migration, Owner states unaffected) and the main-menu mode buttons in `test_tutorial.gd`. Run one file with a scratch runner or the whole suite with `./tools/run_tests.ps1`.
`test_career_creator.gd` (phase 2): career creation, seeds, invalid builds, save and resume, the creator form (errors, archetype templates, hybrids and points, body-limited potential) and the screens end to end.
`test_career_progression.gd` (phase 3, 16 tests, no randomness): XP and level curve inverse, level rewards, points granted once per level, deterministic replay (identical checksum), game XP floor and cap, milestones pay once, training limits and diminishing returns, attribute costs and the ceiling as a hard limit, badge data consistency (real composites and attributes, cap), unlock requirements and prerequisites, equip limit and capped bonus, save and load of progression, controller views, the hub tabs.
`test_career_season.gd` (phase 4, 13 tests): joining a team, seeded draft team, rewards from real box scores paid once, a recorded season and the next one starting, determinism of whole careers, save and resume mid-season without re-paying, badge bonuses touch only the career player's composites, normal games bit-for-bit unchanged, the hub's Season tab, and the three defects the 20-season playthrough found. Long check: `./tools/career_playthrough.ps1 [seasons=20] [teams=12] [seed=7] [archetype=...]` (17 seasons to retirement, 0 problems at seed 7).
`test_career_events.gd` (phase 5 slice, 8 tests): event data well formed with real choices, eligibility by level and no quick repeats, seeded picks, choices change XP/points/reputation/currency/tags and are logged, no negative balances and refused answers change nothing, a waiting decision blocks play, new seasons bring new decisions and save and load, and determinism.
`test_career_role.gd` (8 tests): a starter request starts a reserve every game and a bench request keeps a starter out, more minutes and shoot-first change the box score, neutral requests are bit-for-bit identical, the coach's refusals and their exceptions, controller application and clearing, saving. `test_career_contract.gd` (6 tests): offer scaling and agent/reputation ceilings, talks only when the contract ends, accept gives exactly the offered deal, counters (refused above the ceiling, reputation cost for hard bargaining), free agency without AI re-signing, talks survive saving and continue identically.
`test_career_relationships.gd` (5 tests): season scoring by rank, games, wins and tags, the 0-100 limits and the chemistry bonus, trust changing role limits and contract ceilings, scored once across saving, determinism.
`test_career_rival.gd` (6 tests): game score, seeded peer rivals, duel scoring and rewards, the challenge picks a rival on another team, a real duel scored once from the league's box score, saving and a retired rival. `test_career_sponsor.gd` (7 tests): no offers for unknown players and scaling, one deal at a time paid once a season, the bold brand's cost, dropping a deal, cosmetic looks, an end-to-end season and saving.

- `tests/unit/test_career_overall.gd` (11 tests): growth equals the original algorithm, other players bit-identical, once-per-season grant, preview equals action, rounding cap, banked points, best next upgrade, milestone once and saved, offensive star vs defensive specialist, strategy ranking.

## Career click test (tools/career_click_test.ps1)
`tools/career_click_test.gd` drives the real Career screens with simulated mouse clicks: Career Mode, Create a player, Check my build, Create my player, Let the draft decide (the team must match the scouting report), the first decision, Play next week, +1 on a skill, Train, Finish the season, Save. 18 clicks, 0 problems (2026-11-19). Two tests in `test_career_overall.gd` cover the scouting report.

## Career validation tools and the full-run record (2026-11-19)
| What | Command |
|---|---|
| A whole 20-season career, checking every rule | `./tools/career_playthrough.ps1 seasons=20 seed=7` |
| One career per archetype and seed; exit 1 if an archetype's average peak is outside the band, focused careers peak more than 3 below potential, archetypes differ by more than the spread limit, or a run breaks a rule | `./tools/career_balance.ps1 [seeds=3] [teams=12] [seasons=20] [strategy=focused|even|template|low_weight]` |
| How spending strategies compare (a study, not a pass/fail check; run through Godot directly, no wrapper) | `godot_console --headless --path . --script res://tools/career_growth_study.gd` |
| Career Mode through simulated mouse clicks | `./tools/career_click_test.ps1` |
A balance threshold describes acceptable balance; it is never a reason to retune progression. Use at least 3 seeds for a first comparison and at least 5 before changing a threshold. Full, dated outputs of each validation run (command, commit, exit code, duration, seeds) are kept in `docs/validation/`. Total test count: 710 (from the 2026-11-19 full run; see `docs/validation/`).

## Portrait, cache and pack-opening tests (D-059)
Unit: `test_player_traits.gd` (6: deterministic, in range, integers, age changes only the age marks, `resolve` unchanged, the approved figure is the default), `test_player_variety.gd` (7: 400 seeded players: every feature group varied, no two alike, almost every pair differs in 5 or more of 9 groups, no look-alikes in a 15-man roster, ageing keeps the face, body data nudges proportions only), `test_player_visual_sources.gd` (8: Owner and Career are procedural; a trade or another mode never changes a face; a Career face is the same for 20 years; ageing changes the cache key; Dynasty art is used, a missing or invalid file falls back to the same procedural identity; editions share a face; optional inputs never touch identity). The 50-key identity golden is unchanged (47 identity tests). Live: `test_live_player_hd.gd` (2: 40 players x bust, head, full x four sizes draw without script errors), `test_live_portrait_bake.gd` (9: the 20 MB budget, a changed picture is a different key, near sizes share a step, hard-budget LRU eviction, flooding never exceeds 20 MB, an oversized picture is refused, drawing with and without a cache never errors), `test_live_pack_cinematic.gd` (12: five stages in order, record never changed, skip equals watching, skip mid-show leaves nothing running, reduced motion, bounded effects, audio gate, spec covers every rarity) and `test_live_pack_reveal_production.gd` (10: quick versus spotlight by rarity, presentation grows with rarity, legendary shows the player name as the banner with LEGENDARY under it, Done acknowledges exactly once, watching acknowledges nothing, Quick equals Cinematic in result, the preference is saved and falls back, reduced motion suppresses every effect for every rarity, the limits hold, the opening is never written to). Real baking, frame times, memory and variety need a window: `tools/portrait_perf.gd`, `tools/portrait_bench.gd`, `tools/portrait_variety.gd` (the headless renderer cannot read pixels).

`tests/unit/test_player_dossier.gd` (8): the Owner view-model carries personality and a contract that match the game data, building a dossier changes nothing, the Owner overview shows Ratings, Development, Personality and Contract panels, a Dynasty card shows no contract or personality or career arc, the Career dossier has the arc and level, the development track describes itself in words, the hero keeps its layout contract and shows both ratings.

`tests/unit/test_injury_history.gd` (7): history kept in order and bounded, saved through JSON and an older save loads empty (data version unchanged), a played season records its injuries, the Owner view-model and dossier show Health with the history newest first, an injured player shows the status chip and games out, a healthy player says so, a Dynasty card has no Health panel.

`tests/unit/test_player_relationships.gd` (6): the words for a relationship value, Owner tenure and best teammates (best first, never himself), a traded player starts a new run, the Owner and Career dossiers show the Relationships panel (Career: trust, chemistry, rival and tags), a Dynasty card has none. `tests/unit/test_player_similarity.gd` (5): identical players score 100 and the score falls with the gap, the nearest list is sorted, stable and bounded, an Owner player plays like five other active players and computing it changes nothing, a Dynasty card plays like other players' cards.

`tests/unit/test_achievements.gd` (10): the data file is well formed (unique ids, known metrics, three ascending tiers), tiers are reached at their thresholds, season averages need a real season, honours and club years feed their achievements, a comeback needs a serious injury and a real season after it, earned and next-up lists are sorted and stable, an Owner player's achievements match his statistics and the career totals, the dossier shows the panel and a tab with a bar for every achievement, building them changes nothing, a Dynasty card has none.

## UI tests, the live runner and the screenshot matrix (UI polish milestone, D-047)
The design system and component kit have their own tests, in three groups:
- **Unit tests** (`tests/unit/test_ui_design_system.gd`, `test_ui_kit.gd`, `test_ui_motion.gd`): contrast of every text colour on every surface (WCAG 4.5:1), the three mode skins and their whitelist, the theme's variations, fonts and text scale, icons and licences, rating tiers, the reduce-motion preference, and every kit component's states and signals.
- **Ratchets** (they may only improve): `test_ui_style_lint.gd` counts literal colours, font-size overrides and sized labels in `src/ui` outside the theme, tokens and kit, and fails if a count rises above `tests/support/ui_style_baseline.json`. `test_ui_layout.gd` measures the smallest window each screen needs (`tests/support/ui_layout_probe.gd`) and fails if it grows beyond `tests/support/ui_layout_baseline.json`. When a screen is migrated or made narrower, lower its numbers in the baseline file.
- **Live tests** (`tests/live/test_live_*.gd`, runner `tests/run_live_tests.gd`, `./tools/run_live_tests.ps1`): the unit runner works before the first frame, when nodes are not yet inside the scene tree, so tweens, timers, focus, `Range` signals and keyboard input cannot be tested there. The live runner starts after the first frame, lets a test `await` frames or seconds, and reports `Live tests: N passed, M failed` (exit code 1 on failure). Extend `FcLiveTestCase` (it gives each test a `host` Control in the real tree and resets the UI statics). The unit runner skips `tests/live`. CI runs both.
- **Screenshots** need a window (not headless): `./tools/screenshot.ps1 screen=gallery skin=broadcast size=1280x800 out=shot.png`, or the whole matrix with `./tools/screenshot_matrix.ps1 -Out docs/validation/ui/<name>`. `screen=` accepts Owner tabs, Career screens, `dynasty_*` screens (built from the test fixture content, so they do not depend on the machine) and `gallery`. Sizes use true pixels (`stretch=off`), so `size=412x915` shows what a phone-width layout really needs. The Component Gallery (Main menu, "Component gallery", editor and debug runs only) shows every token, component and state with switches for skin, touch layout, reduced motion and text size.
Shaders and animation looks cannot be checked headless: they are reviewed from screenshots and by eye.

### Phase 3 additions
`tests/unit/test_ui_shell.gd` (33 tests): layout profile rules and safe margins, the navigator, the notifier, the dialog stack, the frame (scroll area, safe margins, bottom bar, backdrops), the navigation bar on both targets, and how `FcApp` uses them (Back, skins, Settings, confirmed delete, Dynasty desktop and mobile navigation, touch-sized stock buttons). `tests/live/test_live_shell.gd` (9 tests): the Escape key, dialogs closing first, screen fade-in only on a new screen, reduced motion, toasts from messages, the loading overlay, the window changing to a phone and back while a screen is open, sideways scrolling in a small window, and the More menu. The layout baseline was tightened (main menu 820 to 393 px, Dynasty tabs 789 to 300 to 740 px). `tools/click_test.gd` caught a real regression (a toast covering a button) before it was committed; keep running it after any shell change.

### Test-runner reliability (D-052)
A test now FAILS if a runtime script error happens while it runs (setup, body, teardown, or the time spent awaiting in a live test), because Godot aborts the function that raised it and the remaining assertions would never run. This uses a `Logger` (`tests/support/script_error_logger.gd`), not console parsing. A test file that extends `FcTestCase` but defines no `test_` method also fails. Options: `--filter=text` and `--dir=res://folder`. `tests/unit/test_runner_detection.gd` proves the behaviour by running a second Godot process on the deliberately broken tests in `tests/runner_fixtures` (a folder both normal runners skip). Limits: `push_error` calls and engine messages are not failures; an infinite loop or an `await` that never resumes is left to the CI job timeout; the live runner returns exit code 2 if the run stops early. Details: docs/DYNASTY_HARDENING.md.


## Status at the end of the UI polish milestone (2026-11-20) (historical)
*Historical record, kept as written. For current numbers see "Current totals" above.*
Unit suite: 1,113 tests; live UI suite: 68 tests; both exit 0. See docs/RELEASE_READINESS.md for every other check and for what was not verified.

## Release validation additions (2026-11-21)
- **Screen matrix** (`tests/live/test_live_screen_matrix.gd`, helper `tests/support/ui_viewport_audit.gd`, ratchet `tests/support/screen_matrix_baseline.json`): real `SubViewport` of each window shape x 3 text sizes; checks controls outside the window, sideways overflow, touch size, dialogs, keyboard reach, theme focus styles and the ultrawide column. "Builds" (`test_release_readiness.gd`) is not "fits" (matrix) is not "feels right" (a person). Run: `./tools/run_live_tests.ps1 -Filter screen_matrix`.
- `tests/unit/test_dynasty_founding.gd` and `./tools/dynasty_initial_check.ps1`: the bundled Founding Series release from a fresh install.
- `tests/unit/test_release_fixes.gd`: regressions for what the matrix and the Owner audit found, plus the phone scale and safe-area conversions.
- Exports: `./tools/export_windows.ps1`, `./tools/inspect_export.ps1 <package>`, `./tools/export_android.ps1`, packaged self-test `FullCourt.exe --headless -- --selftest` (docs/PLATFORM_BUILDS.md).
- **Do not run two Godot test processes at once**: the Dynasty fixtures use shared `user://test_*` folders and a second process corrupts them (this produced false failures during this milestone).

## Visual Identity additions (2026-11-21, D-057)
- Unit: `test_brand_assets`, `test_ui_table` and `test_ui_table_extras` (sorting, selection, multi-select, from_strings, stacked bar, chart colours), `test_ui_states` (six interaction states, contrast of the focus ring and disabled text), `test_ui_team_identity` (determinism, emblem rules, readability for all 16 colour schemes, a different crest for every team of a generated league), `test_ui_menu`, `test_player_identity_golden` (**50 fixed keys keep their faces**: regenerate `tests/support/player_identity_golden.json` with `tools/build_identity_golden.gd` only after reviewing the portrait contact sheet), `test_ui_owner` (every old column and action is still there), `test_ui_career_hub`, `test_ui_bracket`, `test_ui_celebration` (sounds, confetti cap, reduced motion, Owner tab build budget 250 ms).
- Live: `test_live_table` (virtualisation, keyboard, timing for 400 and 1,000 rows), `test_live_menu` (the menu at 1920x1080, 1280x800, 800x600 and 412x915).
- Screenshots: `tools/screenshot.gd screen=menu_saves | credits | <Owner tab> | career_hub | gallery section=Teams|Portraits|"Portrait variety"|Table`; the checkpoint pictures are in `docs/validation/ui/visual_identity/`.
- Ratchets changed on purpose (each noted in D-058): style lint now exempts `src/ui/art`, `team` and `player` (drawn pictures), `app.gd` sized labels 80 to 68; layout baseline heights for `owner_roster`, `owner_schedule`, `new_league` grew (real minimum table heights, dropdowns).
- The real-click tools (`click_test.ps1`, `career_click_test.ps1`) click `FcTable` rows as well as Trees.

## Ecosystem integration additions (Phase 1, 2026-11-21)
- `tests/unit/test_ecosystem_integrity.gd` (11 tests): one position list (`FcPosition.PLAYABLE`), one rating calculation for Dynasty-built and Owner-generated players, attribute and badge keys across every data file, the bundled Founding Series validating with every reference resolving, dangling references rejected, and a roster card missing from the release reported and skipped safely. Pure checks, no scene.
- `tests/live/test_live_mode_transitions.gd` (1 test): the real app through menu, Owner, Career, Dynasty and back, with saves, loading and Continue, all in scratch folders. It is the only test that covers a full cycle between the modes. It was checked by breaking an assertion on purpose and watching it fail.
- Findings and their status: `docs/INTEGRATION_AUDIT.md`.

## Play-by-play recording (Phase 2A, 2026-11-21)
- `tests/unit/test_game_events.gd` (11 tests): the recorder never changes a game (identical box score and identical random-generator state with it on or off, 8 seeds); the events alone reproduce the score of every period and every counting stat of every player; injuries match the box; five players on court at all times and starters match the box; the clock never runs backwards inside a period; every event reads as a sentence with no unfilled placeholders and the same text every time; an overtime game is labelled and still adds up; the log survives JSON and ignores damaged rows.

## Game history (Phase 2B, 2026-11-21)
- `tests/unit/test_game_history.gd` (10 tests): a watched game keeps its play-by-play and the events add up to the stored final; unwatched games are not recorded; the log survives a JSON round trip as whole numbers and a full save and load; unfinished seasons are never archived and a finished archived season drops boxes and replays; one replay stays under 70,000 characters (measured: 6,500 to 12,200 for 363 to 659 events, about 173 KB for the 20 kept games); the version 2 to 3 migration adds empty logs and touches nothing else (and a version 1 save walks both steps); Career games and Dynasty results carry the play-by-play, and a Dynasty profile save never holds it.
- Existing tests that asserted the old data version now assert 3 (`test_career_foundation`, `test_injury_history`).

## Replay (Phase 2C, 2026-11-21)
- `tests/unit/test_replay_model.gd` (14 tests): shots are placed by kind (threes beyond the line, rim finishes at the basket, all on the court, repeatable but varied), the ends switch at halftime, formations have defenders goal-side, slots follow positions; the model's final state has every player's points and fouls equal to the box, points and scores only grow and add up at every event, possession and ends follow the events, five on court after the tip-off and team fouls reset each period, the three filters nest and stepping visits exactly the filtered events, pacing is positive and shots linger longer than substitutions, empty or missing logs are handled; the adapters give no replay without events (older saves) and open one for Owner, Career and Dynasty games.
- `tests/live/test_live_replay.gd` (11 tests): the screen opens on the tip-off and draws; play, pause, speed and play-to-the-end then start-over; stepping, filters, period buttons and the scrubber; clicking the feed; five players listed per side; reduced motion shows events at once; a phone-width layout fits; an empty replay explains itself; space and arrow keys; and the real path: an Owner post-game dialog offers "Watch replay" and opens this game's replay (and offers none when no events were kept).
- Looked at, not only tested: `./tools/screenshot.ps1 screen=owner_replay` renders it; pictures in `docs/validation/ui/replay/` (desktop 1280x800 and phone 412x915). The court is an illustration (see ARCHITECTURE).
- Kit fix found while building it: `FcChoiceGroup.select()` left the previously chosen button looking pressed.

## Game day (Phase 2D, 2026-11-21)
- `tests/unit/test_game_day.gd` (6 tests): the preview describes the next game (home and away, the user's side, date, record and rank equal the standings, five different starters each); **the five it projects are the five who start the game** (6 games checked against the stored box scores, preview made on the morning of the game); days-to-next-game plays exactly up to it and is 0 when none is left; an injured star is listed as out and not projected; a Career team gets a preview; the simulator exposes its starters.
- `tests/live/test_live_game_day.gd` (3 tests): from the Owner dashboard, Game day opens the preview without playing anything, Play this game plays that game and opens its summary with Watch replay, and the replay is that game; the same through the Career hub, whose recent games can be picked and replayed; the preview fits a phone width.
- Picture: `docs/validation/ui/replay/gameday_desktop_1280x800.png` (`./tools/screenshot.ps1 screen=owner_gameday`).

## Dynasty replays (Phase 2E, 2026-11-22)
- `tests/unit/test_dynasty_replays.gd` (7 tests): a played game keeps its replay and the events add up to the kept box; only the last `replay_limit` (5) are kept, newest last, while the game-history list is untouched; replays survive saving and loading as whole numbers and still open; five replays stay under 160,000 characters; a version 1 profile migrates to an empty list (the step adds it and changes nothing else, an existing list is not wiped); a commit that fails rolls the replay back; games with no events keep nothing. `test_dynasty_ui` now also clicks the recent-games picker through to the replay.
- Two older tests asserted the previous rule that a Dynasty profile never holds a box (`test_post_game`, `test_game_history`); they now assert the narrower rule: boxes and events appear only inside the capped replays list (D-061).

## Franchise and league history (Phase 3, 2026-11-22)
- `tests/support/history_fixture.gd`: finished seasons built by hand (standings, a bracket, champion, MVP) and career rows, so the history rules have exact answers.
- `tests/unit/test_franchise_history.gd` (9): the season log and summary of hand-built seasons (titles, finals, playoffs, best and worst year, droughts, playoff streak; results as words), one champion and one runner-up per season, unfinished and other-league seasons ignored, a real played league obeys the invariants, franchise leaders count only seasons with the team, retired numbers (the season after the last, minimum seasons, a strong enough career, still-playing players excluded, split careers honoured by the main team only, two legends never share a number), jersey numbers steady and in 1 to 99.
- `tests/unit/test_rivalries.gd` (8): score from meetings, deciding-game series, finals and a shared division (58 points for the hand-built rivalry), the year-by-year development (22, 42, 58: Budding, Heated, Bitter), a pair in different divisions and a pair that never met, headlines, strongest-first lists per team and for the league, level thresholds, byes and unfinished series are not meetings, a real league's meetings equal its finished series.
- `tests/unit/test_storylines.gd` (9): back-to-back and three-peat, a title after a long wait, worst to first and Cinderella, the champion that misses the playoffs, repeat MVPs and a record season, a retiring legend and the retired number, ordering, filters, repeatability and a year cut-off, an empty history, well-formed stories from a real league.
- `tests/live/test_live_history.gd` (5): the History tab has its five pages and builds in a sensible time, the club picker rebuilds the page for another team, the heavier pages (retired numbers, rivalries, storylines) fill only when opened and show a legend's number card, the storyline scope switch, the dashboard still builds every tab, and the Career hub's league storylines panel.
- Pictures: `docs/validation/ui/history/` (`./tools/screenshot.ps1 screen=owner_history section=Franchise`, or "Retired numbers", Rivalries, Storylines).
- Existing tests updated: `test_ui.test_history_tab_builds` (the tab is now a page set), and new code was brought under the style-lint baseline with tokens instead of raising it.
