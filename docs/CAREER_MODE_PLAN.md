# Career Mode: repository audit and implementation plan (Phase 0)

*Planning record. Current Career feature status, with test evidence, is in [FEATURE_MATRIX.md](FEATURE_MATRIX.md).*

Status 2026-11-18. Written from the actual repository. The founder was away, so every open question below was answered with Claude's recommended answer and is marked **[Decision]**; change any of them before Phase 2 and the plan adapts. **Update 2026-11-19: phases 1-6 are built and Career Mode is playable** (test count and validation results: `docs/validation/`). Later decisions: D-039 (potential is the overall cap; growth is player-directed; one calculation behind the preview and the raise) and D-040 (a light prospect step: scouting report and draft pick from the player's rating); the profile id contract is D-041. The text below is the original Phase 0 audit and is kept as written. Supersedes the shorter `docs/CAREER_MODE_DRAFT.md` where they differ.

## 1. Repository architecture assessment
- **Layers (CLAUDE.md, ARCHITECTURE.md):** `core` (RNG, ids), `data` (entities), `gen` (generation), `sim` (headless game simulation), `league` (seasons, offseason, economy), `save`, `game` (the controller API screens use), `ui` (one big `app.gd`, about 2,400 lines, built in code), `tests` (about 600 tests, exit code 1 on failure), `tools` (stress and check scripts), CI on GitHub Actions.
- **Player model that already exists:** `FcPlayer` (`src/data/player/player.gd`) = identity (`FcPersonIdentity`: name, birth date, birthplace, country) + physical (`FcPlayerPhysical`: height, weight, **wingspan**, handedness) + 28 data-driven attributes (`data/definitions/attributes.json`, range **0-100**) + personality (7 traits) + tendencies (8) + development (`potential`, `peak_age`, `development_rate`, `volatility`) + positions. By decision D-009, contracts, team membership, statistics and history are NOT on the player; they are separate records keyed by `player_id`. Ratings the simulation uses are computed from attributes by `FcPlayerRatings` (`data/simulation/ratings.json`).
- **Simulation:** `FcGameSimulator` plays a game from two `FcGameTeam`s built by `FcGameTeam.from_world`, which reads rosters and ratings. A player is simulated purely through his `FcPlayer`; there is no notion of a human-controlled player. Lineups and minutes are chosen by the simulator from ratings, positions, fatigue and team tactics.
- **Progression:** `FcPlayerProgression` (yearly aging in the offseason, coach and facility effects, retirement). There is no XP, levels or in-season growth.
- **Seasons and calendar:** `FcSeasonEngine` plays a dated calendar; `FcOffseason` handles aging, expiry, re-signing, the draft, free agency. For non-Owner modes the offseason runs automatically (`run_first_half`/`run_second_half`), as in Spectator Mode.
- **Saves:** `FcGameState` (`src/data/world/game_state.gd`) is the root object (mode, season, owner fields, world); `FcSaveManager` writes checksummed slot files with backups; `FcSaveMigrator` has an empty step registry because `FcVersion.DATA_VERSION` is still 1. New fields so far were added with defaults ("additive") instead of version bumps. `FcGameState.MODES` lists owner and spectator.
- **Owner Mode dependencies:** `FcGameController` (about 2,000 lines) mixes mode-neutral calendar/season API (`advance_day`, `sim_playoffs`, `start_next_season`, standings) with owner-only features (finances, staff, GM, meeting). `FcApp` shows owner tabs when `state.mode == MODE_OWNER`.
- **UI conventions:** screens are built in code with `FcUiTables` helpers and `FcUiTheme` (dark theme, three text sizes, tooltips on levers, a tutorial panel from `data/tutorial.json`). Tests build screens headless and click through them.
- **Documentation state:** current after the 2026-11-18 reconciliation; `CAREER_MODE_DRAFT.md` is a high-level draft that this plan refines.

## 2. Conflicts between the brief and the repository (and how they are resolved)
| Brief | Repository | **[Decision]** |
|---|---|---|
| Attribute scale 25-99 | Catalog is data-driven, 0-100, 28 attributes; the generator and ratings depend on it | **Keep the one shared catalog (0-100).** Career builds are *validated* into 25-99 (start) and a per-attribute ceiling (max 99). No second attribute set. |
| Attribute list (Layup, Dunk, Close Shot, Post Control, Midrange, Three, FT, Passing, Ball Handling, Court Vision, Perimeter/Interior D, Steal, Block, Off/Def Rebound, Speed, Acceleration, Strength, Vertical, Stamina) | Has close_finishing, layups, dunking, mid_range, three_point, free_throw, passing, ball_handling, perimeter/interior_defense, steals, blocks, rebounding, speed, agility, strength, vertical, stamina, plus awareness/mental traits. No post control, court vision, acceleration, separate rebounding sides | **Map, do not add.** Post Control -> `close_finishing` + `post_tendency`; Court Vision -> `passing` + `basketball_iq`; Acceleration -> `agility` + `speed`; Off/Def Rebound -> `rebounding` + `offensive_rebound_tendency`. The creator UI may show the brief's labels as *views* over catalog keys. Adding attributes to the shared catalog changes ratings, generation and balance for Owner Mode, so it needs a separate approved change. |
| New `PlayerProfile` model | `FcPlayer` already is the player | **No duplicate.** "PlayerProfile" = `FcPlayer` (identity, physical, attributes, potential) + a new **`FcCareerProfile`** sidecar record keyed by `player_id` (archetype, appearance, jersey, XP, level, points, badges, reputation, stage, history, online identity placeholder). Same pattern as contracts and stats (D-009). |
| Career player on a team in the existing league | Roster, contracts, stats and the sim already handle any `FcPlayer` | The Career player is an ordinary roster player flagged by the sidecar; the rest of the league keeps running through existing rules. |
| Versioned saves + migration | Registry exists but empty | **Bump `DATA_VERSION` to 2 in Phase 1** with a tested v1 to v2 step (adds the empty career section). First real use of the migrator. |

