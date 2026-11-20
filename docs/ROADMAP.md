# Roadmap

Dependency-driven, continuous development (not an MVP schedule). Always keep the game testable.

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

## Current
- Owner Mode depth (see `docs/PROGRESS_LOG.md`). A milestone plan is drafted in `docs/MILESTONE_PLAN.md` and is the plan of record; the "Next" list below is only a rough guide.
- Stabilization (2026-11-19): fix doc and contract inconsistencies, run the full validation set, then founder manual playtesting, a visual and usability pass on the Owner and Career screens, and a rules freeze before the next major track.

## Next (proposed order, driven by dependencies)
1. (done) Staff entities. 2. (done) Save system. 3. (done) Procedural generation of the league.
   Done since: the UI shell and all tabs, trades (AI and human), injuries, careers/records/Hall of Fame, scouting with a scouted draft board and user picking, draft lottery, free-agent signing and releasing, re-sign decisions, the owner's offseason window, loans, sponsorship style, arena projects, revenue sharing. Remaining (autonomous work order, Owner Mode first): deeper simulation (matchups, timeouts; the overtime rate is still low), contract negotiation, draft pick trading, AI-proposed trades, mobile layouts, a visual polish pass.
4. **Basketball engine v1**: possession simulation, box scores, stress-test tool for plausibility.
5. **League operations**: schedule, standings, playoffs, season progression.
6. **Basic UI shell**: main menu, save selection, standings, box score viewer (manual testing begins).
7. **Owner Mode**: finances, tickets, arena, sponsorships, GM/coach hiring.
8. Draft, free agency, trades, development/regression, scouting, injuries.
9. (done) Career Mode. Dynasty Mode (card game, static hand-made players) is not started; its content pipeline (Creator Studio publishing and the game-side loader, D-042) is built first. Three modes in total.
10. Mobile layouts/exports, polish, release infrastructure.

## Outstanding dependencies
- Basketball engine needs the attribute/data model.
- Owner Mode finances need a running league (attendance, wins) and contracts.
- UI needs a stable data model to bind to.
