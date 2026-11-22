# Full Court — Project Rules for Claude

Full Court is a long-term, commercial-quality basketball management simulation (real-world cities, original franchises and players).
It is NOT an MVP or prototype: build the real architecture, expand it incrementally, keep it playable and tested.
The developer is a solo, beginner programmer. Explain decisions in plain language, give exact steps, and ask before major product/architecture decisions.

## Established decisions (do not change without the user's explicit approval)
- Engine: Godot 4.7 standard (NOT .NET). Language: GDScript. Renderer: gl_compatibility (mobile-friendly).
- Platforms (D-030): PC (Windows first, Mac later) will host all three modes; **mobile (Android/iOS) is for Dynasty Mode only**. Owner and Career screens are designed for desktop (mouse, big windows); only Dynasty needs touch layouts. Architecture still must not block Mac/Android/iOS.
- Modes (defined by the founder 2026-11-16, see D-029): THREE modes. **Owner Mode** (built first): control every operation of a franchise, simulated for up to 50 years; cannot be lost, but the owner can transfer to another team like changing jobs; randomized players. **Career Mode**: create one player and take them through an RPG-style career (about 20 years); randomized players. **Dynasty Mode**: a card-collecting game inspired by NBA 2K MyTeam with static, hand-made players (the founder will supply them) and some paid features. Owner Mode and Career Mode are built and playable (Career: `docs/CAREER_MODE_PLAN.md`); Dynasty Mode is built (offline, D-043 to D-046, `docs/DYNASTY_MODE_PLAN.md`): extend it only through its domain services. Career is a complete single-player game; online play is not planned for it (any online team play would be a later Dynasty-side track). Owner and Career share the simulation/league core.
- Free-to-play, no pay-to-win. No monetization code until there is a clear reason.
- Real-world places are fine (real cities and countries, user-selectable by area). Teams, players, staff and branding are ORIGINAL and generated: no real franchises, player names, logos or league IP (those need licenses). Changed from "fully fictional" by the founder on 2026-11-15.
- Leagues are user-customizable: size, which areas/cities, number of conferences and divisions.
- Version control: Git. The GitHub repo exists (public, Novaeris/full-court-godot, created 2026-11-17 at the founder's request, D-032). Never push, create or change remotes, or change visibility without being asked.

## Layout
- `src/core/`   Foundation utilities with no game knowledge (seeded RNG, ID generation).
- `src/data/`   Data model: attributes, player, team, contract, world/repositories (see docs/ARCHITECTURE.md). No UI or simulation code here.
- `src/save/`   Save system (slots, checksums, backups, migrations). Changing saved data shape REQUIRES bumping `FcVersion.DATA_VERSION` and adding a migration step.
- `src/gen/`    Procedural generation (names, players, staff, whole league). Content lives in `data/generation/*.json`. Always generate through seeded `FcRng`.
- `src/league/` Pure league computations (matchup planner). League STRUCTURE and RULES data classes are in `src/data/league/`; salary presets in `data/rules/`.
- `src/sim/`    Game simulation (headless, pure). Balance numbers live in `data/simulation/*.json`; recalibrate with `tools/simulate_games.ps1` after any change and keep all 16 league-average checks in range.
- `src/data/season/` + `src/league/season_engine.gd`: seasons (calendar, results, playoffs, awards). `tools/play_season.ps1` plays one.
- `src/data/business/` + `src/league/finance_engine.gd`: Owner Mode business model. `tools/finances.ps1` shows the books.
- `src/game/`  The game controller: the one API screens use. Screens must call it, never the engines directly.
- `data/definitions/`  JSON definitions of attributes, personality traits, tendencies. Edit these to rebalance, not code.
- `src/career/` + `src/data/career/` + `data/career/`  Career Mode (docs/CAREER_MODE_PLAN.md): pure build validation, progression rules and the career season rules, the career profile record, archetypes and build rules as data. The player itself is the shared `FcPlayer`; never create a second player type.
- `src/dynasty/` + `src/data/dynasty/` + `src/ui/dynasty/` + `data/dynasty/`  Dynasty Mode: pure domain services (economy, packs, collection, lineup, challenges, tournament), profile records, screens. State changes only via `FcDynastySession.commit()` through `FcDynastyController`; saves are `user://dynasty/*.dyn` (`FcVersion.DYNASTY_DATA_VERSION` + `FcDynastyMigrator`).
- `src/ui/`  Screens and the design system (D-047, D-057): tokens and theme at the top, `kit/` components (FcTable, charts, buttons, dialogs), `shell/`, `cards/`, `player/` (one resolver for a player's look), `team/` (one resolver for a team's crest), `menu/`, `owner/`, `career/`, `dynasty/`, `brand/`, `art/`. Screens take colours and sizes from tokens (the style-lint test enforces it) and call the controller, never the engines.
- `src/audio/`  Sound (D-054): `FcAudio` (owned by FcApp, fire cues with `FcAudio.cue("id")`), `FcAudioSynth` (sounds built from recipes in `data/ui/audio.json`; no unlicensed audio).
- `src/content/`  Content publishing (D-042): release manifest, validator, local store, publisher, loader, catalog. The ONE shared copy used by the game and Creator Studio.
- `creator_studio/`  Separate Godot project (Creator Studio) in this repo; reaches the game code and data through the git-ignored junctions `game_src` and `data` (`tools/link_studio.ps1`). Never copy game code into it. Check it with `godot_console --headless --path creator_studio --script res://tools/studio_smoke.gd`.
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
9. Naming and IP: real places are fine; teams, players, staff and branding are original. Do not use league-branded terms or names (e.g. NBA's "Bird rights", "Designated Veteran", "apron", trophy or league names); use our own or generic terms ("cornerstone extension", "restriction line"). Rules and mechanics are not copyrightable but names can be trademarked. A lawyer should review before a commercial release.

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
GAME_DESIGN.md, ARCHITECTURE.md, ROADMAP.md, DECISIONS.md, TESTING.md in `docs/`, plus FEATURE_MATRIX.md (the one place that says what is built, with test evidence: update it in the same change as the feature) and INTEGRATION_AUDIT.md (cross-mode findings). Current test totals live ONLY in TESTING.md; other docs link to it and never copy numbers.
