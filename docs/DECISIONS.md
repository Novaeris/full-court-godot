# Decisions Log

Newest at the bottom. Mark revised decisions rather than deleting them.

## Established by the founder (2026-11-15)
Full Court name; basketball management sim; fully fictional universe; Godot 4.x standard + GDScript; Windows first, then Mac/Android/iOS; solo dev; free-to-play; Owner Mode first, Dynasty Mode later; not an MVP; Claude Code as development assistant; Git/GitHub; automated + manual testing.

## D-001 Project folder
Project lives in `C:\Users\dynam\Documents\Full Court` (the folder the Claude session is opened in), not `C:\Projects\FullCourt` as originally written. Decided by founder.
Note: the space in the path is fine for Godot, but scripts should quote paths.

## D-002 Godot version
Godot 4.7.2 stable (standard, non-.NET), installed with `winget install GodotEngine.GodotEngine`. The earlier `godot.exe` was a broken WinGet shortcut. Command line: `godot_console` prints output in the terminal.

## D-003 Renderer
`gl_compatibility` for both desktop and mobile. A management game is UI-heavy, not graphics-heavy; this renderer maximizes device compatibility.

## D-004 Test framework: custom minimal runner (APPROVED)
Chosen: ~60-line headless runner (`tests/run_tests.gd`) + `FcTestCase`.
Alternative: GUT (popular third-party Godot test plugin).
Reasons: zero dependencies, works immediately on 4.7, simple for a beginner to read. GUT can be adopted later if we need mocking/richer reporting; tests are plain methods so migration is easy.

## D-005 Randomness
All simulation randomness goes through `FcRng` (seeded, forkable, state-saveable) for reproducible bugs and consistent saves.

## D-006 IDs
Stable integer IDs per entity kind (`FcIdGenerator`), never reused. Chosen over strings/UUIDs for speed, small saves, and simple dictionary keys.

## D-007 No SQLite yet (APPROVED, with condition)
Deferred. Condition from founder: keep a clean persistence abstraction. Implemented as `FcRepository` with `FcMemoryRepository`; a SQLite-backed implementation can be added later without changing game systems. Revisit when history volume demands it.

## D-008 Line endings (APPROVED)
`.gitattributes` forces LF for Godot/data/text files and CRLF for `.ps1`/`.bat`. No remote repository or push until the founder explicitly authorizes it.

## D-010 Save format (2026-11-15)
- JSON text: header line + payload, SHA-256 checksum, one file per slot under `user://saves/`.
  Alternatives: binary/compressed (smaller, not debuggable; can be added later via format version), SQLite (deferred, see D-007), Godot Resource files (tied to engine internals and unsafe to load from untrusted files).
