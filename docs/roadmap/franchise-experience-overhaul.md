# Franchise Experience Overhaul (D-077)

The programme that turns Owner Mode (and Career where it fits) from a menu-driven management app into an immersive franchise simulation: a franchise HQ, a season calendar you play from, one authoritative simulation clock, a Game Center, daily reports, the Full Court Network, upgraded management screens, broadcast links, event presentations and franchise legacy.

- **Started:** 2026-11-26, at the founder's request. The founder asked for the work to run without questions, with each milestone tested, documented, committed and pushed.
- **Related documents:**
  - Design of time and integrity: [season-calendar-system.md](../architecture/season-calendar-system.md)
  - Screens and components: [presentation-system.md](../architecture/presentation-system.md)
  - Evidence: [franchise-experience-validation.md](../validation/franchise-experience-validation.md)
  - Decision record: D-077 in [DECISIONS.md](../DECISIONS.md)
- **How to resume after an interruption:** find the first milestone in the tracker (bottom of this file) that is not **Done**, read its acceptance criteria, then continue.

## 1. Audit: what exists today (checked in the code on 2026-11-26)

### Simulation, season and time
| Area | What exists | Where |
|---|---|---|
| Dated calendar | `FcSeason.start_date` (Oct 20) plus each game's `day` offset gives a real date. `date_of_day`, `games_on_day`, `total_days`. An 80-game season spans about 160 days. | `src/data/season/season.gd`, `scheduled_game.gd`, `src/data/common/date.gd` |
| Schedule | `FcScheduleBuilder.build`: one game per team per day, even pacing, limited back-to-backs and home or away runs. Seeded. | `src/league/schedule_builder.gd`, `matchup_planner.gd` |
| Advancing | `FcSeasonEngine.play_day` plays every game on `next_day`, then increments it. The `played` flag plus a cursor that only moves forward mean no game is played twice. Playoff days are added as needed (`play_playoff_day`). | `src/league/season_engine.gd` |
| Controller time API | `advance_day`, `advance_days`, `sim_regular_season`, `sim_playoffs`, `begin_offseason`, `start_next_season`, `phase()`, `next_user_game`, `days_to_next_user_game` | `src/game/game_controller.gd` |
| Phases | `FcSeason.status` (pending, regular, playoffs, complete) plus `FcGameState.offseason_stage` (0 normal, 1 free-agency window, 2 draft, 3 meeting, 4 expansion) | `season.gd`, `game_state.gd` |
| Playoffs | Builder, series, bracket rules from data | `src/league/playoff_builder.gd`, `src/data/season/playoffs.gd` |
| Awards | MVP, stat leaders, All-League 1st to 3rd teams, Finals MVP | `FcSeasonEngine.compute_awards` |
| Offseason | Archive, economy, progression and retirement, contract expiry, re-signing, the draft (the lottery runs silently inside `prepare_draft`), AI-to-AI trades, free agency, roster fill, staff rollover | `src/league/offseason.gd`, `draft_lottery.gd`, `trades.gd` |
| Injuries | Counted in games, not days, with history and medical effects | `_apply_injuries`, `FcWorld.injury_history` |
| News | `FcWorld.news`, capped at 300, with date, kind, text and team; about 30 places add to it. `FcStorylines`, `FcRivalries`, `FcRecords` and `FcFranchiseHistory` are computed each time they are needed. | `src/data/world/world.gd`, `src/league/*` |
| Weekly show | "Full Court Tonight" (`FcWeeklyRecap`, `FcTonight`), Owner only | `src/ui/production/` |
| Box scores | Full box score plus play-by-play for the watched team's last 20 games (`RECENT_BOX_LIMIT`). Every other game keeps only its score. | `FcSeason.recent_boxes` |
| Career stats | `FcWorld.careers`: one row per player per season, kept forever | `world.gd` |
| Saves | Atomic: written to `.tmp`, verified, renamed, with `.bak` kept. Checksums. `DATA_VERSION = 4` with a chain of migration steps. | `src/save/save_manager.gd`, `save_migrator.gd`, `src/core/version.gd` |

