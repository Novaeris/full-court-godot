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
Procedural generation (src/gen, data/generation)    IMPLEMENTED
Core (src/core): FcRng, FcIdGenerator, FcVersion   IMPLEMENTED
Save system (src/save) beside the data model        IMPLEMENTED
```

Save/load serializes the data model, never the UI. Procedural generation (planned) uses only `FcRng` and the data model.

## Data model rules
1. Every entity has a stable integer `id` from `FcIdGenerator` (never reused, 0 = none).
2. Entities reference each other **by ID only**, never by object. This prevents circular references and makes saving trivial.
3. Each class has `validate() -> Array[String]` (empty = valid), `to_dict()` and `static from_dict()`. `from_dict` tolerates missing fields (fills defaults) and never crashes on bad data; `validate()` reports it.
4. Top-level entities write a `"schema"` version. Old saves load with defaults for new fields; real migrations will be added by the save system when a field is removed or changes meaning.
5. Money is whole dollars (`int`). Seasons are the calendar year in which they start. Dates are `FcDate` (ISO text when saved). Physical measures are metric.
6. The data model contains no simulation, UI, or Godot scene code.
7. **No raw floats in saved data.** Godot's JSON keeps only ~14 significant digits, so an arbitrary float changes in its last bits after save + load, which would break exact reproducibility. Floats that must be saved go through `FcChecks.quantize()` (3 decimals) in a property setter (see `FcPlayerDevelopment`). Prefer integers (money in dollars, ratings 0-100). 64-bit values are saved as text.

## Data model map (`src/data/`)

```
common/      FcChecks (validation helpers), FcDate
attributes/  FcAttributeDef      one rating's definition (key, range, default...)
             FcAttributeCatalog  loaded list of definitions of one kind
             FcAttributeSet      one entity's values, validated against a catalog
             FcDefinitionSet     the 3 catalogs: attributes, personality, tendencies
player/      FcPlayer            composed of:
               FcPersonIdentity  names, birth date, birthplace, country
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
league/      FcLeague            name + conferences; team membership queries; add_team / remove_team
               FcConference      name + divisions
               FcDivision        name + team ids
contract/    FcContract          player_id, team_id, status, signing date, composed of:
               FcContractYear    season, salary, guaranteed, option (type/status)
               FcContractBonus   kind, season, amount, guaranteed, counts vs cap
staff/       FcStaffMember       coach / GM / scout / medical / business exec, composed of:
               FcPersonIdentity  (shared with players; lives in common/)
               3 x FcAttributeSet  skills, personality, philosophy
             FcStaffRole         the six jobs (GM, head coach, assistant, scout, medical, business exec)
             FcStaffContract     staff_id, team_id, role, signing date, status, years (FcContractYear)
world/       FcRepository        persistence interface (abstract)
             FcMemoryRepository  in-memory implementation
             FcWorld             definitions + id generator + repositories +
                                 cross-entity validation + snapshot to/from dict
