# Decisions Log

Newest at the bottom. Mark revised decisions rather than deleting them.

## Established by the founder (2026-11-15)
Full Court name; basketball management sim; fully fictional universe (changed 2026-11-15 to real places with original teams and people, see D-014 and below); Godot 4.x standard + GDScript; Windows first, then Mac/Android/iOS; solo dev; free-to-play; Owner Mode first, Dynasty Mode later; not an MVP; Claude Code as development assistant; Git/GitHub; automated + manual testing.

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

## D-053 One post-game screen for every mode (2026-11-20, UI polish Phase 9)
- `FcPostGameModel` (pure) turns a box-score dictionary into one view-model (final score, line score, team comparison, top performers, a labelled player-of-the-game pick, both teams' lines, season implications, rewards); `FcPostGameScreen` shows only that model; `FcPostGame` adapts Owner (stored season boxes, standings now), Career (the player's night against their season average, XP earned) and Dynasty. It changes nothing: no simulation, save, or pack/economy rule is touched.
- **The player of the game is a display pick**, not an award or a stat: weights are data in `data/ui/pog.json`, winners only, and the screen says so.
- **Box-score pass-through (D-049 executed):** `FcDynastyPlay.play_against` adds the simulation's own box (`to_dict()`), the user's side and the card map to its result, the tournament passes the user's match through `shown`, and the controller keeps it in `last_game`. In memory only; the profile and its saves are unchanged (a test proves the saved profile holds no box score). Career game entries also carry their `box` for display only.

## D-054 Audio: sounds the game builds itself (2026-11-20, UI polish Phase 11; D4 honoured)
- No third-party or unlicensed audio is added. `FcAudioSynth` builds every UI and effect sound from small recipes (tones, glides and noise) in `data/ui/audio.json`; an audio file named in the map (under `assets/audio/`, each listed with source and licence in `assets/audio/SOURCES.md`, enforced by a test) replaces the built sound only if it exists. Unknown ids, missing files and a muted game are silent, so the game is fully playable with the sound off. Music is not included (the Music bus exists and is empty).
- `FcAudio` is owned by `FcApp` (not an autoload) and fired through `FcAudio.cue("id")`, which does nothing when no audio is running (tests, tools). Buses: Master, UI, SFX, Music. Every button clicks (opt out with the `silent` meta), toasts, card flips, pack tears, rarity stings (one key, C major, climbing in five tiers), rewards and game results have cues. Volumes, one mute and a phone-vibration toggle live in `preferences.cfg` (`[audio]`, additive, no save-format change) and in a Sound panel in Settings.