### Business and management
- **Finances.** `FcFinanceRecord` keeps 9 revenue and 12 expense keys plus attendance, valuation and cash for each team and season. `FcTeamBusiness` holds the owner's levers. The engine is `FcFinanceEngine`.
- **Contracts and cap.** `FcCapRules` (soft or hard caps, taxes, exceptions, holds, rookie scale) and `FcPlayerMarket` (asking price, offers).
- **Trades.**
  - `FcTrades` handles AI-to-AI trades, in the offseason only.
  - `FcTradeDesk` handles the user's proposals, with negotiation.
  - `FcTradeOffers` makes AI offers to the user.
- **Draft.** Lottery, scouting with noise, workouts, 2 rounds, and pick ownership.
- **Staff and meetings.**
  - Staff: hiring, firing and extensions, plus chemistry.
  - Owners' meeting: 8 rule families, expansion and relocation.
- **Owner standing.** Reputation and an approval report, job offers, and moving to another team.
  - There are **no explicit objectives**.

### Presentation
- **Design system.** `FcUiTokens` and `FcUiTheme` (Hardwood Night) and 38 kit components:
  - tables, sparkline, stacked bar, radar, stat bars, bracket, KPI strip, modal, toasts, celebration, score bug, lower third, letterhead
  - the shell (`FcScreenHost`, `FcNavigator`, which has no screen registry)
  - a style lint that only lets literal-colour and font-size counts go down
- **Owner Mode is one screen with 13 tabs.** Overview, Standings, Schedule, Roster and History live in `src/ui/owner/`. Trades, Draft, Market, Finances, Staff, Meeting, News and League are built inline in `src/ui/app.gd` (2,687 lines).
- **Players.**
  - One look resolver (`FcPlayerVisual`).
  - Portraits, chips and tiles.
  - The dossier modal: radar, development track, contract, health, relationships, and stats and history tables.
- **Games.** Each of these opens as a modal:
  - `FcGameDay`, the pregame screen
  - `FcPostGame`
  - `FcReplay` and `FcReplayScreen`: scorebug, 2D or 3D court, commentary, play-by-play, broadcast productions
- **Teams.** `FcTeamLook` and `FcTeamCrest`, procedural with no image files.
- **Audio.** `FcAudio` with synth recipes (UI, cards, results, court, arena, music recipes) on 8 buses. The Settings screen has volume sliders.
- **Tooling.** Screenshot tooling (`tools/screenshot.gd`, `screenshot_matrix.ps1`) and a viewport audit.

### Modes
- **Owner:** uses everything above.
- **Career:** wraps the same `FcGameController` (`FcCareerController`) and has no separate season loop. XP is paid once per game through `_box_key`.
- **Dynasty:** an offline card game (packs, collection, lineup, ladder, tournaments). **It has no league, season or calendar**, so the calendar and season features of this programme do not apply to it.

### Creator Studio
- One screen for drafting, validating, approving and publishing content packs through the shared `src/content` code.
- No editors and no save inspection.

## 2. Gaps, technical debt and visual weaknesses
- **Time:**
  - no calendar events, sim-to-date, "advance to event", daily reports or saved history of past days
  - the offseason jumps to Jul 1 without walking through dates
  - no preseason, All-Star or trade deadline
  - the lottery is not shown as an event
- **Integrity:**
  - games have no stable ID
  - no ledger of processed events or transactions
  - no audit trail and no integrity checker
  - no structured transaction log (transactions exist only as news text)
- **Data for presentation:**
  - no shot locations (only rim, mid or three)
  - no box score or compact line for games without the user's team
  - no rating history
  - no jersey number on `FcPlayer` (only the Career profile has one)
  - no weekly or monthly awards, and no ROY, DPOY, 6MOY, MIP or COY
- **League activity:** AI teams never trade or sign players during the season.
- **UI debt:**
  - `app.gd` holds 8 inline tabs
  - routing is a TabContainer
  - games, replays and profiles open only as modals
  - the Owner post-game replay calls `FcReplay.build` instead of `FcReplay.for_owner`, so it has no crests or title context