## 3. Career Mode integration proposal
- **New mode `MODE_CAREER`** in `FcGameState`; a `career` dictionary in the saved state holds the career record(s).
- **`FcCareerController`** (`src/game/career_controller.gd`): the API Career screens call (create player, career hub data, spend points, equip badges, play day/season, history). It *composes* the existing `FcGameController` for calendar and season flow (so Owner code is untouched and nothing is duplicated) and adds only career-specific rules.
- **Pure rules** in a new `src/career/` module (no UI, no state): build validation, ceilings, XP and level curves, development-point costs, badge and skill unlocks, post-game rewards. Same shape as `src/league` (pure, seeded, data-driven).
- **Data** in `data/career/*.json`: archetypes, build budget, XP curve, badge definitions, skill trees, reward tables. New badges/archetypes are data, not code.
- **UI** in new files (`src/ui/career_*.gd`) because `app.gd` is already large; `FcApp` only routes the Career button to them.
- **Simulation integration (Phase 4):** (1) no parallel engine; the career player is simulated as any player. (2) The honest limit: one player among ten has a modest effect on results, so the RPG feel needs *role and usage* control (starter/bench goal, minutes target, shot-diet tendency). Add an optional `role` input to `FcGameTeam.from_world` that only applies to flagged players; with no flagged player behavior is bit-for-bit unchanged (regression-tested against fixed seeds). (3) Badge effects are small, capped, data-defined adjustments to the *composite ratings* in `FcPlayerRatings` for equipped badges only. (4) The rest of the league (AI re-signing, draft, trades) already runs in the automatic offseason.
- **Coexistence with the league database:** the Career player is generated into a normal generated league (same creator as Owner Mode's league wizard) as a drafted rookie or free agent; `FcWorld.validate` keeps checking him like anyone else.

## 4. Player domain model (proposed)
- `FcPlayer` (existing): identity, physical (height, weight, wingspan, hand), attributes (0-100 catalog), potential and development, positions.
- `FcCareerProfile` (new, `src/data/career/career_profile.gd`): `profile_id` (text, "fcp_" + 16 hex digits from the seeded `FcRng`; unique within a save, deterministic from the seed, not globally unique; see D-041), `player_id` (world entity), `archetype_key`, `appearance` (small dictionary of choice keys: skin, hair, face; data-driven), `jersey_number`, `stage`, `xp`, `level`, `development_points`, `skill_points`, `reputation`, `currency`, `badges` (owned + equipped), `attribute_ceilings` (derived, stored for audit), `build_version` and `ruleset_version` (which validation rules created and last validated it), `decisions` (log), `history` (seasons: team, stats line, awards), `owner_account` (reserved and unused).
- `FcPlayerBuild` (new, `src/career/player_build.gd`): static validation of a build: name present, position valid, measurements inside the human range and consistent (wingspan vs height, weight vs height), attribute budget, per-attribute floor 25 and cap by physical profile and potential, archetype shape, number of badges. Returns a list of plain-language errors; the same function will run on a server.
- `FcCareerRules` (new, pure): XP, levels, points, costs; every function takes data and returns data (no globals, no randomness except through `FcRng`).
- Money amounts are ints and the `profile_id` is text, never floats (rule 6); serialization is canonical and versioned.

## 5. Proposed files and folders
```
data/career/archetypes.json   build shapes and starting attribute templates
data/career/build_rules.json  attribute budget, floors, ceilings, physical limits, appearance options
data/career/progression.json  XP and level curve, point rewards, costs  (Phase 3)
data/career/badges.json       badge definitions, requirements, capped effects  (Phase 3)
src/data/career/career_profile.gd
src/career/player_build.gd    validation, ceilings
src/career/archetypes.gd      loader
src/career/career_rules.gd    progression math  (Phase 3)
src/game/career_controller.gd (Phase 2+)
src/ui/career_creator.gd, career_hub.gd (Phase 2+)
tests/unit/test_career_*.gd
```
Existing files extended: `game_state.gd` (mode, career section, validation), `version.gd` and `save_migrator.gd` (v2), `app.gd` (menu routing, done), `CLAUDE.md` layout (new `src/career/`).

## 6. Phase breakdown
1. **Player domain foundation** *(done 2026-11-18)*: `FcCareerProfile`, `FcPlayerBuild`, archetypes and build rules data, ceilings, stable `profile_id`, canonical serialization, `MODE_CAREER`, save v2 + migration, tests. No UI.
2. **Character creator** *(done 2026-11-18: form, validation, hub card, save and resume; the league wizard shortcut and portraits are later)*: screens to create, validate, save and reload a player; appearance and jersey; hybrid builds; league wizard shortcut to place the player as a rookie.
3. **Progression** *(done 2026-11-18: rules, data, controller, Develop and Skills tabs; badge effects are applied to the simulation in phase 4)*: XP, levels, development points, attribute allocation under ceilings, badge and skill frameworks, training rewards; deterministic tests.
4. **Career simulation** *(done 2026-11-18 as a first slice: team placement, calendar, games, stats, rewards, history, save and resume, badge bonus in the sim, retirement; role and usage control still open)*: team placement, calendar, games with role control, stats and history, post-game rewards, save and resume; Owner regression with fixed seeds.
5. **Career RPG** *(done 2026-11-18: seeded decisions with real effects and tags, agent-driven contract talks, role and minutes requests the coach can refuse, coach trust and team chemistry, a rival with duels, sponsorships and cosmetic spending)*: agents, contracts, coach relations, chemistry, rivalries, media, endorsements; each decision with a mechanical consequence.
6. **Multiplayer preparation** *(done 2026-11-18 as a document: `docs/CAREER_MULTIPLAYER_READINESS.md`; now deferred and not planned, see section 8)*: audit and document the authoritative-server contract (below); no networking.

## 7. Testing strategy
Deterministic unit tests for every rule (validation boundaries, ceilings, XP/level tables, costs, unlock requirements, badge caps); save/load round trips and a **v1 to v2 migration test**; property-style tests (random valid builds always validate, random invalid builds never do); simulation-integration tests with fixed seeds, including "no flagged player means identical box scores to today"; the full existing suite and click test after each phase; `ui_playthrough` and `economy_check` unaffected (Owner paths untouched); CI runs it all.

## 8. Multiplayer compatibility assessment
**Status (proposed 2026-11-19, awaiting founder approval): deferred, not planned.** Career Mode stays a complete single-player game. Online team play, if built, is a later Dynasty-side track, designed asynchronous or server-simulated first. The notes below only record that Career code does not block it.

- **Ready already:** stable integer ids for world entities; deterministic seeded RNG; headless simulation; versioned saves with checksums; separation of state from UI (screens only call controllers).
- **Added by this plan:** a separate `profile_id` (unique within a save); `build_version`/`ruleset_version` on every profile; pure validation and progression functions that a server can run unchanged; canonical, versioned serialization; an *event-sourced* progression log (XP and points change only through validated events derived from simulation results, never from client claims).
- **Authoritative rules for later:** the server owns match results, XP, points, currency, badge unlocks and attribute changes; a client may only *request* an action (spend a point, equip a badge) and the server re-validates with the same `FcPlayerBuild`/`FcCareerRules`; every request carries `profile_id`, `ruleset_version` and a sequence number; results are signed by the server; a client-submitted match result or reward is always rejected.
- **Gaps to close before online:** account/identity layer, a transport format and server for the simulation (the sim is deterministic, so replays can be verified by re-simulation), anti-tamper for local saves (a local career is never trusted online: an online profile is created or imported only through server validation), and 3v3/5v5 live-play design (the current sim is possession-based and not real-time).
- **Pay-to-win guard:** currency buys cosmetics only; no purchasable XP, points, badges or attributes (project rule).

## 9. Risks and recommendations
1. **One player's impact:** a single player changes game results modestly; without role/usage control the RPG loop feels flat. Mitigation: Phase 4 role and usage inputs, and progression that rewards decisions, not just output.
2. **Shared attribute catalog:** mapping instead of adding attributes keeps Owner stable but limits the creator's vocabulary; revisit with an approved catalog extension later.
3. **`app.gd` size:** keep all Career UI in new files.
4. **Save versioning:** the first real migration; test it before shipping Phase 1.
5. **Balance drift:** badge effects are capped and only apply to flagged players; fixed-seed regression proves Owner Mode is unchanged.
6. **Scope:** 20-season careers multiply simulation time (about 6 s per season at 12 teams, acceptable).
7. **Legal and art:** appearance options are data keys; no real likenesses; AI-generated portraits follow `docs/LEGAL_CHECKLIST.md`.

## 10. Recommended answers used (change any of these)
- Keep the 0-100 shared catalog; career builds validate into 25-99. Do not add attributes now.
- No duplicate player type; a sidecar profile keyed by `player_id` plus a global `profile_id`.
- `DATA_VERSION` 1 to 2 with a real migration step.
- The Career player joins the league as a rookie or free agent; the first journey is one season with automatic offseasons for the rest of the league.
- No control of live games in v1; role and usage choices instead.
- Currency is cosmetic only.
