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

## D-004 Test framework: custom minimal runner (PENDING FOUNDER APPROVAL)
Chosen: ~60-line headless runner (`tests/run_tests.gd`) + `FcTestCase`.
Alternative: GUT (popular third-party Godot test plugin).
Reasons: zero dependencies, works immediately on 4.7, simple for a beginner to read. GUT can be adopted later if we need mocking/richer reporting; tests are plain methods so migration is easy.

## D-005 Randomness
All simulation randomness goes through `FcRng` (seeded, forkable, state-saveable) for reproducible bugs and consistent saves.

## D-006 IDs
Stable integer IDs per entity kind (`FcIdGenerator`), never reused. Chosen over strings/UUIDs for speed, small saves, and simple dictionary keys.

## D-007 No SQLite yet
Deferred; see ARCHITECTURE.md "Data architecture". Revisit when history volume demands it.
