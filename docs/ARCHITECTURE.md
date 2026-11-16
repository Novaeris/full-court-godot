# Architecture

Items marked **(planned)** do not exist yet; everything else is implemented and tested.

## Guiding idea
One shared basketball universe + simulation core. Game modes (Owner now; Career and Dynasty later, see D-029) are thin layers that decide *what the player is allowed to do and see*, not separate games. The UI is a replaceable skin over the core.

## Layers (dependencies point downward only)

```
UI (scenes, screens, widgets)                      (planned)
Game Modes (Owner; Career and Dynasty later: permissions, flows)    (planned)
League & Business Systems (schedule, standings,    (planned)
  draft, free agency, trades, finances, cap rules)
Basketball Simulation (src/sim)                    IMPLEMENTED (v1)
Data Model (src/data): players, teams, contracts,  IMPLEMENTED
  attributes, world container, repositories
Procedural generation (src/gen, data/generation)    IMPLEMENTED
Core (src/core): FcRng, FcIdGenerator, FcVersion   IMPLEMENTED
Save system (src/save) beside the data model        IMPLEMENTED
```

Save/load serializes the data model, never the UI. Procedural generation (planned) uses only `FcRng` and the data model.

## Data model rules
1. Every entity has a stable integer `id` from `FcIdGenerator` (never reused, 0 = none).
2. Entities reference each other **by ID only**, never by object. This prevents circular references and makes saving trivial.
3. Each class has `validate() -> Array[String]` (empty = valid), `to_dict()` and `static from_dict()`. `from_dict` tolerates missing fields (fills defaults) and never crashes on bad data; `validate()` reports it.
4. Top-level entities write a `"schema"` version. Old saves load with defaults for new fields; real migrations will be added by the save system when a field is removed or changes meaning.
5. Money is whole dollars (`int`). Seasons are the calendar year in which they start. Dates are `FcDate` (ISO text when saved). Physical measures are metric.
6. The data model contains no simulation, UI, or Godot scene code.
7. **No raw floats in saved data.** Godot's JSON keeps only ~14 significant digits, so an arbitrary float changes in its last bits after save + load, which would break exact reproducibility. Floats that must be saved go through `FcChecks.quantize()` (3 decimals) in a property setter (see `FcPlayerDevelopment`). Prefer integers (money in dollars, ratings 0-100). 64-bit values are saved as text.

## Data model map (`src/data/`)

```
common/      FcChecks (validation helpers), FcDate
attributes/  FcAttributeDef      one rating's definition (key, range, default...)
             FcAttributeCatalog  loaded list of definitions of one kind
             FcAttributeSet      one entity's values, validated against a catalog
             FcDefinitionSet     the 3 catalogs: attributes, personality, tendencies
player/      FcPlayer            composed of:
               FcPersonIdentity  names, birth date, birthplace, country
               FcPlayerPhysical  height, weight, wingspan, handedness
               FcPlayerDevelopment potential, peak age, development rate, volatility
               3 x FcAttributeSet  attributes, personality, tendencies
               FcPosition        position ids (primary + optional secondary)
team/        FcTeam              composed of:
               FcTeamIdentity    nickname, abbreviation, founded year
               FcTeamBranding    colors, logo key
               FcRoster          list of player ids (the changing part)
             FcCity              market: population, economy
             FcArena             capacity, year built, city
league/      FcLeague            name + conferences; team membership queries; add_team / remove_team; make_even()
             FcLeagueStructure   which team counts / layouts are valid at creation (4-64 teams, equal divisions of 3-8)
             FcLeagueRules       saved rules of one league (by league_id): season, playoffs, cap, roster limits
               FcSeasonRules     games per division / conference / other-conference opponent; suggest(); advice()
               FcPlayoffRules    qualification, bracket, team count, series lengths; round math; describe()
               FcCapRules        soft / hard / none; tax; hard limit; exceptions; check_signing, check_trade, validate_contract
               FcRuleCheck       allowed? + reason
src/league/  FcMatchupPlanner    who plays whom how often, with a fair home/away split (computed, not saved)
             FcMatchupPlan       result: pairs, games and home/away per team
               FcConference      name + divisions
               FcDivision        name + team ids
contract/    FcContract          player_id, team_id, status, signing date, composed of:
               FcContractYear    season, salary, guaranteed, option (type/status)
               FcContractBonus   kind, season, amount, guaranteed, counts vs cap
staff/       FcStaffMember       coach / GM / scout / medical / business exec, composed of:
               FcPersonIdentity  (shared with players; lives in common/)
               3 x FcAttributeSet  skills, personality, philosophy
             FcStaffRole         the six jobs (GM, head coach, assistant, scout, medical, business exec)
             FcStaffContract     staff_id, team_id, role, signing date, status, years (FcContractYear)
world/       FcRepository        persistence interface (abstract)
             FcMemoryRepository  in-memory implementation
             FcWorld             definitions + id generator + repositories +
                                 cross-entity validation + snapshot to/from dict
```

Attribute definitions live in `data/definitions/*.json`: 28 basketball attributes, 7 personality traits, 8 tendencies (players); 17 staff skills in 5 categories and 7 philosophy dials (staff). `FcDefinitionSet.all()` lists every catalog. Add, rename or rebalance by editing JSON; `FcAttributeSet` fills any attribute added later with its default when old data loads.