- **Visual weaknesses** (before pictures: `docs/validation/franchise/before/`):
  - Finances, Staff, Market, Trades, Meeting, News and League are tables and SpinBox rows with long sentences
  - the Overview is a stack of panels with no hero composition
  - the schedule is a plain list
  - no calendar, no trade-machine visuals, no draft night
  - no charts over time apart from one sparkline
- **Performance notes:**
  - about 13 s to simulate a 30-team season plus playoffs headless, about 0.1 s per sim day
  - the 3D replay leaks 6 to 24 MB over 10 open and close cycles, against a 10 MB limit (`RELEASE_READINESS.md`)

## 3. Decisions (summary; the reasons are in D-077)
| Key | Decision |
|---|---|
| A | One clock: `FcSeasonClock.advance_until(target, prefs)` loops over a single `_process_day()`. The 9 targets are stop conditions. The speeds Normal, Fast and Instant change only the presentation. |
| B | Integrity: each day's random numbers are forked from the seed and that day only, so the same seed gives the same result whichever speed or grouping is used. `FcSimLedger` holds the keys of everything already processed. Saves happen at day boundaries only, using the existing atomic save. A `sim_audit` row is kept per day, and `FcSimIntegrity.check` verifies the state. |
| C1 | Each milestone that changes the saved format adds one migration step. Steps that have been pushed are frozen. v5 comes with M2 (data foundation), v6 with M9 (lifecycle). |
| C2 | Game IDs come from `FcIdGenerator.next_id("game")` when the schedule is built and when playoff games are created. The migration backfills them in (season, day, index) order. |
| C3 | Owner objectives are set at season start, stored per season and fixed for it, and evaluated at season end into the owner history and reputation. |
| C4 | The offseason has real dates from `data/rules/calendar.json`. `offseason_stage` stays the state machine. Days without games move the date. |
| C5 | All-Star is a real simulated game stored in `season.all_star`. It is left out of standings, season stats, careers, records and milestones. |
| C6 | Every game in the current and last season keeps a compact line. Game logs are kept for the user's team and the Career player. Full box scores are kept for the last 20 user games plus up to 20 followed games. A 50-season save may be at most 1.5x today's size. |
| C7 | `FcPlayer.jersey_number`, kept unique per roster by `FcJerseyNumbers` (retired numbers are skipped; a player keeps their previous number when possible). |
| D | `FcGameAvailability` decides which game actions a screen may offer. A screen never offers an action the stored data cannot support. |
| E | AI-to-AI trades in a window before the deadline. AI teams sign injury cover during the season. Each move is a transaction with an ID and a news link. |
| F | Weekly and monthly player awards come from differences between stats snapshots. MVP and ROY races, power rankings, a playoff race with magic numbers, and milestones, all from real stats. |
| G | Screens get a registry and back stack. New kit components. A composition rule: one hero area, a main data area and a context rail. Screenshots are taken at 1280x720 and 1920x1080 and reviewed by eye. |
| H | The calendar is the home of the season loop (month, week and day views, team and league, filters, scoreboard, date panel, events rail, sim progress, sim settings). |
| I | Owner: everything. Career: the clock, calendar, reports, Game Center, Network and profile. Dynasty: shared visuals, result cards and audio only. |
| J | Audio stays synth recipes. The HQ backdrop is layered 2D. A walk-around 3D HQ is not built, because the complexity is too high for what it would add. |
| K | Studio becomes an admin centre: data editors that go through the content pipeline, plus a read-only save inspector. Live editing of saves is not built because it would bypass migrations and integrity checks. |

