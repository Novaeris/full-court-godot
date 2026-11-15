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

## D-010 Save format (2026-11-15)
- JSON text: header line + payload, SHA-256 checksum, one file per slot under `user://saves/`.
  Alternatives: binary/compressed (smaller, not debuggable; can be added later via format version), SQLite (deferred, see D-007), Godot Resource files (tied to engine internals and unsafe to load from untrusted files).
- Atomic write with verification and `.bak`; recovery order main → temp → backup.
- `DATA_VERSION` + step migrator; newer saves refused rather than guessed at.
- Saving never refused for integrity problems; loading reports warnings.
- `user://` is the per-user game data folder (on Windows: `%APPDATA%\Godot\app_userdata\Full Court\`). Works on all target platforms.
- Bug found and fixed while designing: JSON numbers are doubles, so 64-bit RNG state/seed are saved as text.

## D-011 Staff model (2026-11-15)
- Staff mirror players: identity + data-driven attribute sets (skills, personality, philosophy). `FcPlayerIdentity` was renamed `FcPersonIdentity` and shared; the saved format did not change.
- Roles are a closed enum (rules refer to them: one GM, one head coach per team); skills are data.
- Staff have their own contract entity rather than reusing `FcContract`. Rejected alternative: one contract type with a subject kind. It would force salary-cap/guarantee semantics onto staff pay, and changing the player contract format would need a save migration. Cost: a little duplication of year/season queries.
- A staff member's `primary_role` (profession, for browsing the hiring pool) is separate from the role on their contract (the job held).
- Team staff = ACTIVE staff contracts; there is no separate staff list to keep in sync.
- Staff sections in snapshots are additive (missing = empty), so DATA_VERSION stays 1. If a future change removes or reinterprets saved fields, bump it and add a migration.
- What staff skills DO (coach quality affecting development, GM evaluation affecting trades, scouting accuracy) is deliberately not implemented; each hooks in when its system is built.

## D-012 Procedural generation (2026-11-15)
- Content in JSON (`data/generation/`), logic in `src/gen/`. Names: 7 pools mixed per fictional country (Aldoria is home; Brenmark, Castellia, Tarsany, Kalunda, Shirane, Highcourt supply ~20% international players). Cities, countries, nicknames, arenas are all fictional; nicknames avoid real pro team names.
- Hand-curated city and nickname lists rather than syllable-generated names: better quality and no accidental unfortunate names; 40 of each is enough for a 30-team league and some expansion. Can be extended or made procedural later.
- Player quality comes from one `level` plus position profile and shared latents, so attributes correlate sensibly. Rejected: independent random attributes (unrealistic players).
- League structure (30 teams) is a generation DEFAULT in config, not a league rule; conferences/divisions are a later system. Founder input needed when that system is designed.
- Contracts are generated partly served (started up to N-1 seasons ago) so expirations are staggered from day one.
- All generation numbers are first drafts; they will be tuned with the simulation and stress tests.

## D-014 Real-world places, original franchises (2026-11-15, founder decision)
- The founder dropped the "fully fictional world" requirement: cities and countries are now real and selectable by area (North America, South America, Europe, Asia, Oceania, Africa). Supersedes the fictional-geography parts of D-012 (Aldoria and the other invented countries were removed).
- Kept: teams, players, staff and branding are original and generated. Real franchises, real player names and logos would require licensing and were excluded by the founder's original brief. Team nicknames avoid real pro team names (but a generated "Paris Barons" could coincide with a real club; that is accepted, names are generic).
- City data: 124 cities with approximate metro populations and a 0-100 "economy" game-balance index (not an official statistic) in `data/generation/world.json`. Coordinates there are used only to group teams geographically and are not saved on FcCity yet (add them when travel/time zones are built).
- Politically sensitive entries (e.g. disputed territories, Russia) were left out for now; the list is easy to extend by editing the JSON.
- Name styles: 12 pools (anglo, hispanic, west_african, south_european, east_european, nordic, east_asian, western_european, middle_eastern, south_asian, southeast_asian, east_african) mixed per country. They are approximations; expect to refine them.

## D-015 Customizable league structure (2026-11-15, founder request)
- `FcLeague` > `FcConference` > `FcDivision` > team ids, a saved entity with stable ids. Membership lives in the division (single source of truth). Several leagues per world are possible (additional leagues are a monetization idea).
- Customization lives in `FcGenerationConfig` (the future "new league" screen edits it); `validate()` returns plain-language messages. Auto-grouping is geographic. Names are generated (Western/Eastern, South/North...) and are meant to be user-editable later. Explicit per-team division assignment is supported by the data model (`add_team`/`remove_team`) but has no generation option yet.
- Rules (season length, playoffs, salary cap, schedule format) are NOT part of the league structure; they will be separate rules data keyed by league_id so leagues can differ.
- Saving: `leagues` and `FcCity.area` are additive snapshot fields, so DATA_VERSION stays 1 and older snapshots load (no league / empty area).

## D-013 Floats in saved data; runner robustness (2026-11-15)
- Found by a test: JSON float round trips lose last bits, so a saved-and-reloaded world differed from the original. Rule: saved floats are quantized to 3 decimals via `FcChecks.quantize` in property setters; prefer integers. Documented in ARCHITECTURE rule 7.
- Found while testing: a test file with a syntax error made the test runner hang forever. The runner now reports such files as failures.

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