## Relationships
- Player ↔ Team: via `FcRoster` (the team's roster is the single source of truth for membership). A player does not store his team.
- Player ↔ Contract ↔ Team: a contract holds `player_id` and `team_id`. A player may have many contracts over time but at most one `ACTIVE`; every rostered player must have an ACTIVE contract with that team (checked by `FcWorld.validate()`).
- Staff ↔ Team: via `FcStaffContract` (staff_id, team_id, role). A team's staff = its ACTIVE staff contracts (no separate staff list, single source of truth). Rules checked by `FcWorld.validate()`: one active job per person, at most one active General Manager and one Head Coach per team, retired staff cannot hold an active job. Scouts, assistants, medical and business roles are not limited.
- Staff contracts are separate from player `FcContract`: staff pay comes from the operating budget (Owner Mode), not the salary cap, and has no guarantees/bonuses/cap hits. Query helpers on `FcWorld`: `staff_contracts_of_team`, `staff_in_role`, `active_staff_contract_of`.
- Save compatibility: the `staff` / `staff_contracts` snapshot sections are additive; snapshots without them load as empty, so `DATA_VERSION` stays 1.
- Team ↔ League: a team belongs to a league by being in one of its divisions (`FcLeague` is the single source of truth). `FcWorld.validate()` requires every team to be in exactly one league whenever any league exists. League structure only; league rules (season length, playoffs, cap) will be separate data keyed by league_id.
- Team → City / Arena: by id. Arena → City: by id. Relocation = change `city_id`; the team id is unchanged.
- Not on the player/team by design (separate records keyed by id, to be built with their systems): career and season statistics, historical records and awards (keyed by `player_id` / `team_id` + season), team finances, staff, owner (`owner_id` reserved, unchecked until that entity exists).

Permanent vs changing team information: id + founded year are permanent; identity/branding/city/arena/owner change rarely (rebrand, relocation); roster changes constantly; per-season data (records, finances) will be season-keyed records.

## League rules (`FcLeagueRules`, `data/rules/cap_presets.json`)
- Rules are saved data keyed by `league_id` (`FcWorld.rules`), separate from structure, so leagues can differ. `FcWorld.validate(season)` checks every active contract against the cap rules (min/max salary, length, raises), roster size against the roster limit, and (when a season is given) every team payroll against the hard limit.
- Schedule rules: games per opponent by distance. `FcMatchupPlanner` turns structure + rules into pair counts and gives each odd-length series a host by walking closed trails through the graph of odd pairs (Euler-style orientation), so every team's home and away games differ by at most 1. This is the proof that rules like 3/2/1 work; it is not a calendar. Building dated schedules is a later system (back-to-backs, travel, rest days).
- Season rules are validated against the league: 10-120 games per team; recommended games-per-opponent ranges 2-3 / 1-2 / 1-2, allowed 1-5 / 1-3 / 1-3 (a one-conference league has 0 other-conference games). `FcSeasonRules.suggest(league, target = 80)` scores each combination: distance from the target, +10 for an odd season length, +1 per tier outside the recommended range (a tie-breaker only). So seasons end on an even number, and leagues too small for 80 get the longest even season possible.
- Playoffs: `qualification` (division_leaders | seeding), `bracket` (conference | league), `team_count`, `series_lengths` (1/3/5/7 per round). Round count = ceil(log2(bracket size)) (+ rounds among conference champions for conference brackets). Validated: even split across conferences, enough spots for every division leader, series count equals round count.
- Extra salary rules in `FcCapRules` (each switched off by 0/false; presets differ): tax sharing (`distribute_luxury_tax`), repeater tax (`luxury_tax(payroll, tax_seasons_in_last_four)`), restriction line (blocks the mid-level exception and tightens trade matching), rookie scale (`rookie_salary(pick, total)`, geometric curve from first pick to last), cornerstone extension (`check_cornerstone_extension`; contracts flagged `is_cornerstone` may exceed the normal max), cap holds (`cap_hold_amount`), sign-and-trade limits (`check_sign_and_trade`), no-trade clauses (`FcContract.no_trade`, `trade_requires_consent`). Saves made before these rules existed load with them all OFF so an old league plays exactly as before.
- Salary: `FcCapRules` is pure rule logic. Tiers: minimum payroll < soft cap < luxury tax line < hard limit. The free-agency and trade systems (not built) will call `check_signing` / `check_trade`; they return an allowed flag plus a reason to show the player. Presets: `soft_cap_with_hard_limit` (default), `hard_cap`, `no_cap`.
- Creation limits (`FcLeagueStructure`): 4-64 teams at creation; saves may grow to 100 (expansion adds teams and must rebalance divisions; uneven structures are legal inside a save, creation requires equal divisions).

## Procedural generation (`src/gen/`, content in `data/generation/*.json`)
```
FcGenerationData     loads names.json, world.json, position_profiles.json, staff_profiles.json, config.json; validate()
FcGenerationConfig   everything a user can customize: league name, size, areas or exact cities, conferences/divisions,
                     roster/staff sizes, nationality mix, salary range; validate() gives readable messages
FcNameGenerator      weighted name pools per country; nationality choice; unique names across a league
FcPlayerGenerator    FcPlayerSpec (age, position, level, country) -> FcPlayer
FcStaffGenerator     role + level -> FcStaffMember (role-specialized skills, reputation-based pay)
FcWorldGenerator     seed -> complete FcWorld; new_game_state(seed, mode, team index) -> FcGameState
```
- Reproducible: same seed + config = identical world. Each stage (cities, every team, free agents) uses its own forked `FcRng` stream, so changing one stage does not reshuffle the rest.
- Player realism: attribute = overall level + position offset + a shared latent per category (skill / athleticism / IQ) + individual noise; height and weight follow the position profile; tendencies blend skill with position habits; potential grows with years left before the player's peak age. Young players have lower current level, old players decline (`age_adjusted_level`).
- Places: 154 real cities in 83 countries and 7 areas (`data/generation/world.json`); teams are original franchises (100 generated nicknames, 16 color schemes, generated arenas). Cities are chosen by area + size/weighted-random, or from an exact list. Conferences/divisions are built geographically (west-east, then south-north) and are always equal in size at creation (`FcLeagueStructure`).
- Contents per team: 15 players with mid-life contracts, a GM, head coach, 3 assistants, 3 scouts, medical and business staff with contracts; plus a free-agent pool. Players come from the team's own country 65% of the time, otherwise by country talent weight; staff 80% local. Payrolls are scaled to fit the league's salary rules (around the cap, never above the hard limit).
- NOT generated yet (belongs to later systems): conferences/divisions/schedule, draft prospects, historical careers and league history, owners.
- All numbers (level ranges, salary curve, profile offsets) are first drafts to be tuned against the simulation.

## Save system (`src/save/`, root object `src/data/world/game_state.gd`)
- `FcGameState`: the root of a playthrough: world, random generator position, mode (owner/spectator; the planned Career and Dynasty modes are not in the code yet), user team, current season/date. This is what a slot contains.
- `FcSaveManager`: save / load_slot / list_slots / delete_slot / autosave. Slots are named `[a-z0-9_]{1,32}`; `autosave` is reserved.
- File (`<slot>.sav` in `user://saves/`): line 1 = header JSON (`FcSaveMetadata`: label, team, season, mode, versions, timestamp, SHA-256 + byte count of payload); rest = payload JSON. Listing slots reads only line 1.
- Safe writing: write `.tmp` → read back and verify checksum → rotate old save to `.bak` → rename `.tmp` into place. A verified complete copy exists at every step.
- Recovery on load: main file → verified `.tmp` → `.bak`. `FcSaveResult.recovered_from` says which was used so the UI can tell the player. Damaged files with no usable copy return `CORRUPT` with a plain-language message; nothing crashes.
- Versioning: `FcVersion.DATA_VERSION` (currently 1) is stored in every header. Saves from a newer game are refused (`UNSUPPORTED_VERSION`). Older saves go through `FcSaveMigrator` steps (N→N+1, registered per version; none yet). Rule: when a saved shape changes, bump DATA_VERSION and add a step; never edit released steps.
- Policy: saving never refuses because of world integrity problems (progress matters most); problems are returned as `warnings` on save and load.
- 64-bit values (e.g. RNG state) are stored as text, because JSON numbers are doubles and would lose precision.
- Not built yet: compression/binary format, cloud sync, save-slot screenshots, multiple autosave rotation, automatic autosave triggers (those belong to the game loop).

## Persistence abstraction
Game systems use `FcRepository` (get, has, add, update, remove, ids, all, count) and never a specific storage engine. `FcMemoryRepository` is the only implementation today. SQLite or another store can later be added as another `FcRepository` implementation. The save system (planned) will wrap `FcWorld.to_dict()` with slots, metadata, versioning, atomic writes and migrations.
Known limit: `team_of_player()` and `active_contract_of()` scan linearly; indexes will be added when profiling justifies them.

## Season engine (`src/league/`, `src/data/season/`)
```
FcDate.add_days / to_day_number     calendar arithmetic
FcScheduleBuilder                   matchup plan -> dated calendar (<=1 game a day, even pacing, few back-to-backs, travel streaks limited, ~2 days per game)
FcSeason                            saved: calendar + results + player stats + playoffs + awards + champion; status PENDING/REGULAR/PLAYOFFS/COMPLETE
FcScheduledGame                     day, home, away, score, overtimes, series (compact; box scores are NOT stored)
FcSeasonStats                       accumulated player totals (regular season and playoffs separately), leaders, per-game averages
FcStandings                         records, home/away, division/conference, streaks, last 10, ranking with tiebreakers
FcPlayoffBuilder                    bracket from standings + FcPlayoffRules (division leaders or pure seeding; conference or league bracket; byes; finals stage)
FcPlayoffs / FcPlayoffSeries        qualifiers, series (best of 1/3/5/7, 2-2-1-1-1 home court), winners propagate
FcSeasonEngine                      start_season, play_day(s), play_regular_season, start_playoffs, play_playoff_day, play_full_season, finish_season, awards
```
- Tiebreakers: win%, head-to-head among the tied, division record (if all in one division), conference record, point differential, team id.
- Awards (v1): MVP (value score x team success), scoring/rebounding/assists/steals/blocks leaders, All-League first/second/third teams (15 best by value, positions ignored), Finals MVP. Rookie of the Year and defensive awards wait for the draft and a defensive metric.
- A whole 30-team, 80-game season plus playoffs takes about 13 seconds; a 1,230-game season is stored in about 100 KB.
- Rosters are read when an engine is created; change rosters between seasons.

## 50-season health (decided target, D-029)
- A first 50-season, 20-team run (seed 31, 2026-11-16, before the fixes) found: (1) **integrity problems from the 12th season on**: contracts have built-in 4% raises, so a team that signed up to the hard limit ($189M) could be over it a year later; fixed by `FcOffseason.enforce_hard_limit` (the league makes a team release its worst value-for-money players, the roster may dip two below the minimum, the owner's team gets a news item); (2) **seasons got slower** (8 s early, 26 s by season 45): expired contracts were kept forever and every contract lookup scans them all; fixed by `FcWorld.prune_old_contracts` (contracts ended more than two seasons ago are forgotten; careers and history live elsewhere): a season now takes a constant ~12 s for 20 teams (about 16 s for 30), so 50 seasons take about 10 minutes headless; (3) titles spread over 16 different teams with a few multi-title runs (6, 6, 5, 5, 5); (4) the league's top-8 talent rises from 61 to about 66 in the first 12 seasons and then stays flat, and the average payroll settles around $145-150M against a $140M cap; both look like equilibrium effects, to be reviewed in M2 (cap growth over decades is a design question).
- **Second 50-season run after the fixes (same seed): 0 integrity problems in all 50 offseasons, 746 s instead of 1,294 s, 16 different champions (6, 5, 5, 5, 4, 4 titles at most), 175 Hall of Fame members, talent and payroll plateaus as described above.** This is the baseline for M2.
- **Title distribution (checked 2026-11-16 on the three 50-season runs against a random baseline):** titles are spread as evenly as pure chance would spread them (most titles 6-7 per team in 50 seasons, the top three teams win 16-21, all the same as random), but champions repeat far more than chance: a team that won in the last two seasons wins again in about 22-24 of 50 seasons against about 5 for random (20 teams) and 18 against 8 (12 teams), with runs of 3-5 straight titles. That is the dynasty effect real leagues show (about half of NBA seasons in 2010-2020 were won by a team that had won in the previous two), so it looks right. No change made; the check can be repeated after sim changes.
- **Save size after 50 seasons (12 teams, seed 9): 5.2 MB, 0.8 s to write, 1.0 s to read** (3,040 players in the database, 2,283 of them retired). Fine on desktop; to be re-measured on a phone in M5. A 30-team league will be larger (roughly 2x players).
- `tools/play_seasons.ps1` now prints the integrity messages instead of just a count and, at the end, the size and write/read time of a save of the finished world.

## Trade offers from AI teams (Owner Mode)
- `FcTradeOffers` (src/league/trade_offers.gd): every two weeks of the regular season and in the free-agency window up to 3 AI teams offer one of their players for one of the owner's top six. Each AI team picks the swap that is only just good enough for itself (at least the usual 10% margin, no more than 1.7x lopsided), so the owner gets the most it will give; every offer passes `FcTradeDesk.propose` (cap, rosters, no-trade) and is checked again on accepting. Derived from the year and a time bucket, so the same list every time and nothing is saved; declined offers are hidden until the next batch (`decline_trade_offer`, not saved). The Trades tab lists them with Accept and Decline. Note: because rebuilding teams undervalue veterans, offers often give the owner an older, better player for a younger one, which is a consequence of the valuation model.

## The owner's career: reputation and changing jobs (Owner Mode)
- Decided by the founder (D-029): the owner cannot lose, but can transfer to another franchise "like a job". `FcGameState.owner_career` (saved; older saves start fresh at reputation 40): reputation 0-100 and one history row per season ([year, team, approval, wins, title]). When a season ends the owner's reputation moves toward that season's approval (70% old, 30% new, +5 for a title) (`_record_owner_season`, once per season).
- `job_offers()` (only when the season is complete and before the offseason begins): up to 3 franchises, the same every time you look; the better the reputation the more valuable the franchises on offer (a team is eligible if its value percentile is at most reputation/100 + 0.25, so a weaker team is always among them). `transfer_to(team)` once per season: the old team goes back to the AI, pending agreements are dropped, the season just finished is recorded for the old team, your delegation and direction settings stay. The Overview shows the reputation, your seasons per team and the offers with a "Take the job" button.
- Not built: applying for specific teams, contract/term negotiation with the new franchise, the old franchise reacting.

## Sponsorship contracts (Owner Mode)
- Sponsors are invented company names (`data/generation/sponsors.json`, to be checked for resemblance to real companies before a commercial release). Each season the owner is offered 3 deals (`FcFinanceEngine.sponsor_offers`, derived from the team and the year, so the same list every time and nothing to save): 1-5 years, either fixed (95-110% of a slot's open-market value) or a bonus deal (80-90% plus 10% of a slot per playoff round won); longer deals pay slightly more. There are 2 slots, each covering 40% of the sponsorship income with the fixed payment; the rest still floats with brand, market, success and the style choice, so a long deal is a bet on how your brand develops. Signed deals are saved on `FcTeamBusiness.sponsor_deals`, decrease each season and end with a news item. AI teams keep the open-market formula, so league averages are unchanged (8.0% margin on 30 teams). Finances tab: the Sponsors row. Controller: `sponsor_offers`, `accept_sponsor`.

## Staff negotiation (Owner Mode)
- Hiring takes terms: `hire_staff(id, role, years, salary)`; staff accept up to 6% below their asking salary, more security (years above 3) lowers the price 2.5% per year and fewer years raise it (`staff_minimum_acceptable`); a refusal says the least he would take. The Staff tab has salary and years fields (defaulting to the asking salary) and the hire list now includes medical staff and business executives.
- Staff contracts ending this season (`expiring_staff`) are kept only if the owner agrees terms with `extend_staff` (3% extra discount for re-signing); agreements are saved in `FcGameState.agreed_staff_terms` and used by `FcOffseason.staff_rollover`; unagreed staff of a human-run team leave and the vacancy is filled, as with players (the start-offseason warning now lists staff too). With "Re-sign my players" delegated, the GM keeps staff with reputation 40+.
- New leagues start with 3 unemployed staff per role (`free_staff_per_role`) so there is someone to hire from day one; before this the hiring pool was empty until contracts ended.
- UI: the delegation tick boxes are now toggle buttons labelled [x] / [ ] because the theme drew no visible box.

## Playthrough tool and what it found
- `tools/ui_playthrough.ps1` (`ui_playthrough.gd`) plays Owner Mode through the real UI code for several seasons (`seasons=`, `teams=`, `seed=`, `reprice=1`): every tab builds, loans, arena projects, trade checks, extensions, the interactive draft (workouts and a pick), the free-agency window, GM delegation (alternating by season) and save/load in the middle of the draft and the window, validating the state after each step and printing results per season (record, profit and rank, payroll, approval, GM grade). Exit code 1 if anything fails.
- Runs on 30 teams (3 and 5 seasons) and 12 teams (4 seasons) found no crashes or invalid states. It did find: (1) the owner's ticket price never changed while the AI reprices every year, so a smaller-market owner fell to 28th of 30 in profit; fixed with a suggested price (`suggested_ticket_price`, "Use suggestion" button, what the AI charges); (2) the GM grade used absolute wins so short seasons graded too kindly; it now uses the share of games.
- A first-season loss for a small-market owner with an above-average payroll is normal in this model (it reached profit rank 14 of 30 by season 3 and 62 wins).

## League finance comparison (Owner Mode)
- `FcGameController.league_finances()` lists every team's last settled books (wins, revenue, profit, payroll, ticket price, attendance, valuation, profit and revenue rank), best profit first; the Finances tab shows it beside the owner's own seasons so decisions can be judged against the league.

## Playoff ticket prices (Owner Mode)
- `FcTeamBusiness.playoff_premium_pct` (100-300, default 160 = what the league's teams charge): playoff tickets cost this share more than regular ones, with playoff demand boosted (`playoff_demand_boost` 1.842 = 1.6^1.3) so that 160% sells as many tickets as a regular game. A higher premium earns more per fan but sells fewer seats once the arena stops selling out, so revenue per game has a sweet spot (`FcFinanceEngine.playoff_attendance`). Defaults reproduce the earlier league economics (8.0% margin on 30 teams). Finances tab, "Apply shop settings".

## Concessions and merchandise (Owner Mode)
- `FcTeamBusiness.concession_price_pct` (70-150, default 100): spending per fan is price x (1 - 0.6 x (level - 1)), so it peaks around 133% of the normal price, but each +10% costs about 0.8 points of fan interest, so the best price depends on how much the team needs its crowd. `merch_tier`: limited (x0.85 sales, 2% stock cost), standard (x1.0, 12%) and premium (sales x(0.9 + 0.5 x brand), 25% stock cost), so premium only pays for a strong brand; the stock cost is its own expense line (`merchandise_stock`). Defaults reproduce the earlier league economics (standard is the AI teams' range; the merchandise base was raised to offset the new 12% stock cost). Finances tab: "Apply shop settings".

## Business executives (Owner Mode)
- The business executive's skills now matter (`FcFinanceEngine.executive_skill`, constants in finance.json): marketing scales sponsorship income (+/-20% around the typical executive, skill 62) and the brand effect of the marketing budget (+/-40%); financial acumen scales travel and administration costs (-/+20%); community relations moves fan interest (+/-10 points of its target). A team with no executive counts as skill 35, so hiring one pays off. The typical executive is neutral, so the league's average margin stays about 8%. Shown on the Finances tab.

## Sponsorship style and loans (Owner Mode)
- `FcTeamBusiness.sponsor_plan`: 0 balanced (default, all AI teams), 1 steady (95% of base, ignores results), 2 performance (65% base plus weight on win percentage and playoff rounds, so it pays more only for winners). Constants in `data/simulation/finance.json`. `FcGameController.set_sponsor_plan`.
- `borrow(amount)` adds cash and debt up to `loan_limit()` (40% of franchise value); `repay_debt(amount)` pays from cash. Debt already costs 6% interest a season in the finance engine. Both are on the Finances tab. Not built: named sponsor contracts with multiple years, negotiated loan terms.

## Contract decisions at season end (Owner Mode)
- In Owner Mode the offseason no longer re-signs the owner's expiring players automatically. `FcGameController.expiring_players()` lists them (with asking salary and years); `extend_contract(player_id)` records an agreement in `FcGameState.agreed_extensions` (saved; missing in old saves = nobody) after checking the own-player cap rule. When the next season starts, `FcOffseason` (given `human_team_ids` and `agreed_re_signs`) re-signs the agreed players on a new contract at their asking price and everyone else becomes a free agent. Dynasty Mode is unchanged (automatic). The UI warns once, listing the players who will leave, before starting the next season; the Roster tab has "Extend contract of selected player".
- Not built yet: choosing among the free agents and the draft before the AI teams act (the offseason still runs in one step after the re-signing decisions).

## Delegation to the general manager (Owner Mode)
- The owner can let the GM handle three areas (`FcGameState.delegation`, saved; Staff tab check boxes; `set_delegation`): re-signing (`_gm_re_sign_players`: he keeps players he rates at 50+ value points, at their asking price, if the cap allows), the draft (the staff picks as an AI team would, using the team's scouts) and free agency (`_gm_sign_free_agents`: up to 3 signings of players he rates 52+). His judgement of a player is the market value plus a fixed per-player error whose size comes from the GM's and scouts' talent evaluation (`FcOffseason.draft_noise`), so a better GM decides better. What he did is listed in the message after the offseason starts (`gm_log`).
- When free agency is NOT delegated, AI free agency skips the owner's team (`FcOffseason.manual_free_agency_team_ids`); the league's emergency fill still keeps the roster at the legal minimum. Before this change the AI signed players for the owner's team after the window.
- Direction (`FcGameState.direction`, saved; Staff tab): philosophy (win now / balanced / rebuild) and budget (frugal 92% / normal 100% / aggressive 115% of the cap, never above the tax line). The philosophy tilts how the GM values players (rebuild: potential and youth, win now: today's ability), which free agents he signs (a rebuilding team skips players over 29), who the staff picks for the owner in the draft (`emphasis` in `ai_draft_choice`), and whether he trades: with "Make trades" ticked a rebuilding GM sells veterans to the top third for youth and picks, a win-now GM buys veterans from the bottom third (up to 2 trades, via `FcTrades.attempt`); balanced makes none. The budget caps re-signing and free-agent signings (`gm_payroll_limit`). `gm_report()` grades last season (wins against the expected wins) and is shown on the Staff tab.
- Staff changes on the owner's team (retirement, renewal, a contract ending, a replacement being hired) are reported as news. In-season: with "Replace injured players" ticked (`injuries` delegation) the GM checks once a day (`_gm_cover_injuries`, at most one move a week): if fewer than 11 players are healthy, or a top-eight player is out 10+ games while 13 or fewer are healthy, he signs the best free agent he can afford within the budget (preferring the injured player's position), releasing the weakest healthy non-rotation player first when the roster is full; the news reports each move.

## Draft pick trading (Owner Mode)
- Pick ownership is `FcWorld.pick_owners` ("year:round:original team" -> owner; unlisted = original owner; saved, missing in old saves = none). The year is the year of the season that starts after the draft. Draft rows are now `[round, pick, team (who made it), player, original team]`. The draft asks `pick_owner` who is on the clock, and forgets ownership of a draft once it is held (`prune_picks`).
- The Trades tab and `FcGameController.propose_trade(..., give_picks, get_picks)` trade picks as `[year, round, original team id]`; three drafts ahead are tradable (`first_tradable_pick_year`, `tradable_picks`). The AI values a pick by its original team's expected strength (average rating of its best eight; far-away picks are pulled toward the middle and discounted), first-round picks of weak teams are worth about as much as a good young player, and contenders value picks less than rebuilding teams (`FcTradeDesk._picks_value`). AI-to-AI trades also use picks (below).

- AI-to-AI trades (`FcTrades`, after the draft): a rebuilding team sells its best veteran (27+) to a contender for a young player, picks only, or a young player plus a pick. For each option each side computes its gain in player-value points (picks are worth a few points: `pick_points`, first-round picks of weak teams most; rebuilders value them 15% more and contenders 15% less); both gains must exceed a margin, and the most even split wins, with a reluctance penalty for adding picks so they appear when they help. Pick-only deals change roster sizes by one and respect the league's roster limits. In a 20-team league most offseason trades involve a pick.
- Bug found and fixed on the way: trades must remove outgoing players from both rosters before adding incoming players, because a full roster silently refuses an add. This affected the human trade desk too (default rosters start full), so a trade could leave a player on no roster with an active contract; regression test added.

## Contract negotiation (Owner Mode)
- `FcPlayerMarket.minimum_acceptable / evaluate_offer`: a player accepts a little under his asking price (6%), more when re-signing with his own team (about 3-8% extra by loyalty), and trades price for security (2.5% per year above the length he wants, more per year below). `sign_free_agent(id, salary, years)` and `extend_contract(id, salary, years)` take offers (no terms = asking price and desired length) and a refusal returns `required`, the least he would take. Agreed extension terms are saved in `FcGameState.agreed_terms` and used by the offseason's re-signing. The Market and Roster tabs have salary and years fields.

## The interactive draft (Owner Mode)
- The draft is a state machine in `FcOffseason`: `prepare_draft` (order incl. lottery, the prospect class), `make_pick` (one pick: roster spot, rookie contract), `finish_draft` (undrafted become free agents, results stored on the season). The automatic draft (`run_draft`, used by AI-only offseasons and Dynasty Mode) is the same machine run to the end with `ai_draft_choice`, so there is one set of rules.
- Owner Mode: `FcGameController.begin_offseason()` runs aging/retirement/contracts/re-signing, prepares the draft, and lets the AI teams pick until it is the owner's turn (`PHASE_DRAFT`, `offseason_stage` 2; the draft in progress is `FcGameState.draft_state`, saved, so you can quit mid-draft). `draft_board()` is the class as the owner's scouts see it (`scouting_report`: estimates with ranges that hold the truth about 80% of the time; the width depends on the GM's talent evaluation and the scouts' accuracy, never narrower than +/-3 overall and wider for potential); `user_draft_pick(id)`, `draft_staff_pick()` (the choice the AI would make for the user), `draft_auto_rest()`. After the last pick the AI trades run and the free-agency window opens (stage 1). Leaving the draft unfinished and starting the season lets the staff finish it. Signings and trades are refused during the draft.
- Per-pick randomness comes from `rng.fork("pick<n>")` (a function of the seed and the pick number only), so the draft is reproducible after saving mid-way or when the staff picks for the user (both tested).
- Workouts: the owner can invite 5 prospects (`invite_to_workout`); a workout gives a much sharper, independent report (error x0.4, never under 1) plus a note on the prospect's most extreme personality trait. Saved in `draft_state["workouts"]`.
- Not built: prospects' hidden traits beyond ratings.

## The owner's offseason window
- `FcOffseason.run()` is now `run_first_half()` (aging and retirement, expiring contracts, re-signing, the draft, AI trades) plus `run_second_half()` (AI free agency, legal rosters, staff). They use the same random streams, so running both back to back gives exactly the same result as before (tested).
- In Owner Mode `FcGameController.begin_offseason()` runs the first half and sets `FcGameState.offseason_stage = 1` (saved; missing in older saves = 0). The phase is then `PHASE_OFFSEASON`: `current_season` is still the finished season, `contract_year()` is the next one, and the owner can sign free agents (including the players who were not re-signed and the undrafted), release players and trade before the AI teams sign anyone. `start_next_season()` runs the second half and starts the new season; called with stage 0 it does both halves in one go (Dynasty Mode, tools and tests).
- UI: after the season the button reads "Begin Offseason"; then "Finish Offseason and Start Next Season". Not built: negotiating contract length or price, a scouted draft board before the draft, and picking in the draft yourself.

## Looking at the screens
- `tools/screenshot.gd` renders the real UI in a window and saves a PNG so the screens can be inspected (not headless; it opens a window for a moment):
  `godot_console --path . --script res://tools/screenshot.gd -- screen=Roster out=C:/temp/roster.png days=20`
  (`screen` is a tab name, `menu` or `new_league`). The first pass found: new games started with a $0 valuation (so no loans in season 1, fixed), text columns right-aligned (fixed: alignment now follows the content), an empty Overview (now shows the latest news) and a new-league form missing season length and draft lottery (added).

## Revenue sharing
- Every season end, teams in big markets pay and teams in small markets receive a transfer of `revenue_sharing_amount` ($120M at a $140M cap) times (league average market factor minus the team's) / average. It sums to zero over the league, so league-wide profit is unchanged. Found with `tools/owner_playthrough.ps1`: before this, the owner of the smallest market lost $55-75M a year and fell into a debt spiral; now about $15-20M a year (still the hardest team to own, which is a valid challenge but survivable).

## Arena projects (Owner Mode)
- Definitions in `data/simulation/arena_projects.json` (cost scaled by the cap, seasons to build, effect): expand seating (+1,500 seats, up to 26,000; more upkeep because arena operations scale with capacity) and luxury suites (+25% arena event income per level, 3 levels). Running projects are saved on `FcTeamBusiness.projects` ({key, seasons_left}); `FcFinanceEngine.start_project` charges the cost up front, `advance_projects` runs at every season end and applies the effect (arena capacity is changed on the saved `FcArena`). Controller: `arena_project_options()`, `start_arena_project(key)`; the Finances tab has a picker. The quick "+10 arena quality" button remains for upkeep-style improvement.

## Draft lottery
- `FcDraftRules` (in `FcLeagueRules.draft`): `lottery_teams` (0 = no lottery), `lottery_picks`, `odds_power`. `FcDraftRules.suggest(n)` enters about 45% of the teams and draws up to 4 picks. `FcDraftLottery.order` draws the top picks among the worst non-playoff teams with odds weight (places from best)^1.3, so the worst team is favoured but can fall at most `lottery_picks` places. New leagues get a lottery by default (`draft_lottery` in generation config, `lottery=off` in tools/generate_league); saves made before the rule exist have no lottery. The draw uses its own forked rng stream, so other randomness is unchanged. `FcGameController.latest_draft_report()` rebuilds where each team would have picked without the lottery, so the Market tab shows how many places the lottery moved each team (nothing extra is saved).

## Signing and releasing (human owner)
- `FcGameController.free_agent_market()` lists free agents with their asking salary and years; `sign_free_agent(id)` signs one at his asking price using the cheapest legal route (cap space, then the minimum contract for players asking close to it, then the mid-level exception once per season, tracked in `FcTeamBusiness.mid_level_used_season`). `release_player(id)` waives a player for a buyout of half his current salary (from cash, shortfall becomes debt). The Market and Roster tabs have buttons for both. Signing and releasing are possible during the season; the offseason runs automatically.

## Records and the Hall of Fame
- `FcRecords` (src/league/records.gd) computes the Hall of Fame and single-season records from career rows plus each season's champion and awards (which survive archiving). Nothing extra is saved. Retired players are eligible 2 seasons after their last game and inducted at a score of 60 (production plus MVPs, finals MVPs, titles, first-team selections, scoring titles). In a 12-season 16-team run about 4% of retired players were inducted. The History tab shows it.

## Scouting and the draft
- Each team judges prospects with some error (`FcOffseason.draft_noise`): a base of 6 value points, reduced by the general manager's talent evaluation, and by its scouts' scouting accuracy (up to 3 points for the best staffs). Better-staffed teams draft more accurately. The owner's board (see the next section) shows the same quality of information as ranges.

## Human trades
- `FcTradeDesk` (src/league/trade_desk.gd) evaluates a trade the user proposes through `FcGameController.propose_trade(team, give_ids, get_ids, preview)`. It checks ownership, no-trade clauses, roster limits, the cap trade rule for both teams, then the AI's own valuation (stars weigh more than depth, AI must profit 10%). Nothing moves on refusal or preview. The Trades tab in the UI is built on it. Draft picks are not tradeable yet.

## Career statistics and archiving
- `FcWorld.careers` (player id -> rows of 18 numbers, one per regular season: year, team, games, seconds, points, field goals, threes, free throws, rebounds, assists, steals, blocks, turnovers, fouls) is written when a season finishes (`record_career`) and kept forever; `career_totals(player_id)` sums it. This is the base for player pages, records and the Hall of Fame.
- Seasons older than two years are archived by the offseason (`FcSeason.archive()`): the games, player statistics and stored box scores are dropped; standings, champion, awards, playoff series and draft results stay. An archived season is under a fifth of its original size, so long careers of a league do not make saves grow without bound.

## News and box scores
- `FcWorld.news` is a capped (300) feed of `{date, kind, text, team}` items: stars injured (overall 62+) or any injury on the owner's team, 50-point games (and 40-point games for the owner's team), champions and awards, first draft pick, big signings (55% of the maximum salary or more), retirements of good players.
- `FcSeason.recent_boxes` keeps the box scores of the owner's team's last 20 games (the engine's `watched_teams`); other box scores are not stored. Both are saved.

## User interface (`src/ui/`, `scenes/main.tscn`)
- `FcApp` (the main scene's script) builds the screens in code: main menu (new / continue / load / delete), new league form (areas, valid team counts and layouts, cap style, era, mode, seed), team choice, and the dashboard with tabs Overview, Standings, Schedule, Roster, Finances, Staff, League. `FcUiTables` makes tables and formats money.
- Screens only call `FcGameController`; no rules live in the UI. Public methods (`show_*`, `on_*`, `build_tab`) let tests click through the same paths a player does.
- Status: first, plain version (tables and buttons) intended for testing the rules. Smoke tests prove every screen builds with real data, a whole season and the next one can be played, and saving/loading works; they cannot judge appearance, layout or usability, which needs a human. A News tab, a box score viewer (Schedule tab, last 20 games of your team) and a player profile (Roster tab: bio, ratings, personality, tendencies, contract, career) exist. Not yet: draft and free agency screens, trade screens, responsive/mobile layouts, a theme with real typography, icons and team logos.

## Game controller (`src/game/game_controller.gd`)
The single object a screen talks to. It owns the `FcGameState` and drives everything; it has no UI code.
- Create: `FcGameController.new_game(generator, seed, mode, user_team_index)` or `resume(loaded_state)`.
- Time: `advance_day()`, `advance_days(n)`, `sim_regular_season()`, `sim_playoffs()`, `start_next_season()` (runs the full offseason, returns its report). Phases: regular_season -> playoffs (starts automatically when the last game is played) -> season_complete.
- Information: `standings()`, `user_record()`, `next_user_game()`, `season()`, `owner_report()` (profit, valuation change, wins vs expectation, approval 0-100).
- Owner decisions (Owner Mode): `set_ticket_price`, `set_marketing_budget`, `invest_in_facilities`, `fire_staff`, `hire_staff`, `staff_pool`, `asking_salary`. In Dynasty mode no team is "human" for pricing.
- Saving: `autosave(manager)`. All randomness comes from `state.rng`, which every save contains, so a loaded game plays out exactly as the original would have (tested mid-season and between seasons).

## Business model (`src/league/finance_engine.gd`, `src/data/business/`, `data/simulation/finance.json`)
```
FcTeamBusiness     per team (id = team id): ticket price, marketing budget, facilities level, fan interest, brand, cash, debt, valuation
FcFinanceRecord    per team per season: 8 revenue lines, 9 expense lines, wins, playoff rounds, attendance, end-of-season brand/cash/debt/valuation
FcFinanceEngine    demand(), attendance(), best_price(), initial_business(), invest_in_facilities(), settle()
```
- Demand = capacity x (how much the city cares about the team) x market size x local wealth x arena quality, falling with price (elasticity 1.3). Attendance = demand capped at capacity. The best price is where demand just fills the arena.
- Revenue: tickets, playoff gates (premium), concessions, merchandise (brand x market), sponsorship (brand x market x playoff success), broadcasting (equal share), arena events, luxury-tax share. Expenses: payroll, luxury tax (repeater rate uses the finance history), staff, arena operations, marketing, travel, administration, facilities upkeep, interest. A cash shortfall becomes debt; positive cash repays half of it each year.
- Feedback loops: winning and playoff success raise fan interest; interest and marketing raise brand; both lift next season's attendance and revenue; valuation = revenue x (2.6 + 1.2 x brand) - debt. Arena facilities decay 1.5 points a year and cost money to rebuild.
- Money values are for a $140M cap and scale with the cap; per-game prices scale with season length (a 40-game season charges twice the ticket price) so the economy balances at any season length.
- `FcSeasonEngine.finish_season` settles all teams automatically. `FcSeasonEngine.human_teams` lists the teams whose owner sets price and marketing (Owner Mode); AI teams re-price and use default marketing each season.
- Calibrated (30 teams, 80 games): average revenue about 1.8x the cap, about 11% average margin, a third of teams lose money, large markets earn up to $120M profit, small markets lose up to $45M. Check with `tools/finances.ps1`.
- Not yet: sponsorship deals as negotiable contracts, loans and owner capital injections, arena expansion beyond facilities level, merchandise lines, season tickets, revenue sharing beyond the tax, owner distributions, bankruptcy rules.

## Offseason (`src/league/offseason.gd`, `player_progression.gd`, `player_market.gd`)
```
FcPlayerProgression  yearly development/decline per attribute (potential, peak age, development rate, work ethic, coach player-development skill, volatility); retirement odds by age and ability. Data: data/simulation/progression.json
FcPlayerMarket       value (ability + room to grow for the young - age penalty), asking salary on the generated-contract curve, desired length, contract builder
FcOffseason.run      1 progress_and_retire -> 2 expire_contracts -> 3 re_sign -> 4 run_draft -> 5 free_agency -> 6 fill_rosters
```
- Every signing is checked with `FcCapRules.check_signing` (cap space, own-player exception, mid-level exception once per team, minimum contract, hard limit / hard cap), so the AI cannot break the salary rules.
- Draft: 2 rounds, a new prospect class (age 19-22, upside from years to peak) larger than the picks, order = non-playoff teams by worst record then playoff teams (no lottery yet), picks by value with noise that shrinks with the GM's talent-evaluation skill, rookie scale salaries with team-option years, undrafted prospects become free agents. Results saved on the finished season (`FcSeason.draft`).
- Free agency: up to 14 rounds; teams with the most cap space act first; each round a team signs the best affordable free agent. Rosters end between the league minimum and maximum (minimum contracts fill gaps; excess is waived). 12 fresh free agents enter each year so the pool never dries up.
- Verified over 3 consecutive seasons: world integrity (including contract rules and payroll limits) holds every year, talent stays level, average age stays 24-30.
- Trades (`FcTrades`, run after the draft): contenders (top third by record) and rebuilding teams (bottom third) swap players one for one when both teams gain by their own valuation (contenders value ability now, rebuilders potential and youth), both pass `FcCapRules.check_trade` (hard limit and salary matching), no-trade clauses are respected, contracts move unchanged, at most 2 trades per team a year. Typical result: 1-4 trades per offseason in a 20-team league.
- Not yet: three-team or multi-player trades, draft pick trading, trades during the season, human trade offers, cap holds applied to the market, restricted/qualifying offers, player preferences beyond loyalty, the draft lottery, two-way/G-League players.

## Simulation (`src/sim/`, balance in `data/simulation/`)
```
FcPlayerRatings    28 attributes -> composite ratings (three, mid, finishing, playmaking, perimeter_d, ...) + overall; recipes in ratings.json
FcGameTeam         players (FcSimPlayer, best first) + coach style/skills; built from the world with from_world()
FcSimPlayer        per-game working state: composites, tendencies, energy, fouls, hot/cold form, stats line
FcGameSimulator    simulate(home, away, rng) -> FcBoxScore, possession by possession; all numbers from tuning.json
FcBoxScore         scores by period, player lines, team totals, advanced stats (pace, ORtg/DRtg, eFG, TS, rates); to/from dict
FcPlayerGameStats  one player's box score line
```
- **Headless and pure**: no scene tree, no UI, never changes the world (tested). Same teams + same `FcRng` = identical game.
- **A possession**: (1) non-shooting foul, with free throws in the bonus; (2) turnover vs steal pressure; (3) shooter chosen by scoring ability and usage, shot type (three / mid / rim) from his tendencies and the coach's three-point emphasis; (4) block, shooting foul (and-one), make probability from shooter skill, lineup defense, assisted or not, fatigue, home court, coach skills, personal hot/cold form and a mean-reversion term (below); (5) miss -> rebound contest, offensive rebound keeps the ball.
- **Rotations**: starters = best five with a guard and a big man; subs one per dead ball for fatigue, foul trouble (4 early / 5 late / 6 out), close finishes (stars stay in, better with a high game-management coach) and blowouts (starters rest). Energy drains with court time and stamina, recovers on the bench and between periods.
- **Coach effects**: pace preference (shared game speed), three-point emphasis (shot mix), defensive aggression (turnovers and fouls), ball movement (assists), offensive/defensive strategy skills (small efficiency edge), game management (substitution timing).
- **Variance control**: independent shot luck alone gave a 16-point spread in final margins (real basketball: 12-14). `luck_regression` makes a team that is shooting above its odds cool off slightly, which brings the spread to about 13 and reduced blowouts from 28% to 16% of games. Also a shared per-game pace shift (fast or slow game for both teams).
- **Calibration**: three EARLY/MID/LATE 2010s presets (`data/simulation/eras.json`; default mid_2010s). `tools/simulate_games.ps1` plays N games and compares 16 league averages with the era's ranges, measures home-court edge with identical teams (`mirror`), and with `leaders` plays a whole 80-game season and prints the scoring/rebound/assist/steal/block leaders, 20- and 25-point scorers, 50-point games, minutes and records. All 16 checks pass in all three eras; about 10 ms per game (a 1,230-game season in about 12 s).
- **Injuries**: a player is hurt in a game with a chance per minute played (`injury_per_minute` 0.00025, scaled by durability: fragile players about 2x as often as durable ones). He leaves the game (unless nobody can replace him) and misses 1-82 games (60% minor 1-5, 28% moderate 6-20, 9% serious 21-60, 3% season-ending 61-82). The season engine records `FcPlayer.games_out` / `injury`, counts down one per game of his team, rebuilds the team's lineup without him (a team always fields at least 8), and severe injuries (60+ games) permanently cost 1-3 points of speed, agility, vertical and stamina. The summer heals 60 games; longer injuries carry over. About 12% of games have an injury; a player misses roughly 8-9% of games. Medical staff matter: the average injury-prevention skill of the team's medical staff scales the injury chance (x1.25 at skill 0, x0.75 at 100) and the average rehabilitation skill scales the time out (+15% at 0, -15% at 100).
- **Not modeled yet**: intentional fouling and timeouts, technical fouls, shot clock violations, individual defensive matchups (defense uses lineup averages), player-vs-player chemistry, clutch ratings, the player progression that follows a game.

## Game mode architecture (planned)
A mode defines a permission set (which actions the player does directly vs. delegates to AI staff) and which UI screens are available. Both modes call the same core services.

## UI structure (planned)
Godot Control scenes, reusable components, shared theme. PC and mobile get separate layouts from the same screen logic.

## Testing
See TESTING.md.