## D-055 The Founding Series: the first playable Dynasty content release (2026-11-21, release validation milestone)
- The bundled fallback release (`data/content_starter`) is now the **Founding Series**: 40 original, invented players (names, home clubs and ratings are fictional), 46 cards (10 common, 10 uncommon, 10 rare, 11 epic, 5 legendary; six extra editions), five packs (a fixed 15-card starter collection and Rookie, Pro, Elite and Reward packs with published odds, guarantees and pity), 14 challenges across all seven categories, a market for common to rare cards, the "Founding Season" (four milestones, two objectives, two tournaments) and the starter configuration. A fresh install is therefore playable; a release published from Creator Studio still replaces it.
- It was built **through the real draft workspace, validator and publisher** (`tools/build_starter_content.gd`, data in `tools/dynasty_founding_content.gd`), never by hand-editing release files. Rebuild with `./tools/build_starter_content.ps1`.
- **Nothing about the economy or the pack mechanics changed**: prices, odds and rewards are content, set inside the existing rules. Rating spread: common 47-52, uncommon 56-60, rare 65-68, epic 67-76, legendary 81-85 (the game's own overall rating).
- The founder said the official Dynasty players would be supplied by them: these are a coherent starting pool so the mode can be played and tested now, and they can be replaced or extended from Creator Studio at any time. Names are invented but, like every generated name, need the lawyer review of CLAUDE.md rule 9.
- Existing tests that assumed the bundled release was too small now build an unplayable release on purpose.

## D-056 Android build preset and portrait lock (2026-11-21, release validation milestone)
- `export_presets.cfg` gained preset 1 "Android": arm64-v8a, prebuilt template (no Gradle), debug-signed, `display/window/handheld/orientation=portrait` (the Dynasty mobile layouts are designed for portrait), ETC2/ASTC texture import, an original app icon (`assets/icons/app_icon.svg`).
- **Placeholder package name `com.novaeris.fullcourt`: a founder decision** before any store build (it can never change after publishing), together with the release keystore. See docs/PLATFORM_BUILDS.md. Android is "builds, not device-tested" until docs/DEVICE_VALIDATION.md is completed on a physical phone; iOS is not started.

## D-057 Visual Identity and UI Transformation milestone (2026-11-21, founder-approved plan: docs/VISUAL_IDENTITY_PLAN.md)
- **Evolve, do not rebuild.** The D-047 design system (tokens, code-built Theme, kit, shell, cards, player identity, motion, audio, tests) stays; the milestone extends it, brands it and migrates the remaining screens onto it. Public contracts are kept.
- **Palette resolved by contrast tests:** the founder's proposed Court Orange `#FF8A24`, Championship Gold `#FFB547`, Electric Blue `#39A9FF` and Court Slate `#17233D` all pass 4.5:1 as text on every surface, so they replace `F58C29`, `FFC857`, `3DA5FF` and `18233D`; `SURFACE_HIGH #202F4D` is the new third surface step; `PRIMARY_DEEP #E65300` is the logo underline orange (glows and gradients, not text). Rating-tier colours follow.
- **Brand:** Full Court is the game logo, Novaeris is the studio logo. Transparent masters are keyed from the supplied banners by `tools/build_brand_assets.sh` (replace with the original layered files if they exist). Brand manifest: `data/ui/brand.json`; spec: `docs/ASSET_SPEC.md`; provenance: `assets/ART_PROVENANCE.md`.
- **Assets:** procedural-first (generated players, menu art); approved custom art for featured Dynasty cards through `art_path`; nothing unapproved or AI-generated ships.
- **Order:** A brand and spec, B design-system foundations and the FcTable prototype, C team identity, D brand/menu/navigation, E shared player presentation (ahead of Owner and Career), F Owner, G Career (display existing progression only), H Dynasty and Creator Studio restyle (previews, no editors), I animation/audio, J final QA. `app.gd` is split incrementally into `src/ui/menu|owner|career` with its public `show_*`/`on_*`/`build_tab` methods kept.
- **No save, controller, simulation or gameplay change.** New preferences are additive in `preferences.cfg`.
- **Cadence:** the founder asked for no hard stops: each checkpoint produces screenshots and a summary, anything uncertain is fixed with the best recommendation, and each milestone is committed and pushed to `Novaeris/full-court-godot`.

## D-058 Visual Identity milestone: what was changed in tests and ratchets, and what was left out (2026-11-21)
- **Existing tests changed because the screens changed, never to hide a failure:** the menu tests check the logo and cards instead of a text title and a table; the highlighted-save regression is kept for cards; the About test is a Credits test; tests that read a `Tree` on the Owner tabs read `FcTable` rows; a layout baseline for three screens grew in height (a table now has a real minimum height; the wizard's pickers are dropdowns); the style-lint exempts drawn art folders and its `app.gd` baseline fell from 80 to 68; the player-identity "different players look different" count includes the new proportions.
- **Additive only:** `FcGameController.finance_series()` (read-only, the user's books season by season), additive preferences (`show_splash`), new sound ids, `FcToast.Kind.ACHIEVEMENT`. No saved format, controller rule, simulation or economy number changed.
- **Player identity** gained hash-derived face proportions (not stored). A player's face therefore changed once, deliberately, with the golden fixture re-based; league players are not saved with a look, Career players keep their stored options.
- **Left out on purpose:** hand-made or generated raster art (procedural only, as agreed); a direction-aware screen slide (fade only); an Owner playoff bracket drawing (needs a new view of the season engine, not a restyle); achievements, trophy shelf and career timeline (the rules produce no achievement list); `FcSpinner`, `FcSelect` and `FcListPicker` wrappers (the themed controls are used, `FcDropdown` and `FcToggle` where they exist); localization itself (layout rules only, no translated strings).

## D-059 Player portrait and pack-opening visuals: APPROVED and IMPLEMENTED (2026-11-21)
Full write-up, measurements, pictures and recordings: `docs/PLAYER_VISUAL_PROPOSAL.md` (section 0 is the implementation record).
- **Direction (proposed):** high-fidelity procedural 2D as the default for every generated player; approved illustrated art through `art_path` for featured Dynasty players (provenance line in `assets/ART_PROVENANCE.md` first); stylised 3D rejected for now (cost and mobile risk), tier 3 (poses) and tier 4 (render) stay reserved.
- **Identity is untouched:** `FcPlayerVisual.resolve` and its golden fixture are unchanged. The extra detail is `FcPlayerTraits`, derived from the key by hash in a separate salt space and never stored; age is an optional presentation input. No new `FcPlayer` field, no `DATA_VERSION` change, no migration.
- **Now on:** `FcPlayerFigure.hd_enabled = true` (`FcPlayerFigureHd` is the production figure); the five-stage reveal is the default pack opening, with a Settings toggle "Cinematic pack opening (off: quick reveal)" (`FcPreferences.pack_reveal_style`). `FcPortraitBake` is the texture cache with a hard 20 MB budget (live HD draw is 4 to 9 times dearer than the old figure; baked it is one rectangle).
- **Modes:** Owner and Career use the procedural figure (stable per key, ageing, body from real height, weight and position). Dynasty keeps approved artwork through `art_path`; only a card with no readable artwork falls back to the stable procedural figure or the monogram, never a random identity. One renderer serves all three.
- **Pack opening integrity unchanged:** rolled, paid and saved before presentation; the reveal only reads the committed opening; skip equals watching (tested). Rarity looks are data (`data/ui/reveal_effects.json`); caps: 160 particles, 3 flashes per second.
- **Shipped fix made now (safe):** the reveal no longer fakes a mouse event; `FcCardFace.play_sweep()` and `set_glow()` are explicit.
- **Founder answers applied:** texture cache approved (20 MB); cinematic reveal is the default with Quick and skip; the legendary banner is the player's NAME with LEGENDARY as the supporting label. Player profile redesign is the NEXT milestone and was not started. No monetisation, odds, economy or content-format change.
- **Injury history (founder: injury and health matter only in Owner and Career):** `FcWorld.injury_history` is a new ADDITIVE saved section (older saves load as empty; no `DATA_VERSION` bump, the same pattern as staff and careers), written by the season engine; shown only in the Owner and Career dossier. Dynasty cards have no health.
- **Achievements (third of the founder's list):** derived, never stored (so no saved-format change), data-driven (`data/achievements/achievements.json`), three tiers, Owner and Career only; no gameplay reward is attached.
- **Relationships and Plays like (founder's order: relationships, similar players, achievements):** both are derived read-only from existing data, no saved-format change. Relationships are Owner and Career only; Plays like is in all three modes.
- **Profile dossier (follow-up, built on the founder's go-ahead):** `FcPlayerProfile` keeps its API and tabs and gains the dossier hero and Overview panels; only data the mode has is shown (no invented stats, achievements or contract for Dynasty cards). Items the game has no data for (relationships, similar players) are not built and are listed in `docs/PLAYER_VISUAL_PROPOSAL.md`.

## D-063 Career timeline and public image are stored on the profile (2026-11-22, Phase 4A)
- **Decision:** unlike franchise history (D-062), a career timeline and the public image are kept in the career profile: the numbers (fan favour, media image, hype, 0-100) are real state that changes sponsor pay, and a timeline row records a moment that cannot be re-derived later (an injury, a decision, a headline). Capped (300 rows, 12 headlines).
- **Save change:** `FcVersion.DATA_VERSION` 3 to 4; the migration gives each profile the starting image and a timeline built from its history and decisions.
- **Rules in data:** every threshold and weight is in `data/career/media.json`; a season is applied once (`public_year`).

## D-064 Dynasty ladder and collection goals (2026-11-22, Phase 5)
- **Decision:** the ranked ladder (rating, tiers, a fixed seed-made computer field for the rank) and collection goals are game-owned rules in `data/dynasty/*.json`, not published content, so no content kind, validator or feature flag changed. Goals describe cards by filters (rarity, position, team), so any release works.
- **Why local rank:** there is no server yet (D-065); the field makes the rank real and reproducible offline.
- **Save change:** `DYNASTY_DATA_VERSION` 2 to 3 (ladder) and 3 to 4 (claimed goals), each with a migration. Ladder money moves only through the ledger with request ids.
- **Not done:** new tournament formats and new published collection kinds (they need content and validator work the founder should shape).

## D-065 Online foundations are local; backend choice is the founder's (2026-11-22, Phase 6)
- **Decision:** built only the transport-agnostic server rules (`src/online/`) running in-process: signed requests, nonces, rate limits, idempotency keys, a command whitelist, rollback, signed receipts, rating matchmaking with server-issued seeds and server-decided matches checked by re-simulation. They reuse the offline Dynasty services, so the rules cannot drift.
- **Not decided (needs the founder, CLAUDE.md rule 7):** backend technology and hosting, sign-in provider, transport, and the first online feature set. A recommendation is in `docs/ONLINE_ARCHITECTURE.md` (a headless Godot server, Godot built-in networking, collection plus ranked head-to-head first, payments last and lawyer-reviewed).
- **No save change:** the server stores the existing Dynasty profile document.

## D-066 Online scope (founder, 2026-11-22; supersedes the "no online for Owner/Career" lines of D-029/D-030)
- **Decision:** Owner and Career stay fully playable offline and gain an optional online layer; Dynasty is online-first (the built offline Dynasty stays until online ships). PC hosts all online play; mobile is still Dynasty only.
- **Owner multiplayer:** one shared league, each person owns one team, invites, one host who simulates the whole league (host-authoritative, so a host can cheat in a friends' league; the server-authoritative rules of D-065 apply to Dynasty and ranked play).
- **Career online:** a person brings their created player into others' 5v5 and 3v3 games, still the text and box-score simulation; a visual presentation for players to watch is wanted later.
- **Backend (founder's choice of services):** Supabase (accounts, storage, realtime) and Resend (e-mail), plus a small Godot headless server for live matches (recommended, not yet approved). Transport WebSocket with TLS. No trading and no real-money purchases yet.
- **Build order:** accounts, then Owner multiplayer, then Career team play.
- **Nothing is built yet** beyond D-065; no network code until the accounts milestone starts.
- **Status note (2026-11-22, stabilization; append-only):** lines 351 and 353 were refined the same day by D-068: the Godot headless server is accepted for now, and the sign-in client and sign-in screen are built (unverified against a real Supabase project). Current wording: Supabase for accounts and storage; a Godot headless server authoritative for live matches; nothing provisioned, nothing deployed.

## D-067 Published sets and Studio tournaments (founder, 2026-11-22)
- **Sets:** a set is a named group of cards with its own packs. The Founding Series is the permanent base set. A set is permanent or timed (start and end). When a timed set ends its packs leave the store, cards already owned stay forever, and the founder may re-release it. A card belongs to exactly one set (a variation is a new card in a new set). Offline timing uses the device clock; online uses the server clock. Goals for an ended set keep what was earned but gain no new progress.
- **Tournaments:** made in Creator Studio, single-elimination brackets (4, 8, 16 or 32 entries).
- **Built (2026-11-22):** `set` content kind and `set_v1`, `tournament_v2` (size, window), `FcContentWindow`, catalog/pack/market checks, "early" placement, the bundled Founding Series base set (release id changed to `fcr_35b60b935eccd69e`, so the bundled release differs from older checkouts; saves only keep ids and are unaffected). No save-format change. Offline timing trusts the device clock; clock cheating offline is accepted by design. Goals do not yet filter by set. Guide: `docs/SETS_AND_TOURNAMENTS.md`.

## D-068 Online server, Career team play and Owner leagues (founder, 2026-11-22)
- **Server:** a headless Godot server for live matches is acceptable for now (hosting on a small rented VPS, roughly $5 to 15 a month). Supabase holds accounts and storage; the Godot server is the authority for games. The founder will decide again if load or cost changes.
- **Career online:** the person chooses 5v5 or 3v3 when they queue. Gameplay stays the text and box-score simulation with almost no extra control. Cosmetics (for example arm sleeves) are the planned extra; they change looks only and never ratings.
- **Owner leagues:** hosted live (the host's game is the league and simulates it; guests join as owners). Not an upload of a save.
- **Built:** the sign-in client (config, Supabase Auth request builders, sessions, HTTP executor). The service-role key is refused by the config guard because it must never ship in the game. No live server, lobby or sign-in screen yet.

## D-060 to D-062 (pointer, added 2026-11-22)
These were recorded in `PROGRESS_LOG.md` (2026-11-21) and are not repeated here: D-060 play-by-play and replay across all modes (events are compact integer rows written by an optional recorder that never touches the random generator; the simulation has no spatial model, so the court picture is illustrative; `DATA_VERSION` 2 to 3), D-061 Dynasty keeps its last 5 replays (`DYNASTY_DATA_VERSION` 1 to 2), D-062 see the log.

## D-069 Autonomous execution of the stabilization, authenticity and broadcast program (founder, 2026-11-22)
- **Decision:** the founder authorized independent execution of the master plan (revision 2.4): Stage 1 stabilization, Stage 2 authenticity audit, then the broadcast presentation milestones, each committed, pushed and checked on GitHub Actions. Routine decisions are made and recorded here instead of asked. Pushing to `main` is authorized for this program only (a standing rule remains: never force-push, never change remotes or visibility).
- **Product direction recorded:** a full 3D basketball broadcast with automatic, manual and hybrid cameras is the aim, **conditional on three feasibility prototypes** (reconstruction, a 3D performance prototype, a player-model prototype) passing pre-registered limits; D-059's concerns (cost, mobile risk) are answered by measurement. A permanent 2D fallback and a 2D completion path exist if 3D fails. Mobile stays 2D only (D-030).
- **Assets:** procedurally built, no purchases, no unlicensed assets. Save changes only under the safety conditions of the plan (backup, deterministic migration, golden comparison, no data loss).
- **Detail:** `docs/AUTONOMOUS_WORK_LOG.md` (the full plan is kept with the founder's session files).

## D-070 The 3D decision: 3D-REDUCED (Claude under D-069, 2026-11-22)
- **Evidence:** B1 reconstruction PASS (`docs/validation/B1_RECONSTRUCTION_SPIKE.md`), B1b rendering budget PASS on the development machine against limits committed first (`B1B_3D_PERFORMANCE_PROTOTYPE.md`, `PERFORMANCE_THRESHOLDS.md`), B1c player-model prototype PASS at broadcast and medium distance only (`B1C_PLAYER_MODEL_PROTOTYPE.md`).
- **Decision:** build the 3D viewer (B4) with a reduced scope: stylised code-built characters, broadcast, wide and medium cameras only, **no 3D close-up preset** (close-ups and introductions keep the 2D portrait cards over the picture), a permanent 2D fallback that preserves the replay state, and no mobile 3D (D-030). D-059's concerns are answered by measurement for desktop only.
- **Jersey numbers:** the stored franchise-tenure model (J1, a save migration) is **not** undertaken now. The 3D uniforms and lineup graphics use a pure, deterministic **display number per game** (the preferred hashed number, conflicts resolved by player id, retired numbers skipped), with no saved data. Limitation, kept open as audit finding S2-JER: display numbers are not records and can differ from the History tab's retired-number display; a roster change can shift a conflicting player's number between games.
- **If B4's own measurements fail** the pre-registered limits, the 2D completion path of the plan applies and this decision is revisited in a new entry.

## D-071 Broadcast pass 2: presentation modes, HUD and honest presentation data (Claude, 2026-11-23)
- **Decision:** extend, not rebuild, the B0-B8 broadcast programme (`docs/plans/BROADCAST_PASS2_PLAN.md`, milestones M1-M8). The replay screen gets three presentation modes (Broadcast, Replay, Analysis) over one shared `FcPlaybackState`, and a HUD level (Full, Minimal, Hidden; key H). Mode and HUD are remembered in `FcPreferences` (additive keys, no save-format change).
- **Close-up:** D-070 stands (no 3D camera closer than 28 ft). A "close-up" is a medium shot plus a 2D player-spotlight graphic.
- **Shot clock and stoppages:** presentation-only, derived from the reconstruction, labelled "reconstructed", hidden when unreliable (19.5% of reconstructed steps are compressed, see `B1_RECONSTRUCTION_SPIKE.md`). The simulator, event log and saves are not changed; no timeouts are invented.
- **Provenance:** presentation events will carry source, confidence and importance; nothing inferred is shown as simulation fact.
- **Camera direction (M3):** the director (`FcCameraDirector`) emits preset, angle (main, baseline, overhead, closeup), side (possession decides the baseline end), critical and reason; the rig (`FcCameraRig`) enforces a minimum shot time, interruption rules (only critical shots interrupt: free throws, celebrations, the final buzzer, instant replays), per-preset cooldowns, a limit of non-critical switches per ten seconds and a director style (calm, standard, energetic), all from `data/ui/broadcast_identity.json`. A direct jump by the person (scrub, feed click, Start/End, camera buttons) bypasses the rules; manual input suspends them and the director's return is never refused. After a rebound, steal or whistle the director whips instead of easing, because those reconstruction steps are clock-compressed. The 3D close-up is a medium shot at the 28 ft minimum (D-070 unchanged).
- **Replay v2 (M4):** one importance model (`FcImportanceModel`) scores plays for highlights, key-play ticks, the reel and bookmarks (weights plus context: three-pointer, clutch, close score late, last basket). A replay is an `FcReplayReference` (game key, event window, label, source user_bookmark, auto_highlight or key_play, importance): a pointer that re-runs the reconstruction over recorded events, never video, and every screen says "reconstructed". Bookmarks live in their own local file (`user://replay_bookmarks.json`, `FcBookmarkStore`, version 1, capped, never fails), apart from every save, so no world, career or dynasty save changed and `DATA_VERSION` is unchanged. Proven by tests: the reconstruction is byte-identical for the same events, and an instant-replay window maps back to the original event indices and never crosses a possession end.
- **Arena presentation (M5):** one `FcCourtScene` is dressed by an `FcArenaIdentity` (team colours and names from the game plus `data/ui/arena_identity.json`), never a scene per arena. The crowd is planned by loyalty (`FcCrowdPlan`: home, away block, neutral; sizes vary) and animated on the GPU (`crowd.gdshader`), reacting to cheers, big cheers (with a wave), groans and gasps; four rotating LED boards, benches with seated figures, four shadow-free spotlights and a glossier floor. Player introductions (`FcPlayerIntroductions`) use only the recorded starters and the lineup card's own display numbers. Frame time passes with a wide margin; the leak check is **not** a clean pass and is recorded as open (`docs/validation/M5_ARENA_PERFORMANCE.md`).
- **Audio and commentary (M6):** three more buses (Ambience, Commentary, Announcer) with their own volumes; looping arena ambience in three intensities that crossfade with `FcAmbienceModel` (a 0 to 1 crowd intensity from the recorded game: tight, late, clutch, runs, whistles); original synthesised music pads (off by default, Broadcast mode only; D4 stands: nothing unlicensed); ducking (`FcDuckingModel`) of Crowd, Ambience and Music while a VOICE speaks. Commentary is structured data: `FcCommentaryEvents` (roles play_by_play, color, narrative, announcer, each a producer over recorded facts with provenance), `FcCommentaryArbiter` (one voice, rank and priority, preemption, cooldowns, no repeats; minor plays are caption-only) and `FcCommentarySink` (captions now; recorded voice, TTS and AI are the same interface, none implemented, none required, no network). Captions never duck anything; only a sink with a voice does. Minor play-by-play (misses, rebounds, turnovers) stays a caption but is never voiced, so the analyst and narrator have room.
- **Broadcast production (M7):** pregame, halftime, postgame, the championship presentation and the weekly show **Full Court Tonight** are template data (`data/broadcast/templates/*.json`, `FcProductionTemplate`: an ordered list of segment types with lengths) over two pure builders: `FcProductionPlan` (one game, from the recorded timeline) and `FcWeeklyRecap` (the league, from saved results). A segment is a view model drawn by one `FcProductionPanel`; the replay screen and the Owner News tab share it. Every line is recorded or saved data and the tests recompute the numbers (box scores for game shows, raw results and `FcStandings` for the week). Honest limits stated on screen: the season keeps full box scores only for the team the owner follows, so the player segments of Full Court Tonight use those games; "player of the game" is points + rebounds + assists + steals + blocks; an upset is a record at least .200 worse beating the better one. The championship presentation appears only for the last game of a completed final series. No save-format change: the shows read and never write.
- **Replay references:** bookmarks and highlight packages are references that re-run the reconstruction, never recorded video.

## D-072 3D visual fidelity and basketball authenticity overhaul (Claude, 2026-11-23)
- **Scope:** the 3D broadcast view only (`src/ui/broadcast3d/`). Simulation, saves, data versions, Creator Studio data, the 2D replay and mobile are untouched. D-070 stands in full: the 3D camera is never closer than 28 ft to what it looks at, and a phone never shows 3D.
- **Character pipeline decision:** characters are generated as skinned meshes from code (a parametric body kit), not imported models. Blender is not available on the development machine and a hand-modelled GLB cannot vary for every generated player. One 16-bone `Skeleton3D`; one smooth lofted `ArrayMesh` per player (torso, limbs, hands with fingers, a parametric head with eyes, nose, brow, mouth and ears, eight hair styles, facial hair, a jersey, shorts, socks, shoes, optional headband); proportions from a pure `FcBodyArchetype` (height, mass, muscle, wingspan, shoulders, head size, hands, feet, the 2D face proportions) derived only from the identity, height, weight, position and key, so nothing new is stored and Creator Studio and saves are unaffected. Bone and surface names are stable so authored GLB parts can replace generated ones later. glTF and Blender were evaluated and not adopted.
- **Animation decision:** keep the pure-maths pose library (deterministic, unit-tested, no authored clips needed) and extend it to 34 states (29 at the end of the overhaul; the pipeline work added a left-hand dribble, pass, catch and screen) with anatomical conventions, ground contact (feet stay on the floor unless a state is airborne), a pure two-bone IK solver that puts both hands on the ball in shots, dunks and rebounds, stride speed matched to travel speed, and event-to-action rules that only READ an already-recorded event. An `AnimationTree` was not adopted (it needs authored clips).
- **Ball, court, hoop, arena:** a real-size (0.39 ft radius) pebbled ball by shader with dribble bounce, arcs, spin, a drop through the net and a rim bounce; a hardwood floor and all its markings computed in a shader in court feet at real dimensions; a hoop with the real proportions, a swinging net; a crowd still on one MultiMesh but drawn as people with arms-up cheers; team-coloured seating, banners, an LED ribbon, a truss, a scorer's table, courtside seats, seated bench players, referees and coaches.
- **Broadcast:** a lower main camera, a three-quarter front close shot (still 28 ft or more), introductions that wave and spotlight, celebrations by the scorer's team.
- **Found and fixed on the way:** characters advanced twice per frame since B4 (Godot re-enables `_process` on tree entry); an inside-out first mesh (Godot's front face is clockwise); left and right had been swapped in the prototype.
- **Evidence and limits:** `docs/validation/3d_overhaul/` (a document, screenshots and benchmark numbers for every milestone, and `README.md` with the final verdict). All performance numbers are from the one development machine; nothing was measured on lower-end hardware.

## D-073 AI-assisted development ecosystem (Claude, 2026-11-24)
- **Decision:** adopt free, open-source, pinned and reviewable tools only: the Godot MCP server (Coding-Solo 0.1.1, MIT), Blender 4.5 LTS portable (GPL) with the Blender MCP (mcp-for-blender 2.3.1, MIT), project skills in `.claude/skills/`, and in-house validation, audio and pipeline scripts. Declared in `.mcp.json` (no credentials), installed by `tools/blender/install_blender.ps1` (SHA-256 verified), verified by `tools/mcp/probe_mcp.py`.
- **Not adopted, with reasons:** Meshy and Tripo (paid, attribution or licence terms to read per file, no standard rig), ElevenLabs (paid commercial licence, API key, synthetic-voice decision), Mixamo (manual Adobe account, redistribution limits; documented as an optional motion source), third-party Godot skill packs and GDAI/godot-ai (redundant, unreviewed, plugin), Audacity (ffmpeg scripts cover the need).
- **Interchange and pipeline:** GLB (glTF 2.0) is the standard; Blender is the production tool, run headless by scripts; one rig standard (`data/player_pipeline/rig_standard.json`, generated from the game's skeleton) is enforced by `FcPlayerModelValidator` and `FcAnimationClipValidator`; imported rigs are driven by the existing pose maths through `FcRigRetarget`. The generated body stays the default look; a GLB is opt-in. Clips are read by `GLTFDocument` and stored as a native library because the editor's animation optimizer is lossy.
- **QA:** `tools/validate_project.gd` (also in CI), a CI workflow that rebuilds the Blender player and clips on a clean machine, an audio data validator, a 3D budget guard.
- **Costs and consents:** nothing was spent and no account, key or licence beyond free open-source software was accepted. Anything paid or account-based stays a founder decision (listed in AI_DEVELOPMENT_TOOLKIT.md).
- **Evidence:** `docs/development/`, `docs/validation/player_pipeline/`.

## D-074 Production Phase M1: professional player visuals (Claude, 2026-11-24)
- **Goal:** replace the mannequin look of the 3D players with a Blender-built, customisable, production-quality character, without touching identity data, saves or the animation system.
- **Kept:** `FcPlayerVisual.resolve()` as the only identity source, rig standard v1, GLB, `FcPlayerModelValidator`, the generated body as fallback and default. **Added:** `docs/development/PLAYER_VISUAL_SPEC.md` (art direction and rubric), `FcPlayerAssetLibrary` (registry and cache), `tools/blender/fc_character/` (reusable) and `tools/blender/basketball/` (specific), optional `x_` finger bones, shader-driven numbers and wordmarks, `FcPlayerRender` for portraits.
- **Promotion rule:** the new model stays opt-in until the founder approves the art direction; milestone M1.8 stops before changing the default.
- **Evidence:** `docs/validation/player_m1/`.
- **Built (2026-11-24):** M1.0 to M1.7 (`docs/validation/player_m1/`): a Blender production kit (`tools/blender/fc_character/`, `tools/blender/basketball/`, `build_player_m1.py`), three body types with fingers (20 `x_` bones, rig standard v1 kept), 18 swappable heads x nose, lips, brow, eye variants, seven hair styles, facial hair, headband, a jersey with armholes, scoop neckline and trim, shorts, socks and shoes; `FcPlayerAssetLibrary` (registry, cache, shared materials, `data/player_pipeline/asset_library.json`), `FcHandPoses` (relaxed, open, ball grip, shooting, dribbling, catching), `FcJerseyGraphics` plus `jersey_cloth.gdshader` (number, surname and wordmark as a texture, no per-number geometry), `FcPlayerRender` (portraits rendered from the 3D player, cached, off by default), validator vocabulary for parts. Measured cost and limits: `docs/validation/player_m1/perf/`.
- **M1.8 not taken:** the new players are NOT the default. The founder must approve the art direction (`FcBroadcast3DView.player_model` default is unchanged, `FcPlayerRender.enabled` is false). Until then they are opt-in with `model = "library"`.
- **M1.8 (2026-11-24):** final review done (`docs/validation/player_m1/M1_REPORT.md`). Promotion is ONE reviewed data flag, `"promoted"` in `data/player_pipeline/asset_library.json` (false): it switches the replay default (`FcBroadcast3DView.effective_model()`) and 3D-rendered portraits (`FcPlayerRender.enabled`) together. It stays false until the founder approves the art direction.

## D-075 Player visual system V2 on a MakeHuman CC0 base (founder, 2026-11-24)
- **Why:** the founder rejected the M1 look ("too primitive"). Script-built shapes cannot reach professional anatomy, faces or hands.
- **Decision (founder approved the foundation):** build V2 on the MakeHuman base mesh and targets (CC0) generated headlessly by the MPFB 2.0.18 add-on (GPL, build tool only, never shipped), using only CC0 asset packs. Installed by `tools/blender/install_mpfb.ps1` with pinned checksums into the user profile. Every shipped derivative is listed in `assets/ART_PROVENANCE.md`.
- **Architecture:** one base character per level of detail with named body and face morph targets, a converted `game_engine` rig (the 16 standard bones plus `x_` extensions), garments and equipment fitted in Blender with the same morphs, morphs baked once per player in Godot. Assessment and sequence: `docs/development/PLAYER_V2_ASSESSMENT.md`.
- **Unchanged:** identity data and saves, `FcPlayerVisual.resolve()`, the 34 animation states and the retarget layer, the promotion rule (V2 becomes the default only with founder approval).
