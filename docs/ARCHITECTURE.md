# Architecture

Items marked **(planned)** do not exist yet; everything else is implemented and tested.

## Guiding idea
One shared basketball universe + simulation core. Game modes (Owner, Dynasty) are thin layers that decide *what the player is allowed to do and see*, not separate games. The UI is a replaceable skin over the core.

## Layers (dependencies point downward only)

```
UI (scenes, screens, widgets)                      (planned)
Game Modes (Owner, Dynasty: permissions, flows)    (planned)
League & Business Systems (schedule, standings,    (planned)
  draft, free agency, trades, finances, cap rules)
Basketball Simulation (possessions, box scores)    (planned)
Data Model (src/data): players, teams, contracts,  IMPLEMENTED
  attributes, world container, repositories
Core (src/core): FcRng, FcIdGenerator              IMPLEMENTED
```

Save/load serializes the data model, never the UI (planned; the data model already produces/consumes snapshots). Procedural generation (planned) uses only `FcRng` and the data model.

## Data model rules
1. Every entity has a stable integer `id` from `FcIdGenerator` (never reused, 0 = none).
2. Entities reference each other **by ID only**, never by object. This prevents circular references and makes saving trivial.
3. Each class has `validate() -> Array[String]` (empty = valid), `to_dict()` and `static from_dict()`. `from_dict` tolerates missing fields (fills defaults) and never crashes on bad data; `validate()` reports it.
4. Top-level entities write a `"schema"` version. Old saves load with defaults for new fields; real migrations will be added by the save system when a field is removed or changes meaning.
5. Money is whole dollars (`int`). Seasons are the calendar year in which they start. Dates are `FcDate` (ISO text when saved). Physical measures are metric.
6. The data model contains no simulation, UI, or Godot scene code.

## Data model map (`src/data/`)

```
common/      FcChecks (validation helpers), FcDate
attributes/  FcAttributeDef      one rating's definition (key, range, default...)
             FcAttributeCatalog  loaded list of definitions of one kind
             FcAttributeSet      one entity's values, validated against a catalog
             FcDefinitionSet     the 3 catalogs: attributes, personality, tendencies
player/      FcPlayer            composed of:
               FcPlayerIdentity  names, birth date, birthplace, country
               FcPlayerPhysical  height, weight, wingspan, handedness
               FcPlayerDevelopment potential, peak age, development rate, volatility
               3 x FcAttributeSet  attributes, personality, tendencies
               FcPosition        position ids (primary + optional secondary)
team/        FcTeam              composed of:
               FcTeamIdentity    nickname, abbreviation, founded year
               FcTeamBranding    colors, logo key
               FcRoster          list of player ids (the changing part)
             FcCity              market: population, economy
             FcArena             capacity, year built, city
contract/    FcContract          player_id, team_id, status, signing date, composed of:
               FcContractYear    season, salary, guaranteed, option (type/status)
               FcContractBonus   kind, season, amount, guaranteed, counts vs cap
world/       FcRepository        persistence interface (abstract)
             FcMemoryRepository  in-memory implementation
             FcWorld             definitions + id generator + repositories +
                                 cross-entity validation + snapshot to/from dict
```

Attribute definitions live in `data/definitions/*.json` (28 basketball attributes, 7 personality traits, 8 tendencies). Add, rename or rebalance by editing JSON; `FcAttributeSet` fills any attribute added later with its default when old data loads.

## Relationships
- Player ↔ Team: via `FcRoster` (the team's roster is the single source of truth for membership). A player does not store his team.
- Player ↔ Contract ↔ Team: a contract holds `player_id` and `team_id`. A player may have many contracts over time but at most one `ACTIVE`; every rostered player must have an ACTIVE contract with that team (checked by `FcWorld.validate()`).
- Team → City / Arena: by id. Arena → City: by id. Relocation = change `city_id`; the team id is unchanged.
- Not on the player/team by design (separate records keyed by id, to be built with their systems): career and season statistics, historical records and awards (keyed by `player_id` / `team_id` + season), team finances, staff, owner (`owner_id` reserved, unchecked until that entity exists).

Permanent vs changing team information: id + founded year are permanent; identity/branding/city/arena/owner change rarely (rebrand, relocation); roster changes constantly; per-season data (records, finances) will be season-keyed records.

## Persistence abstraction
Game systems use `FcRepository` (get, has, add, update, remove, ids, all, count) and never a specific storage engine. `FcMemoryRepository` is the only implementation today. SQLite or another store can later be added as another `FcRepository` implementation. The save system (planned) will wrap `FcWorld.to_dict()` with slots, metadata, versioning, atomic writes and migrations.
Known limit: `team_of_player()` and `active_contract_of()` scan linearly; indexes will be added when profiling justifies them.

## Simulation architecture (planned)
Pure functions of (state, tactics, rng) → events/stats, no scene tree access. Possession-based, attribute-driven. Stress tools simulate thousands of games with fixed seeds.

## Game mode architecture (planned)
A mode defines a permission set (which actions the player does directly vs. delegates to AI staff) and which UI screens are available. Both modes call the same core services.

## UI structure (planned)
Godot Control scenes, reusable components, shared theme. PC and mobile get separate layouts from the same screen logic.

## Testing
See TESTING.md.
