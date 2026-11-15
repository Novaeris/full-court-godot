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