- Atomic write with verification and `.bak`; recovery order main → temp → backup.
- `DATA_VERSION` + step migrator; newer saves refused rather than guessed at.
- Saving never refused for integrity problems; loading reports warnings.
- `user://` is the per-user game data folder (on Windows: `%APPDATA%\Godot\app_userdata\Full Court\`). Works on all target platforms.
- Bug found and fixed while designing: JSON numbers are doubles, so 64-bit RNG state/seed are saved as text.

## D-011 Staff model (2026-11-15)
- Staff mirror players: identity + data-driven attribute sets (skills, personality, philosophy). `FcPlayerIdentity` was renamed `FcPersonIdentity` and shared; the saved format did not change.
- Roles are a closed enum (rules refer to them: one GM, one head coach per team); skills are data.
- Staff have their own contract entity rather than reusing `FcContract`. Rejected alternative: one contract type with a subject kind. It would force salary-cap/guarantee semantics onto staff pay, and changing the player contract format would need a save migration. Cost: a little duplication of year/season queries.
- A staff member's `primary_role` (profession, for browsing the hiring pool) is separate from the role on their contract (the job held).
- Team staff = ACTIVE staff contracts; there is no separate staff list to keep in sync.
- Staff sections in snapshots are additive (missing = empty), so DATA_VERSION stays 1. If a future change removes or reinterprets saved fields, bump it and add a migration.
- What staff skills DO (coach quality affecting development, GM evaluation affecting trades, scouting accuracy) is deliberately not implemented; each hooks in when its system is built.

## D-012 Procedural generation (2026-11-15)
- Content in JSON (`data/generation/`), logic in `src/gen/`. Names: 7 pools mixed per fictional country (Aldoria is home; Brenmark, Castellia, Tarsany, Kalunda, Shirane, Highcourt supply ~20% international players). Cities, countries, nicknames, arenas are all fictional; nicknames avoid real pro team names.
- Hand-curated city and nickname lists rather than syllable-generated names: better quality and no accidental unfortunate names; 40 of each is enough for a 30-team league and some expansion. Can be extended or made procedural later.
- Player quality comes from one `level` plus position profile and shared latents, so attributes correlate sensibly. Rejected: independent random attributes (unrealistic players).
- League structure (30 teams) is a generation DEFAULT in config, not a league rule; conferences/divisions are a later system. Founder input needed when that system is designed.
- Contracts are generated partly served (started up to N-1 seasons ago) so expirations are staggered from day one.
- All generation numbers are first drafts; they will be tuned with the simulation and stress tests.

## D-014 Real-world places, original franchises (2026-11-15, founder decision)
- The founder dropped the "fully fictional world" requirement: cities and countries are now real and selectable by area (North America, South America, Europe, Asia, Oceania, Africa). Supersedes the fictional-geography parts of D-012 (Aldoria and the other invented countries were removed).
- Kept: teams, players, staff and branding are original and generated. Real franchises, real player names and logos would require licensing and were excluded by the founder's original brief. Team nicknames avoid real pro team names (but a generated "Paris Barons" could coincide with a real club; that is accepted, names are generic).
- City data: 154 cities (after the 2026-11-15 expansion, see D-016) with approximate metro populations and a 0-100 "economy" game-balance index (not an official statistic) in `data/generation/world.json`. Coordinates there are used only to group teams geographically and are not saved on FcCity yet (add them when travel/time zones are built).
- Politically sensitive places were added later (see D-016).
- Name styles: 15 pools (anglo, hispanic, west_african, south_european, east_european, nordic, east_asian, western_european, middle_eastern, south_asian, southeast_asian, east_african, hebrew, persian, caucasus) mixed per country. They are approximations; expect to refine them.

## D-015 Customizable league structure (2026-11-15, founder request)
- `FcLeague` > `FcConference` > `FcDivision` > team ids, a saved entity with stable ids. Membership lives in the division (single source of truth). Several leagues per world are possible (additional leagues are a monetization idea).
- Customization lives in `FcGenerationConfig` (the future "new league" screen edits it); `validate()` returns plain-language messages. Auto-grouping is geographic. Names are generated (Western/Eastern, South/North...) and are meant to be user-editable later. Explicit per-team division assignment is supported by the data model (`add_team`/`remove_team`) but has no generation option yet.
- Rules (season length, playoffs, salary cap, schedule format) are NOT part of the league structure; they will be separate rules data keyed by league_id so leagues can differ.
- Saving: `leagues` and `FcCity.area` are additive snapshot fields, so DATA_VERSION stays 1 and older snapshots load (no league / empty area).

## D-016 Sensitive places, nationality share, naming (2026-11-15, founder requests)
- Russia, Ukraine, Belarus, Georgia, the Balkans, Israel, Iran, Gulf states, Taiwan, Hong Kong, Kosovo, Puerto Rico and more were added. Rule: every country is shown under the name it uses for itself in English (Russia, Taiwan, Hong Kong, Kosovo, Türkiye, Czechia, Côte d'Ivoire, Democratic Republic of the Congo, Israel...). The game takes no position on disputes; entries are data in `names.json` / `world.json` and can be adjusted if a player or region objects.
- A seventh area, Middle East, was split out of Asia so users can choose it. The UAE and Dubai moved there.
- Default home-country share raised from 55% to 65%; the remaining players come from all countries by talent weight.
- Team names: users may set nickname and abbreviation per team; everything unset is generated. Limits: nicknames up to 24 characters and unique; abbreviations 2-4 capital letters and unique. A single-name generator (`random_team_nickname`) supports a "generate a name" button.

## D-017 League size and structure (2026-11-15, founder request)
- At creation: 4-64 teams, conferences 1-4, divisions per conference 1-8, EVERY division the same size, 3-8 teams (a 4-8 team league may be one division). Team counts with no valid layout (11, 13, 17, 19, 22, 23, 26, 29, 31, 37, 41, 43, 47, 53, 55, 57-59, 61, 62) are refused with a list of nearby sizes that work. Reason: fair schedules and brackets.
- Why a 4-team minimum: with at most 4 games per opponent, a 2-3 team league cannot reach a 10-game season.
- Expansion: a saved league may grow to 64 teams (D-031; earlier note said 100). Inside a save uneven divisions are legal; the future expansion system must rebalance and re-validate schedules.
- The earlier behavior of splitting an uneven team count by distributing remainders was removed from validation (the helper `FcLeague.make_even` still does it for previews).

## D-018 League rules (2026-11-15, founder request)
- Schedule: founder's guideline of 2-3 games vs each division opponent, 1-2 vs other-division conference opponents, 1-2 vs other-conference opponents. FINDING: inside those ranges a 30-team league plays only 33-62 games and a 16-team league 21-33. So ranges are recommended, not hard: allowed 1-5 / 1-3 / 1-3, and `suggest` picks values near a target. UPDATE (founder, same day): the standard 30-team league should play 80 games, an even number, and other sizes should follow the same rule. Target is now 80; an odd season length is penalized; 30 teams = 5/3/2 = 80 exactly. Division opponents may now be played up to 5 times.
- Playoffs: both formats requested are supported (division-leaders bracket and pure seeding) with per-conference or league-wide brackets and best of 1/3/5/7 per round. Not yet implemented: play-in tournaments, reseeding rules, home-court patterns (2-2-1-1-1), tiebreakers (these belong to the standings/playoff engine).
- Salary cap: see D-019.

## D-019 Salary cap: soft cap with a hard limit (2026-11-15, founder preference)
- Chosen default. A team can only sign free agents with cap space, but may exceed the soft cap to re-sign its own players, use a single mid-level exception, and sign minimum contracts; payroll above the tax line (120% of cap) pays 150% tax; the HARD LIMIT (135% of cap) can never be crossed by any transaction. This keeps stars with good teams while preventing a rich team from buying everyone.
- Anti-hoarding supports beyond the limit: maximum salary 30% of the cap, minimum payroll 85%, maximum contract length 5 years, raises up to 8% per year, roster maximum 15, trade salary matching at 125% when over the cap.
- Alternatives shipped as presets: strict hard cap (no exceptions) and no cap (tax only).
- The further ideas proposed here were approved and built the same day: see D-020.
- Implementation status: rule logic and validation only. Free agency, trades and the draft will call it.

## D-020 Extra salary rules and naming/IP check (2026-11-15, founder approved)
- Built (all configurable, all scale with the cap): tax sharing to teams at or under the cap (100%); repeater tax (+100 points after 3 tax seasons of the last 4); restriction line at 127% of the cap (no mid-level exception, trades must match salaries); rookie pay scale (first pick 8% of the cap down to the minimum, 4-year deals, 2 guaranteed); cornerstone extension (35% of the cap, 6 seasons with the team, performance criterion supplied by the future awards system, 1 per team); cap holds (120%); sign-and-trade limits; no-trade clauses (after 8 seasons, player consent). Only the soft-cap preset enables all of them; the hard-cap preset disables tax rules, the restriction line, cornerstone and sign-and-trade; the no-cap preset keeps tax sharing and repeater tax.
- IP check on "supermax" (research done 2026-11-15): "supermax" is a media/fan nickname; the official term in the NBA's agreement is "Designated Veteran Player" and no trademark registration for "supermax" was found in the search. Game rules and mechanics are not protected by copyright (only creative expression such as names, art and text), and a salary cap is a labor/contract system, not IP. We nonetheless use our own name, "cornerstone extension", and avoid league-branded terms ("Bird rights", "Designated Veteran/Rookie", "apron", league names, trophy names). "Mid-level exception", "luxury tax", "rookie scale" and "sign-and-trade" are generic terms used across sports and contexts, so they stay. This is research, not legal advice: have a lawyer review names, terms and trademarks before a commercial release.
- Not built (need systems that do not exist yet): applying these rules in free agency, trades and the draft; accolade tracking for the cornerstone criterion; tenure tracking; tax payments in the finance system.

## D-021 Basketball simulation v1 (2026-11-15)
Built on the founder's instruction to continue; the following product choices were made on the founder's behalf and are listed for review. All are data in `data/simulation/*.json` or small code switches.
1. **Possession-by-possession simulation** (not play-by-play animation, not a score-from-rating formula). Gives real box scores, minutes, fouls, rotations and an interpretable "why". Cost: ~17 ms per game. Alternative rejected: a single-formula score generator (fast but no box scores or tactics).
2. **Ratings drive everything.** Attributes -> composite ratings -> probabilities, so rebalancing is a JSON edit. Individual matchups are NOT modeled (defense = lineup averages) to keep the first version tractable.
3. **Coach philosophy matters** (pace, threes, aggression, ball movement, game management). Coaches are therefore worth hiring in Owner Mode.
4. **Realism targets**: league averages in the ranges of a modern professional league (about 114 points, 98 possessions, 35% of shots from three, 22 free throw attempts), home court worth about +2 to +3 points, stronger teams winning about 70% and weaker about 25-30%.
5. **Game length**: 4 x 12 minutes, 5-minute overtimes (tuning values; will move to league rules).
6. **Variance**: tuned to the real spread of results (see ARCHITECTURE "Variance control"). More randomness (upsets) or less (predictable) is one number (`luck_regression`, `form_sd`).
7. **Stars**: usage grows with the cube of scoring ability, so a great scorer takes a large share (individual 60+ point nights occur about once per 1,500 games). Change `usage_exponent` to flatten or sharpen this.
- Known tuning items: the best-vs-worst gap and blowout rate (16% of games decided by 25+) are slightly higher than real leagues; deep bench minutes and garbage time are simple; free-throw rate and fouls sit near the top of the realistic range.
- A bug found and fixed while building the stress tool: an "equal teams" test that reused one team object for both sides silently corrupted shared state. Teams must be separate `FcGameTeam` objects (tests now guard this by building two).

## D-022 Simulation calibrated to the 2010-2020 NBA (2026-11-15, founder request)
- The founder asked for the pace and style of the NBA between 2010 and 2020. The first version scored about 115 points per team on 99 possessions (an efficiency no season in that decade reached), so it was recalibrated.
- Three era presets in `data/simulation/eras.json` (an overlay on `tuning.json`, plus the target ranges the stress tool checks): `early_2010s` (about 2010-13: 92 possessions, 100 points, only 20% of shots are threes, mid-range game), `mid_2010s` (DEFAULT, about 2014-17: 96 possessions, 103 points, 28% threes, 46% FG, 35.5% 3P), `late_2010s` (about 2018-20: 100 possessions, 110 points, 38% threes). A league stores its era in `FcLeagueRules.sim_era` (`FcGenerationConfig.sim_era`).
- Reference figures are typical league averages recalled from public NBA statistics, not exact season data; a data-driven check is available (`tools/simulate_games.ps1 era=...`). Adjust the ranges in eras.json if more exact numbers are supplied.
- Stars (founder comment: averaging 30 a game is very doable, 60 is not): usage grows with a scorer's rating but saturates (`usage_exponent` 2.8, `usage_max_rating` 78), players are capped at about 39 minutes (soft cap) and a rotation of about 9-10 players results (top five play 30-36 minutes). Season check (`./tools/simulate_games.ps1 leaders`): scoring leaders average 29-34 points, 25-40 players average 20+, about 5-25 fifty-point games a season, rebounds leader 13-14, assists leader about 8. Season results depend on how many stars the generated league happens to contain (seed to seed variation is expected).
- Known gaps: overtime games are about 2% (real about 5-6%; the end-of-game fouling and timeout logic that makes close games closer is not built), assist leaders (about 8) are below real point guards (10-11), best/worst team records (73-12 over 80 games) are slightly wider than real (65-17).

## D-023 Season engine and league balance (2026-11-15)
- Built autonomously (founder away): calendar, standings with tiebreakers, playoffs, awards, season statistics. See ARCHITECTURE "Season engine". Choices: playoff games advance in lockstep (one game of every ready series per playoff day) with a 5-day gap after the regular season; box scores are not saved (too large), only results and accumulated statistics; completed seasons keep standings, champion, awards and statistics.
- Competitive balance was measured with a full-season check and tightened: the first generated leagues had a best team at 71-9 and several below 15 wins. Generation now uses `team_strength_sd` 0.8 and `player_level_sd` 3.0 (were 2.0 and 5.0), giving a spread of team winning percentage of about 0.147 (real NBA 0.14-0.16), best teams about 63-65 wins and worst 12-20 of 80, while scoring leaders still average about 32 points (6-8 players above 25). Both values are in `data/generation/config.json`.
- Known simplifications: tiebreakers omit multi-team subtleties; no play-in tournament; no all-star break or trade deadline; the calendar has no holidays or neutral sites.

## D-024 Offseason model (2026-11-15, autonomous)
- Progression targets potential by peak age with noise; decline is steeper for physical attributes. Players retire from 33 with a rising yearly chance (9% per year over 32, +18% if weak), forced at 42.
- Teams re-sign expiring players with a probability that rises with value (and slightly with loyalty); contract length shortens with age.
- Draft order has no lottery (simpler and transparent); a lottery can be added as a rules option.
- The AI is intentionally simple (best available affordable player). It never trades. Owner Mode will let the human replace the AI's decisions for one team.
- Staff are not aged or renewed yet (their contracts will need a rollover step).

## D-025 Owner Mode business model (2026-11-15, autonomous)
- The owner's levers in v1 are ticket price, marketing budget and facilities investment (plus, through the GM, payroll via the salary rules). The AI sets a revenue-maximizing price (fills the arena) and default marketing for every non-human team.
- Chosen realism: big markets earn far more but the cap and tax narrow the gap; a third of teams lose money in an average year. Targets are a typical professional league's, not exact figures.
- Brand and fan interest move slowly (catch-up rates 0.20 and 0.30 per season) so success compounds over years; a losing franchise's interest decays.
- Per-game prices scale with season length so short seasons are not unprofitable by construction.
- To be built on top: owner decisions UI, sponsorship and loan negotiations, the owner's own targets and evaluation (profit, wins, valuation), GM/coach hiring and firing, arena renovation projects.

## D-026 Injuries (2026-11-15, autonomous)
- Injury rate and severity mix are single numbers in tuning.json (`injury_per_minute`); setting it to 0 turns injuries off. Rates were chosen so a player misses about 8-9% of games, typical of a professional league, and durability matters but never makes a player immune.
- Injuries are stored on the player (`games_out`, `injury`) and drive lineups for both AI and human teams. The owner currently cannot rest players or rush returns. Medical staff skills now apply (injury prevention changes how often, rehabilitation how long).
- Severe injuries cost athletic attributes permanently so careers can be altered by luck.

## D-027 AI trades (2026-11-15, autonomous)
- Only one-for-one swaps between a rebuilding team (gives a 27+ veteran) and a contender (gives a player of 25 or younger), and only in the offseason. Simple, always roster-neutral, and it moves talent from weak teams to strong ones while moving youth the other way, which should slow permanent dynasties without stripping stars at random. Draft picks are not tradeable yet (the draft is a pure function of the standings).
- A human owner cannot yet propose or accept trades; that needs a UI and a valuation shown to the player.

## D-029 Modes defined (2026-11-16, founder; supersedes the open parts of D-028)
- **Owner Mode**: the player controls every operation of the franchise; simulated for up to **50 years**; the player **cannot lose**, but may transfer to another franchise "like a job" (job offers depend on their track record). Randomized players.
- **Career Mode**: the player creates one player and takes them through an RPG-style progression, about **20 years**. Randomized players.
- **Dynasty Mode**: a **card-collecting** game inspired by NBA 2K MyTeam with **static players made by the founder**; has **paid features**.
- Art and audio will be produced with AI tools (founder). Platform priority after Windows: **mobile** (Android/iOS), so touch-friendly layouts move earlier in the plan.
- (Note 2026-11-18, D-036: "cannot lose" is kept; a distressed owner's debt is restructured at a price instead of ending the game.)
- Consequences: the 50-year target is an M2 requirement (health, performance and save size over 50 seasons); Dynasty Mode is a separate product track (collection, lineups, likely online); legal review must cover loot-box rules, AI-generated assets (rights, store disclosure) and invented names.

## D-032 Published to GitHub (2026-11-17, founder)
- The founder authorized publishing: a PUBLIC repository `Novaeris/full-court-godot` was created and the whole history (86 commits) pushed. The name `Novaeris/Full-Court` already belongs to an earlier, different TypeScript project and was not touched.
- Consequences to keep in mind: the commit author email is public; there is no LICENSE file (all rights reserved by default); the docs, including design and business notes, are public; invented names should still get the legal check before a commercial release (D-020). Pushes happen only when asked.

## D-031 Owners' meeting (2026-11-16, founder)
- Relocation and expansion are in Owner Mode; teams vote on rule changes, expansion and similar items in a stage of the offseason.
- AI owners have **no fixed personalities**: each vote comes from the team's current situation (record, payroll, profit, market) plus a fresh mood each year, so votes can change from year to year.
- The league size ceiling, including expansion, is **64 teams** (this replaces the earlier 100-team ceiling in D-005's note).
- Votes **may change how the game plays** (playoff series, season length, roster size, lottery, cap level), not only money and structure rules.
- The player's "influence" mechanic is still being defined (see the plan); stage (a) of the meeting has the player's one vote and a view of how every owner leans.

## D-030 Platforms by mode (2026-11-16, founder)
- PC (Windows first, Mac later) carries all three modes. Mobile (Android/iOS) carries **Dynasty Mode only**.
- Consequences: Owner and Career Mode UI is desktop-first (no touch-first redesign needed, no phone performance or save-size limits for Owner/Career); the mobile work in the plan (M5) is about the Dynasty card game; the simulation core still has to run on phones because Dynasty matches use it, so it must stay light and headless-capable.

## D-028 Three modes (2026-11-16, founder)
- The game has three modes: Owner Mode, Career Mode and Dynasty Mode. Owner Mode is built first (current work). Career Mode needs a definition from the founder before any design or code; Dynasty Mode (deep roster/lineup control) comes after Owner Mode. `FcGameState.MODES` currently lists only owner and dynasty; add career when it is defined.
- Consequence: Dynasty-mode features (e.g. setting lineups and minutes) are not the next priority; Owner Mode keeps getting depth first.

## D-013 Floats in saved data; runner robustness (2026-11-15)
- Found by a test: JSON float round trips lose last bits, so a saved-and-reloaded world differed from the original. Rule: saved floats are quantized to 3 decimals via `FcChecks.quantize` in property setters; prefer integers. Documented in ARCHITECTURE rule 7.
- Found while testing: a test file with a syntax error made the test runner hang forever. The runner now reports such files as failures.

## D-009 Data model shape (2026-11-15)
- Entities reference each other by integer ID only (no object references): no circular dependencies, trivial serialization.
- Player is split into identity, physical, development and three attribute sets. Contracts, team membership and statistics are NOT on the player.
- Contract is an independent entity (`player_id`, `team_id`, years, options, bonuses). Money is integer dollars.
- Roster is the single source of truth for team membership; contracts must agree (validated in `FcWorld`).
- Attributes, personality traits and tendencies are data (`data/definitions/*.json`), separate from values (`FcAttributeSet`). One mechanism serves all three.
- City and Arena are their own entities so relocation/renovation do not require changing team identity.
- Seasons are identified by the calendar year in which they start.
- Alternatives rejected: one large Player class (hard to evolve); salary stored on player (blocks options, bonuses, history, cap queries); attributes as hard-coded variables (every balance change needs code edits).
- Statistics, history, finances, staff and owner are deferred as separate records keyed by id, to be designed with their systems.

## D-033 Long-run economy (2026-11-17, founder asked for it; details chosen by Claude)
- Money grows with inflation (about 3% a year) and the salary cap follows league profit toward a 6% average margin, instead of staying fixed. The cap never falls in dollars.
- Surplus cash is spent on building projects (AI automatically, human by choice) and paid out as dividends; a new-arena project exists.
- Alternatives rejected: a fixed profit cap (feels artificial), taxing cash directly (confusing), growing revenue only (does not fix margin).

## D-034 Relocation: the owner chooses the city and the name (2026-11-17, founder)
- When the owner moves their franchise, **they choose the destination city and may rename the team** (the AI still picks its own destination and keeps its name). The proposal still needs two thirds of the owners and costs influence points; the mover pays the relocation fee plus half of a new arena; clubs already in the destination's region lose fans.
- Built: `FcRelocation.destinations / plan(city) / execute(city, nickname)`, `FcGameController.relocation_options / propose_relocation`, a chooser on the Meeting tab.

## D-035 Long-run economy details and AI reactions (2026-11-17, Claude's recommended choices, founder asked for these to be completed)
- Inflation about 3% a year with seeded variation; the cap follows league profit toward a 6% average margin and never falls; surplus cash goes into building projects (AI automatically) and dividends; a new-arena project exists.
- AI clubs remember trades (wariness) and meeting votes (rapport); a team moving into a region costs its neighbours fans.
- Season tickets and promotion nights are owner levers (default off). Staff chemistry changes player development by up to about +/-6 coaching points. The general manager's negotiation moves salaries by up to 5% and trade profit by up to 8 points.
- Overtime: trailing teams play for the last shot (about 4.0% overtime games; late fouling added the same day brought it to about 4.4%; the turnover recalibration of 2026-11-18 lowered it again to about 3.7%).

## D-036 Debt restructuring keeps the owner in the game (2026-11-18, founder chose "keep 'cannot lose' + restructuring")
- The owner still cannot lose the franchise (D-029). When debt passes 1.0x the club's value (floored at 0.5x the cap), lenders cut it to 40% of the pre-adjustment value; at most once per 3 seasons; no cash is added; reputation -15; loans frozen for 3 seasons; the write-off is tracked apart from operating profit.
- AI clubs follow the same rule, and an AI club in debt signs minimum contracts only and keeps payroll within 65% of its revenue.
- Alternatives rejected: warnings only (the $16B spiral stays possible) and a forced transfer (changes what "cannot lose" means).

## D-037 Small-market economy follow-up (2026-11-18, Claude's recommended choices because the founder was away)
- Revenue sharing doubled; the owner's GM keeps payroll within 65% of revenue unless the budget is aggressive; a plain distress warning is shown to the owner. Result: restructurings in small-market seeds halved, not eliminated (`docs/STABILITY_REPORT.md`). Reversible: the numbers are in `data/simulation/finance.json` and `FcGameController.gm_payroll_limit`.

## D-038 Career Mode architecture (2026-11-18, recommended answers; see `docs/CAREER_MODE_PLAN.md`)
- One shared player type (`FcPlayer`) plus a sidecar `FcCareerProfile`; the shared 0-100 attribute catalog is kept (builds validate into 25-99); save data version 2 with a real migration; pure rules in `src/career`; no multiplayer backend. Phases 1 (domain) and 2 (creator) built; progression, the calendar and games are next and need no further decision unless the founder wants changes.

## D-039 Career Mode: potential is the cap on overall, growth is player-directed (2026-11-18, founder chose "player-directed growth")
- Goal of a career: reach the maximum overall (potential) without maxing every skill. Overall is a weighted average, so skills that weigh more (defense 7; shooting, finishing, handling, passing 6) move it most; durability, leadership and work ethic weigh 1.
- The career player no longer gets the offseason's automatic growth. The same growth number (`FcPlayerProgression.growth_points_for`, the exact original expression) is converted to development points (`growth_to_points`, measured and set to 17). Decline and the 28 noise draws per player still happen, so no other player's random stream moves; Owner Mode and AI players are unchanged.
- `raise_preview` is the single calculation behind the Develop tab and the real raise. A raise is blocked if the displayed (rounded) overall would pass potential; blocked rows say why. Banked points stay spendable (for example to hold the rating through decline).
- **Deviation to note:** besides `growth_to_points`, the cost schedule was flattened from 1/2/3/4 (at 0/60/75/85) to 1 until 92, then 2, and `ceiling_base` went 55 to 65. With the old curve cheap low-weight skills beat the heavy ones, so focused and even spending ended equal. Measured results are in `docs/ARCHITECTURE.md`.
- Reaching potential claims a one-time milestone (`potential_reached`: XP, a skill point, currency), shows a banner and a news line; nothing ends there.

## D-040 Career Mode: a light prospect step (2026-11-19, Claude's recommended choice, founder away)
- Instead of a second league (college or development league), the prospect stage is a scouting report: `prospect_score` (0.6 overall + 0.4 potential) gives a projected pick, a seeded draft-night surprise of up to 2 picks, and the team holding that pick (weakest roster picks first). The rookie contract follows the pick slot. A full pre-professional league stays unbuilt until there is a reason to simulate one.

## D-041 Career profile id is a text id, unique per save, not an `FcIdGenerator` id (2026-11-19, found in the stabilization audit)
- `FcCareerProfile.profile_id` is text ("fcp_" + 16 hex digits) drawn from the seeded `FcRng`. It is an **exception to rule 3** (integer ids from `FcIdGenerator`): the world's integer `player_id` stays the real key; `profile_id` only names the career record. It is unique within one save (`FcGameState.validate` checks) and deterministic from the seed, so two saves made from the same seed get the same id. Earlier comments and docs called it "globally unique, never reused"; that was wrong and has been corrected.
- No saved-format change, so no migration and no `DATA_VERSION` bump. If a globally unique id is ever needed (online), it would be a new field added with a migration.
- Related, **proposed and awaiting founder approval** (not yet a decision): Career Mode is a complete single-player game; online team play, if built, is a later Dynasty-side track, asynchronous or server-simulated first. `docs/CAREER_MULTIPLAYER_READINESS.md` is kept only as a "does not block it" audit.

## D-042 Content publishing: content ships separately from the game (2026-11-20, founder request; recommended answers for the details)
- Players, cards, packs, challenges, seasonal config and artwork reach the game as **versioned content releases** from a separate tool, Creator Studio, without a new game build. Anything needing new code (mechanics, simulation) is still an app update: a release lists `requires_features`, and an unknown feature makes it INCOMPATIBLE (fail closed).
- **Local and offline first.** Both programs use a shared content directory (default `Documents/FullCourtContent`, user-configurable). Remote hosting, accounts and APIs are not built; `FcContentStore` is the seam where they would plug in later.
- **Owner approval is mandatory.** Saving, editing and validating never publish. Only an approval (named approver, note, bound to one draft's content hash, single use) lets the publisher write a release.
- **Releases are immutable** and previous ones are kept; the active release is a small pointer file replaced crash-safely; rollback only moves the pointer. The game falls back along `previous_release_id` and then to a small bundled starter release, and always reports what it loaded and why.
- **One shared source.** `src/content/` is the single copy of the format code. Creator Studio (`creator_studio/`, its own Godot project in this repo) reaches it through two Windows folder junctions, `creator_studio/game_src` to `src` and `creator_studio/data` to `data` (`tools/link_studio.ps1`; the links are git-ignored because Git would otherwise store second copies). Milestone 0 showed class_name and load() resolve through a junction; building the Studio then showed `src/content` also needs `src/core`, `src/data` and `data/definitions`, so the whole of `src` and `data` is linked (the first probe linked only one folder). Symlinks need admin rights and a second res:// mount is not supported by Godot.
- Standalone loader now, Dynasty gameplay later (the founder approved building the loader before Dynasty is scheduled). The save-data version is NOT bumped; Dynasty ownership data will add it, with a migration, when it exists.

## D-043 Dynasty Mode scope and packs (2026-11-20, founder assignment; supersedes the "no paid random packs" recommendation of the old draft)
- Dynasty Mode is a complete offline, free-to-play card game: collect, build, compete, earn. Random packs ARE in, bought with in-game currency only (credits, tokens, shards). No real-money purchases or payment code. Pack odds are published (visible in the market). Card gameplay ratings, attributes and badges are static: duplicates become shards or cosmetic mastery, never stats.
- Official content comes only from Creator Studio releases; the game invents none. `docs/DYNASTY_MODE_PLAN.md` holds the audit, plan and progress.

## D-044 Dynasty saves are a separate versioned file (2026-11-20, recommended answer)
- A Dynasty profile is `user://dynasty/<slot>.dyn` with `FcVersion.DYNASTY_DATA_VERSION` and `FcDynastyMigrator`, not part of `FcGameState`. Reason: Dynasty needs no league world, and a separate file keeps Owner/Career saves (`DATA_VERSION`) untouched and a future server-side replacement easy (`FcDynastyStore` is the boundary). Safety matches the main saves (checksum, temp file, backup).

## D-045 Dynasty content schema extensions (2026-11-20)
- New `requires_features`: `pack_odds_v1`, `card_market_v1`, `challenge_v1`, `season_v1`, `dynasty_config_v1`, plus optional player fields (secondary position, badges, tendencies, team). Old releases and the bundled starter still load. Economy numbers (pack price, odds, card price) exist only in published content; engine defaults (game rewards, shard values, mastery costs) are in `data/dynasty/economy.json` and overridable by a release.

## D-046 Dynasty uses the simulator unchanged (2026-11-20)
- The roster becomes a hand-built `FcGameTeam`: starters are forced with `role_bonus`, the rotation uses `minutes_pref`, badges use the Career composite bonus. No change to `FcGameSimulator`. Card overall = the existing `FcPlayerRatings.overall` of the card's attributes; team overall is a weighted average of the 13 slots (`team_overall_weights` in the economy data).

## D-047 UI/UX polish milestone: direction and phasing (2026-11-20, founder approval of the plan in `docs/UI_POLISH_PLAN.md`)
- One design system ("Hardwood Night": Barlow Condensed for display, Inter for body, Lucide icons) with **three presentation personalities** applied as mode skins that may change only a whitelist (accent, background treatment, density, header style, motion intensity, numerals): **Broadcast** (post-game in every mode, and Career, D7), **Collectible** (Dynasty), **Franchise** (Owner). Components are shared, never forked per mode.
- Desktop and mobile are separate presentation targets. Owner and Career are desktop-designed; smaller screens must stay usable (minimum window 800x600), not mobile-optimised (D6). Dynasty is the mobile release target.
- Gameplay presentation is **results-first** (post-game screen); no live playback and no simulation change. Pack artwork is procedural. The Creator Studio entry point is development-only.
- Phases 0 to 2 are one milestone; **Phase 3 and later need a report and the founder's go-ahead.**

## D-048 UI-only state and preferences (2026-11-20, founder approval)
- A UI-only sidecar store (`user://ui_state.cfg`) may hold presentation state such as "seen card" markers. It is not a save: no `DATA_VERSION` bump, safe to delete, and existing cards count as seen on first use. UI settings (reduce motion now; audio and haptics in Phase 11) are added to `preferences.cfg` additively.

## D-049 Box-score pass-through for the post-game screen (2026-11-20, founder approval, conditional on Phase 0; **confirmed necessary**)
- Phase 0 found that `FcDynastyController.last_game["summary"]` has only the user's side (no period scores, no opponent lines, few team totals). When Phase 9 is built, the transient `FcBoxScore` is passed through `last_game` (in memory only, not saved, no simulation change). Owner Mode already keeps full boxes.

## D-050 Player visual identity (2026-11-20, founder requirement for Phase 7)
- A player keeps **one visual identity everywhere** (roster, profile, post-game, trade, comparison, card). A single pure, deterministic resolver (`FcPlayerVisual`) is the only way screens obtain it: it hashes a stable key, consumes no game RNG, and reads or writes no player data. Tiers T0 (monogram), T1 (card art) and T2 (stylised procedural figure) are built; T3 (full-body pose sprites) and T4 (richer rendering) are designed as provider slots and **not implemented** (D5). Audio sourcing is deferred to Phase 11 and no unlicensed asset is ever added (D4).

## D-051 Shell and navigation model (2026-11-20, UI polish Phase 3)
- **Back is hierarchical.** Each screen declares its parent when it is shown (`FcApp._reset(title, {back: ...})` into `FcNavigator`); Escape, the Android back button and on-screen Back all call the same action, and an open dialog closes first. No history stack, so it cannot get out of step. The main menu has no Back; a game in progress asks before returning to the menu. `application/config/quit_on_go_back` is off so the app (not the engine) decides what the Android back button does.
- **Messages are toasts.** `_say` and `notify` show a toast and record it (`FcNotifier.history`); `app._message` stays as a hidden text record because tests and tools read it. Toasts pass clicks through on desktop (they once swallowed a click on "Sign selected free agent") and are tappable on touch.
- **Presentation target.** `FcLayoutProfile` picks desktop or mobile (a mobile OS, or touch with a window narrower than 900 px; a Settings override). Dynasty shows top tabs on desktop and a bottom bar with More on mobile; the bar belongs to the frame. Owner and Career stay desktop-designed (D6): a screen wider than the window scrolls sideways.
- **Skins per mode** are applied by the screens through `_reset` options: Owner Franchise (tinted by the team colour, letterhead header), Career Broadcast (grid backdrop, lower-third header), Dynasty Collectible (spotlight backdrop), everything else Neutral.
- **Deleting a save asks first** (destructive dialog, focus on Cancel). Existing-test change: the main-menu card assertion now expects a name plus a status chip instead of one "(Available)" label.

## D-052 Dynasty hardening and a stricter test runner (2026-11-20, founder-requested milestone; see docs/DYNASTY_HARDENING.md)
- Dynasty save slots are discovered from `.dyn`, `.dyn.tmp` and `.dyn.bak` (recovery order: saved file, temp, backup), so a recoverable profile is never invisible and a new profile never takes its slot. Checksums and versions are not weakened.
- A release is playable only if it has 13 different players AND a legal starting five (primary or secondary position, one slot per player). One shared rule (`FcDynastyContentRules.lineup_problem` / `match_starters`) serves the publish validator (rejects releases with 13+ players that cannot field a team), the catalog and the automatic lineup (which it repairs only when the greedy pass left a starter empty).
- `FcDynastyEconomy.apply` enforces request idempotency: a repeat returns the original transaction with `replayed: true`; the same id with different parameters fails with `request_conflict`; failed requests reserve nothing. No save format changed; neither data version changed.
- The unit and live runners use Godot's `Logger` to fail any test during which a runtime script error occurred. Limitations are documented (push_error and engine messages are not failures; hangs are left to the CI timeout).
