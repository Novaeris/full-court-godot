# Roadmap

Dependency-driven, continuous development (not an MVP schedule). Always keep the game testable.

**What is built right now is in [FEATURE_MATRIX.md](FEATURE_MATRIX.md); current test totals are in [TESTING.md](TESTING.md). This file is the order of work and its history.** Counts in parentheses below are the totals at the time each item was finished.

## Completed
- Git repo + .gitignore
- Godot 4.7.2 project (`project.godot`)
- Core: `FcRng`, `FcIdGenerator` (tested)
- Headless test runner + `tools/run_tests.ps1`
- Project docs
- Foundation approved by founder
- Data model: data-driven attribute system, Player (+ parts), Team (+ roster/city/arena), Contract (years/options/bonuses), repositories, FcWorld with integrity validation (58 tests)

- Save system: FcGameState root, slots, autosave slot, checksummed files, atomic write with backup, corruption recovery, version migrator (81 tests total)

- Staff: FcStaffMember (GM, coaches, scouts, medical, business), roles, staff contracts, data-driven skills and philosophy, world rules (100 tests total)

- Procedural generation: names, players, staff, cities, arenas, teams, rosters, contracts, free agents from a seed (129 tests total)
- Real-world city database (154 cities, 7 areas) and customizable leagues: size, areas/exact cities, conferences/divisions (159 tests total)
- League rules: equal-division structure limits (4-64 teams), season schedule rules with fair home/away matchup planner, playoff formats, soft cap with hard limit (plus hard cap and no cap presets), team naming options, sensitive places (198 tests total)
- 80-game standard season (even season lengths for every size) and extra salary rules: tax sharing, repeater tax, restriction line, rookie scale, cornerstone extension, cap holds, sign-and-trade limits, no-trade clauses (218 tests total)

- Basketball simulation v1: possession engine, rotations, fatigue, coach effects, box scores and advanced stats, calibrated stress tool; recalibrated to the 2010-2020 NBA with three era presets and realistic scoring leaders (248 tests)
- Season engine: dated calendar, standings with tiebreakers, playoffs (division leaders or seeding, conference or league brackets, byes, home court), champion, awards, player season statistics, league balance tuning (280 tests)
- Offseason: player progression and retirement, contract expiry, AI re-signing, 2-round draft with rookie scale, free agency under the salary rules, legal rosters; three seasons verified (299 tests)
- Owner Mode business engine: demand and pricing, 8 revenue and 9 expense lines, fan interest, brand, debt, valuation, owner levers (price, marketing, facilities), AI teams run automatically (313 tests)
- Staff rollover (aging, renewals, vacancy hiring), game controller API for screens and Owner Mode decisions, saves that continue identically (325 tests)
- First UI shell: main menu, new league wizard, team choice, dashboard with seven tabs, owner controls; README with how to play (337 tests)
- Injuries (in-game, tracked across the season, lineups adapt, severe injuries have lasting effects) (347 tests)
- News feed and box score viewer (354 tests)
- Medical staff effects and AI trades (363 tests)
- Career statistics and archiving of old seasons (370 tests)
- Owner Mode depth, long-run economy and stability checks (see `docs/PROGRESS_LOG.md` and `docs/STABILITY_REPORT.md`)
- Career Mode phases 1-6 (D-038 to D-040): build validation and creator, progression, season simulation, RPG layer (decisions, contracts, relationships, rivalries, sponsorships), potential-capped player-directed growth, scouting and draft pick; marked playable (710 tests at the 2026-11-19 stabilization run)
- Content publishing (D-042, 758 tests): Creator Studio to game releases, local and offline: manifest and checksums, approval-gated publisher, immutable releases with crash-safe pointer, loader with visible fallback and rollback, bundled starter release. Remote hosting is not built.