```

Attribute definitions live in `data/definitions/*.json`: 28 basketball attributes, 7 personality traits, 8 tendencies (players); 17 staff skills in 5 categories and 7 philosophy dials (staff). `FcDefinitionSet.all()` lists every catalog. Add, rename or rebalance by editing JSON; `FcAttributeSet` fills any attribute added later with its default when old data loads.

## Relationships
- Player ↔ Team: via `FcRoster` (the team's roster is the single source of truth for membership). A player does not store his team.
- Player ↔ Contract ↔ Team: a contract holds `player_id` and `team_id`. A player may have many contracts over time but at most one `ACTIVE`; every rostered player must have an ACTIVE contract with that team (checked by `FcWorld.validate()`).
- Staff ↔ Team: via `FcStaffContract` (staff_id, team_id, role). A team's staff = its ACTIVE staff contracts (no separate staff list, single source of truth). Rules checked by `FcWorld.validate()`: one active job per person, at most one active General Manager and one Head Coach per team, retired staff cannot hold an active job. Scouts, assistants, medical and business roles are not limited.
- Staff contracts are separate from player `FcContract`: staff pay comes from the operating budget (Owner Mode), not the salary cap, and has no guarantees/bonuses/cap hits. Query helpers on `FcWorld`: `staff_contracts_of_team`, `staff_in_role`, `active_staff_contract_of`.
- Save compatibility: the `staff` / `staff_contracts` snapshot sections are additive; snapshots without them load as empty, so `DATA_VERSION` stays 1.
- Team ↔ League: a team belongs to a league by being in one of its divisions (`FcLeague` is the single source of truth). `FcWorld.validate()` requires every team to be in exactly one league whenever any league exists. League structure only; league rules (season length, playoffs, cap) will be separate data keyed by league_id.
- Team → City / Arena: by id. Arena → City: by id. Relocation = change `city_id`; the team id is unchanged.
- Not on the player/team by design (separate records keyed by id, to be built with their systems): career and season statistics, historical records and awards (keyed by `player_id` / `team_id` + season), team finances, staff, owner (`owner_id` reserved, unchecked until that entity exists).

Permanent vs changing team information: id + founded year are permanent; identity/branding/city/arena/owner change rarely (rebrand, relocation); roster changes constantly; per-season data (records, finances) will be season-keyed records.

## Procedural generation (`src/gen/`, content in `data/generation/*.json`)
```
FcGenerationData     loads names.json, world.json, position_profiles.json, staff_profiles.json, config.json; validate()
FcGenerationConfig   everything a user can customize: league name, size, areas or exact cities, conferences/divisions,
                     roster/staff sizes, nationality mix, salary range; validate() gives readable messages
FcNameGenerator      weighted name pools per country; nationality choice; unique names across a league
FcPlayerGenerator    FcPlayerSpec (age, position, level, country) -> FcPlayer
FcStaffGenerator     role + level -> FcStaffMember (role-specialized skills, reputation-based pay)
FcWorldGenerator     seed -> complete FcWorld; new_game_state(seed, mode, team index) -> FcGameState
```
- Reproducible: same seed + config = identical world. Each stage (cities, every team, free agents) uses its own forked `FcRng` stream, so changing one stage does not reshuffle the rest.
- Player realism: attribute = overall level + position offset + a shared latent per category (skill / athleticism / IQ) + individual noise; height and weight follow the position profile; tendencies blend skill with position habits; potential grows with years left before the player's peak age. Young players have lower current level, old players decline (`age_adjusted_level`).
- Places: 124 real cities in 54 countries and 6 areas (`data/generation/world.json`); teams are original franchises (100 generated nicknames, 16 color schemes, generated arenas). Cities are chosen by area + size/weighted-random, or from an exact list. Conferences/divisions are built geographically (west-east, then south-north) with sizes differing by at most 1.
- Contents per team: 15 players with mid-life contracts, a GM, head coach, 3 assistants, 3 scouts, medical and business staff with contracts; plus a free-agent pool. Players come from the team's own country 55% of the time, otherwise by country talent weight; staff 80% local.
- NOT generated yet (belongs to later systems): conferences/divisions/schedule, draft prospects, historical careers and league history, owners.
- All numbers (level ranges, salary curve, profile offsets) are first drafts to be tuned against the simulation.

## Save system (`src/save/`, root object `src/data/world/game_state.gd`)
- `FcGameState`: the root of a playthrough: world, random generator position, mode (owner/dynasty), user team, current season/date. This is what a slot contains.
- `FcSaveManager`: save / load_slot / list_slots / delete_slot / autosave. Slots are named `[a-z0-9_]{1,32}`; `autosave` is reserved.
- File (`<slot>.sav` in `user://saves/`): line 1 = header JSON (`FcSaveMetadata`: label, team, season, mode, versions, timestamp, SHA-256 + byte count of payload); rest = payload JSON. Listing slots reads only line 1.
- Safe writing: write `.tmp` → read back and verify checksum → rotate old save to `.bak` → rename `.tmp` into place. A verified complete copy exists at every step.
- Recovery on load: main file → verified `.tmp` → `.bak`. `FcSaveResult.recovered_from` says which was used so the UI can tell the player. Damaged files with no usable copy return `CORRUPT` with a plain-language message; nothing crashes.
- Versioning: `FcVersion.DATA_VERSION` (currently 1) is stored in every header. Saves from a newer game are refused (`UNSUPPORTED_VERSION`). Older saves go through `FcSaveMigrator` steps (N→N+1, registered per version; none yet). Rule: when a saved shape changes, bump DATA_VERSION and add a step; never edit released steps.
- Policy: saving never refuses because of world integrity problems (progress matters most); problems are returned as `warnings` on save and load.
- 64-bit values (e.g. RNG state) are stored as text, because JSON numbers are doubles and would lose precision.
- Not built yet: compression/binary format, cloud sync, save-slot screenshots, multiple autosave rotation, automatic autosave triggers (those belong to the game loop).

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
