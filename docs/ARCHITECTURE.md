# Architecture

Status: foundation stage. Items marked **(planned)** do not exist yet; items without it do.

## Guiding idea
One shared basketball universe + simulation core. Game modes (Owner, Dynasty) are thin layers that decide *what the player is allowed to do and see*, not separate games. The UI is a replaceable skin over the core.

## Layers (dependencies point downward only)

```
UI (scenes, screens, widgets)                      (planned)
  ↓ reads state, sends commands
Game Modes (Owner, Dynasty: permissions, flows)    (planned)
  ↓
League & Business Systems (schedule, standings,    (planned)
  draft, free agency, trades, finances)
  ↓
Basketball Simulation (possessions, box scores)    (planned)
  ↓
Data Model (players, teams, staff, contracts, ...) (planned)
  ↓
Core (FcRng, FcIdGenerator)                        EXISTS: src/core/
```

Save/load sits beside the data model: it serializes the data model, never the UI. Procedural generation (names, players, draft classes) sits beside the data model and uses only `FcRng`.

## Modules
| Module | Responsibility | Status |
|---|---|---|
| `src/core/rng.gd` (`FcRng`) | Seeded, forkable, save-able random numbers. All randomness goes through it so any run is reproducible. | Done, tested |
| `src/core/id_generator.gd` (`FcIdGenerator`) | Stable, never-reused integer IDs per entity kind; serializable. | Done, tested |
| Data model | Plain data classes (RefCounted/Resource) with `to_dict()`/`from_dict()`; reference each other by ID. | Planned |
| Simulation | Possession-by-possession engine, headless, driven by attributes + tactics. | Planned |
| League rules | Data-driven config (conference layout, season length, playoff format, cap rules). | Planned |
| Save system | Versioned files, slots, metadata, atomic writes, migrations. | Planned |
| Game modes | Owner / Dynasty permission + flow layer over the shared core. | Planned |
| UI | Reusable components, responsive layouts (PC vs mobile arrangements). | Planned |

## Data architecture (recommended direction)
- In memory: typed GDScript classes holding dictionaries/arrays keyed by integer ID, so lookups are O(1).
- On disk (saves): versioned structured data (JSON-compatible dictionaries, compressed binary option later). Human-debuggable early on, easy to migrate.
- SQLite is **not** adopted now. Reason: it adds a native plugin dependency that complicates mobile exports, and a league of a few thousand players with decades of history fits comfortably in memory. Revisit if historical stats (millions of rows) make loading/search slow. See DECISIONS.md.

## Simulation architecture (planned)
- Pure functions of (state, tactics, rng) → events/stats. No scene tree access.
- Game = loop of possessions; each possession resolves via attribute-weighted probabilities tied to basketball logic (not arbitrary dice).
- Stress tools simulate thousands of games with fixed seeds and check statistical plausibility.

## Game mode architecture (planned)
A mode defines a *permission set* (which actions the player may take directly vs delegate to AI staff) and which UI screens are available. Owner Mode delegates roster decisions to an AI GM; Dynasty Mode exposes them. Both call the same core services.

## UI structure (planned)
Godot Control scenes, reusable components (tables, stat cards, charts), theme resource for consistent typography/colors. PC and mobile get separate layout arrangements from the same screen logic.

## Testing
See TESTING.md. Headless custom runner (`tests/run_tests.gd`) with `FcTestCase`.