- Dynasty Mode, offline (D-043 to D-046, D-055): profile and economy, packs, collection, lineup and games, challenges, season and tournaments, the bundled Founding Series release, screens and mobile layouts checked in a phone-sized window (`docs/DYNASTY_MODE_PLAN.md`, `docs/DYNASTY_FOUNDING_REPORT.md`).
- Release validation (2026-11-21): screen matrix, release fixes, Windows export and packaged self-test (`docs/RELEASE_READINESS.md`).
- Phase 1, ecosystem integration and documentation reconciliation (2026-11-21): `docs/INTEGRATION_AUDIT.md`, `docs/FEATURE_MATRIX.md`, cross-mode tests.
- Visual Identity and UI Transformation (D-057, D-058): brand, main menu, team identity, shared player presentation, Owner and Career redesign, Dynasty bracket, Creator Studio restyle, celebration and sound (`docs/VISUAL_IDENTITY_PLAN.md`, checkpoint notes in `docs/validation/ui/visual_identity/`).

## Current
- Owner Mode depth (see `docs/PROGRESS_LOG.md`). `docs/MILESTONE_PLAN.md` is a historical draft (v3); the founder's phase list under "Next phases" below is the current order of work, and the older "Next (proposed order)" list is history.
- Stabilization (2026-11-19): fix doc and contract inconsistencies, run the full validation set, then founder manual playtesting, a visual and usability pass on the Owner and Career screens, and a rules freeze before the next major track.

## Next (proposed order, driven by dependencies)
1. (done) Staff entities. 2. (done) Save system. 3. (done) Procedural generation of the league.
   Done since: the UI shell and all tabs, trades (AI and human), injuries, careers/records/Hall of Fame, scouting with a scouted draft board and user picking, draft lottery, free-agent signing and releasing, re-sign decisions, the owner's offseason window, loans, sponsorship style, arena projects, revenue sharing. Remaining (autonomous work order, Owner Mode first): deeper simulation (matchups, timeouts; the overtime rate is still low), contract negotiation, draft pick trading, AI-proposed trades, mobile layouts, a visual polish pass.
4. (done) **Basketball engine v1**: possession simulation, box scores, stress-test tool for plausibility.
5. (done) **League operations**: schedule, standings, playoffs, season progression.
6. (done) **Basic UI shell**: main menu, save selection, standings, box score viewer (manual testing begins).
7. (done) **Owner Mode**: finances, tickets, arena, sponsorships, GM/coach hiring.
8. (done) Draft, free agency, trades, development/regression, scouting, injuries.
9. (done) Career Mode and Dynasty Mode (card game; offline, free-to-play, all content from Creator Studio releases; see docs/DYNASTY_MODE_PLAN.md). Three modes in total. Dynasty still needs the founder's real content and (later) online play; its mobile layouts are built and checked in a phone-sized window, not yet on a device.
10. Mobile layouts/exports, polish, release infrastructure.

## Next phases (the founder's order, 2026-11-21; design directions only, none started)
1. **Phase 1, ecosystem integration and documentation reconciliation:** done (see Completed).
2. **Phase 2, game replays and basketball presentation:** lineup selection, match simulation, full box scores and game history, better game-day presentation, play-by-play with a visual and replay ability, in all game modes.
3. **Phase 3, franchise and league immersion:** historical franchise records, retired jerseys, league-wide storylines, rivalry development, richer player and team histories.
4. **Phase 4, Career RPG expansion:** career timeline, media and public reputation, more meaningful life decisions, legacy presentation.
5. **Phase 5, Dynasty expansion:** more collections, card mastery, seasonal content, competitive rankings, tournament depth.
6. **Phase 6, online foundations:** accounts, server-authoritative profiles, persistent collections, matchmaking architecture, security and transaction infrastructure (any new dependency or hosting needs founder approval).

## Outstanding dependencies
- Basketball engine needs the attribute/data model.
- Owner Mode finances need a running league (attendance, wins) and contracts.
- UI needs a stable data model to bind to.
