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

- Basketball simulation v1: possession engine, rotations, fatigue, coach effects, box scores and advanced stats, calibrated stress tool (245 tests total)

## Current
- Awaiting founder direction on the next system.

## Next (proposed order, driven by dependencies)
1. (done) Staff entities. 2. (done) Save system. 3. (done) Procedural generation of the league.
   League structure, league rules and simulation v1 are done. Next: the calendar / standings / playoff engine (uses the matchup planner, playoff rules and the simulator), then season progression (aging, development, retirement), then free agency / trades / draft using the cap rules, then injuries and deeper simulation (matchups, timeouts, end-game fouling).
4. **Basketball engine v1**: possession simulation, box scores, stress-test tool for plausibility.
5. **League operations**: schedule, standings, playoffs, season progression.
6. **Basic UI shell**: main menu, save selection, standings, box score viewer (manual testing begins).
7. **Owner Mode**: finances, tickets, arena, sponsorships, GM/coach hiring.
8. Draft, free agency, trades, development/regression, scouting, injuries.
9. Dynasty Mode, history/records, narratives.
10. Mobile layouts/exports, polish, release infrastructure.

## Outstanding dependencies
- Basketball engine needs the attribute/data model.
- Owner Mode finances need a running league (attendance, wins) and contracts.
- UI needs a stable data model to bind to.
