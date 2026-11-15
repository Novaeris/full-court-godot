# Full Court — Project Rules for Claude

Full Court is a long-term, commercial-quality basketball management simulation (real-world cities, original franchises and players).
It is NOT an MVP or prototype: build the real architecture, expand it incrementally, keep it playable and tested.
The developer is a solo, beginner programmer. Explain decisions in plain language, give exact steps, and ask before major product/architecture decisions.

## Established decisions (do not change without the user's explicit approval)
- Engine: Godot 4.7 standard (NOT .NET). Language: GDScript. Renderer: gl_compatibility (mobile-friendly).
- Platforms: Windows first; architecture must not block Mac/Android/iOS.
- Modes: Owner Mode first, Dynasty Mode later. Both share one simulation/league core.
- Free-to-play, no pay-to-win. No monetization code until there is a clear reason.
- Real-world places are fine (real cities and countries, user-selectable by area). Teams, players, staff and branding are ORIGINAL and generated: no real franchises, player names, logos or league IP (those need licenses). Changed from "fully fictional" by the founder on 2026-11-15.
- Leagues are user-customizable: size, which areas/cities, number of conferences and divisions.
- Version control: Git, private GitHub repo. Never publish or push without being asked.

## Layout
- `src/core/`   Foundation utilities with no game knowledge (seeded RNG, ID generation).
- `src/data/`   Data model: attributes, player, team, contract, world/repositories (see docs/ARCHITECTURE.md). No UI or simulation code here.
- `src/save/`   Save system (slots, checksums, backups, migrations). Changing saved data shape REQUIRES bumping `FcVersion.DATA_VERSION` and adding a migration step.
- `src/gen/`    Procedural generation (names, players, staff, whole league). Content lives in `data/generation/*.json`. Always generate through seeded `FcRng`.
- `data/definitions/`  JSON definitions of attributes, personality traits, tendencies. Edit these to rebalance, not code.
- `src/...`     Further modules are added only when they hold real code (see docs/ARCHITECTURE.md).
- `tests/`      Automated tests. `tests/unit/test_*.gd`; base class `FcTestCase`.
- `tools/`      Dev scripts (test runner wrapper, later: season stress-test).
- `docs/`       Living documentation. Update it in the same change as the code.

## Architectural rules
1. Simulation, rules, data, generation, game-mode logic, UI, saving and tests are separate layers. Simulation code must never reference UI nodes and must run headless.
2. All randomness goes through `FcRng` (seeded, forkable). Never use global `randf()`/`randi()` in simulation or generation code.
3. Every entity has a stable integer ID from `FcIdGenerator`; IDs are never reused. Reference other entities by ID, not by object.
4. Data-driven where practical (league rules, attributes, constants live in data, not scattered literals).
5. Save formats are versioned. Never change a saved format without a migration.
6. No raw floats in saved data (JSON loses precision): use integers or `FcChecks.quantize()` in a setter. Store 64-bit numbers as text.
7. Do not add dependencies/plugins/databases without explaining tradeoffs and getting approval.
8. Do not build placeholder systems or empty folders for show.

## Coding conventions (GDScript)
- Files `snake_case.gd`; global classes `class_name FcPascalCase` (the `Fc` prefix avoids clashes with Godot built-ins).
- Static typing wherever practical (`var x: int`, `-> void`).
- `##` doc comments on every class and public method explaining *why*, not just what.
- Tabs for indentation (Godot default). Small focused files and functions.
- Constants in UPPER_SNAKE_CASE. Private members start with `_`.

## Testing requirements
- Run the suite before reporting any change as working:
  `godot_console --headless --path . --import --quit` (only needed after adding new class_name files), then
  `godot_console --headless --path . --script res://tests/run_tests.gd`
  (or `./tools/run_tests.ps1` from PowerShell). Exit code 0 = pass.
- Every new system ships with tests. Bug fixes ship with a regression test.
- Use fixed seeds in tests so failures are reproducible.
- Never claim something works without running it. Say clearly what was and wasn't verified.
- Use `godot_console` (not `godot`) for command-line runs so output appears in the terminal.

## Git practices
- Commit at meaningful milestones with clear messages; keep `main` passing tests.
- `.godot/` and build/export output are git-ignored. Commit `.uid` files (Godot 4.4+ needs them).
- Do not delete or overwrite important files without explaining why and getting approval.

## Docs to keep current
GAME_DESIGN.md, ARCHITECTURE.md, ROADMAP.md, DECISIONS.md, TESTING.md in `docs/`.