## 4. Game data availability (decision D)
| Game | Broadcast / replay | Full box score | Play-by-play | Compact line | Preview |
|---|---|---|---|---|---|
| User team, upcoming | "Watch live" plays it with recording, then opens the broadcast | after | after | after | yes |
| User team, played, in its last 20 | yes | yes | yes | yes | – |
| User team, played, older (this or last season) | – | – | – | yes | – |
| Other teams, upcoming | "Follow" records it | after, if followed | after, if followed | after | yes |
| Other teams, played (this or last season) | if followed | if followed | if followed | yes | – |
| All-Star game | yes | yes | yes | yes | yes |
| Archived seasons | – | – | – | final score | – |
| Career player's team | same as the user team | | | | |

## 5. Milestones and acceptance criteria
Every milestone must pass all of these before it is committed:
- the import
- the unit tests
- the live tests
- `validate_project` (exit 0)
- the Creator Studio smoke test
- the style-lint and layout ratchets
- any new fixed-seed tests

After any simulation change, `tools/simulate_games.ps1` must also keep all 16 checks in range.

| # | Deliverable | Acceptance criteria |
|---|---|---|
| M0 | Audit, plan, architecture and validation docs, before pictures | This document. The architecture and validation skeletons. D-077 recorded. Stale lines in ARCHITECTURE and OWNER_PRESENTATION_AUDIT fixed. Before pictures at 1280x720 and 1920x1080. |
| M1 | Design system | New kit components, each in the gallery with a test. Navigator registry and back stack. Screen and tab transitions (respecting reduced motion). Layered backdrops. The 8 inline tabs moved out of `app.gd` with no change in behaviour (live and click tests pass). The `app.gd` lint baseline goes down. |
| M2 | Data foundation, save v5 | Game IDs. Jersey numbers (unique). Rating snapshots. Compact lines for every game. Shot spots (simulation results identical for the same seed, otherwise zone charts). Transaction log. Day log. Ledger. Audit. `FcSimIntegrity`. Owner objectives. Sim preferences. Followed games. `FcGameAvailability`. A v4 fixture migrates. The 50-season size test passes. |
| M3 | Franchise HQ | Hero team header with date, phase and record. Performance panel. Featured matchup that opens the Game Center. Spotlight and leaders. Headlines. Management summary with objectives. Advance bar. Everything reads from the controller (tested). Pictures reviewed. |
| M4 | Player presentation | Switch between roster table and card gallery. Detailed cards. Full-page profile with rating history, game log, shot chart, tendencies, contract timeline and honours. Every value comes from real data (tested). |
| M5 | Schedule and Game Center | Schedule visuals. Game Center actions follow decision D (tested). Post-game screen with standings effect and news. The `for_owner` replay fix. |
| M6 | Calendar UI | Everything in decision H except the sim controls. Games on the correct dates and with the correct home team (tested against the schedule). Future dates show no results (tested). Filters and navigation tested. |
| M7 | Clock and sim controls | All 9 targets. 3 speeds. Pause rules. Sim Settings. Progress and cancel. Interruption tests (a) to (e) pass. Every game played exactly once. Same hashes across speeds. Owner and Career go through the clock. |
| M8 | Daily reports and league activity | Daily and multi-day reports built only from the ledger. Past days can be revisited. AI trades and signings during the season. Weekly and monthly awards, races, power rankings, magic numbers, milestones. |
| M9 | Season lifecycle, save v6 | Preseason (camp, cuts). All-Star. Trade deadline. Lottery event. Offseason dates. Expanded awards. Two full seasons through the clock with integrity checks every day and saves at every phase. |
| M10 | Event presentations | Lottery reveal, draft night, free agency, All-Star weekend, awards show, playoff bracket and race, championship celebration. |
| M11 | Management screens | Finances, staff, draft board, market, trade machine, standings, League Stat Center, meetings. All redesigned and reading from the controller. |
| M12 | Full Court Network | `FcNetworkFeed` with importance tiers, built from real events and with no repeated templates (tested). Network screen. Expanded Full Court Tonight. |
| M13 | Broadcast and arena | Full-screen replay from every entry point. Intros and broadcast graphics. Arena team colours and banners. Memory leak fixed or measured. |
| M14 | Audio and animation | Music and cue recipes. Card, count-up and result animations. Reduced motion and volume settings respected. Frame times measured. |
| M15 | Legacy and Studio | Legacy screen. Historical league records. HQ banners. Studio admin centre (editors and save inspector). |
| M16 | Integration and regression | Career wired in. Dynasty shared visuals. Full suites. Multi-season stress test through the clock. Save tests. After pictures. FEATURE_MATRIX and TESTING updated. |

