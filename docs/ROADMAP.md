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

## Current
- Awaiting founder direction on the next system (recommended: save system).

## Next (proposed order, driven by dependencies)
1. **Staff / coach / executive entities** (same patterns as Player; needed for Owner Mode hiring).
2. **Save system**: versioned save format, slots, atomic write, round-trip tests.
3. **Procedural generation**: names, players (attributes, potential, personality), teams, fictional cities/league layout.
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