## 6. Risks
| Risk | Mitigation |
|---|---|
| Moving the tabs out of `app.gd` breaks behaviour | Live tests, click tests, and one tab at a time |
| Saves grow | Archiving drops detail after 2 seasons, and a 50-season size test |
| Shot spots change simulation results | Draw them from a separate forked RNG stream, then check results are identical; otherwise fall back to zone charts |
| Changing to a per-day RNG changes how seeded results look | Deterministic by design. Tests that pinned old results are updated in the same change and the reason recorded. |
| Scope | Milestones may be split. The tracker states limits honestly. |

## 7. Progress tracker
| Milestone | Status | Summary | Tests | Pictures | Known issues | Commit |
|---|---|---|---|---|---|---|
| M0 | Done | Audit, plan (decisions A-K), architecture and validation docs, D-077, stale doc lines fixed, before pictures rendered from a clean worktree of `37d86a9` (19 screens x 2 sizes, 30 days into a season) | docs only (no code) | `validation/franchise/before/` | – | see git log (M0 commit) |
| M1 | Done | 12 kit components plus `FcShotZones`, navigator registry and back stack, push/pop slides, franchise backdrop, 8 inline Owner tabs moved to `src/ui/owner/` (app.gd 2,687 to about 1,770 lines; sized labels 68 to 30) | unit 1,756/0, live 241/0, validate 0 problems, Studio PASS | `validation/franchise/m1/` | gallery count tests updated (16 sections) | see git log (M1 commit) |
| M2 | Done | Save data version 5: game ids, compact result lines, day logs with standings checksums, game logs, starts and rim shots, followed games, transaction log, rating history, stored jersey numbers (`FcRosterNumbers`), owner objectives judged into reputation, sim preferences, ledger, `FcSimIntegrity`, `FcGameAvailability`; v4 to v5 migration tested on a real v4 save | unit 1,771/0, live 241/0, validate 0, Studio PASS; simulate_games 400 games identical to M1 (16/16 in range); 50-season save 6.1 MB (was 5.2, limit 1.5x) | – | Shot charts use the three simulated shot kinds; exact spots are not simulated (documented) | see git log (M2 commit) |
| M3 | Done | Franchise HQ: team header hero with record pills, featured matchup banner (opens the game), standing (KPIs, last 10, playoff position from the real builder), team leaders, last game with player of the game, league ranks, headline cards, objectives with progress, business (payroll vs tax line, cash, debt, staff); `FcFranchiseSnapshot` | unit 1,774/0, live 241/0, validate 0, Studio PASS | `validation/franchise/m3/` | layout baseline owner_overview 194 to 231 px (header) | see git log (M3 commit) |
| M4 | Done | Roster Table / Cards switch (cards: number, rating, potential, season line, injury; actions follow the selected card); full-page profile route (Back via the stack); profile gains Game Log, Shooting (three simulated shot kinds vs league), Tendencies tabs, rating-history chart, contract bar, stored jersey number; preferred numbers spread realistically, retired numbers use the worn number | unit 1,780/0, live 241/0, validate 0, Studio PASS | `validation/franchise/m4/` | – | see git log (M4 commit) |
| M5 | Not started | | | | | |
| M6 | Not started | | | | | |
| M7 | Not started | | | | | |
| M8 | Not started | | | | | |
| M9 | Not started | | | | | |
| M10 | Not started | | | | | |
| M11 | Not started | | | | | |
| M12 | Not started | | | | | |
| M13 | Not started | | | | | |
| M14 | Not started | | | | | |
| M15 | Not started | | | | | |
| M16 | Not started | | | | | |
