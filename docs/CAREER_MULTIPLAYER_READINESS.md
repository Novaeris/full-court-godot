# Career Mode: multiplayer readiness audit (phase 6)

Status 2026-11-18. An audit of what exists, what a future online mode will need, and the rules a server must enforce. **No networking, accounts or server code exists or is proposed to be built without the founder's approval.** Written against the code as it stands after phases 1-4 (`docs/CAREER_MODE_PLAN.md`).

## 1. What is already online-ready (and where)
| Requirement | State | Where |
|---|---|---|
| Stable player identity | Done. `FcCareerProfile.profile_id` ("fcp_" + 16 hex digits) is globally unique, seeded, never reused, separate from the per-save integer `player_id` | `src/data/career/career_profile.gd` |
| Explicit data ownership | Done. The profile has `owner_account` (empty until accounts exist); a career profile belongs to one account, the world belongs to one save | same |
| Versioned serialization | Done. Save data version 2 with a tested migration step; `build_version` and `ruleset_version` on every profile; `schema` on each record | `src/core/version.gd`, `src/save/save_migrator.gd` |
| Validated player builds | Done. `FcPlayerBuild.validate(spec, defs)` is pure, never throws on garbage, returns plain-language errors; the creator only sends a build that passes | `src/career/player_build.gd` |
| Same attribute definitions offline and online | Done by construction: one shared catalog (`data/definitions/attributes.json`) and one rules file (`data/career/build_rules.json`) | `data/` |
| State separate from UI | Done. Career rules and the controller never touch UI nodes; screens call `FcCareerController` | `src/game`, `src/career` |
| Deterministic simulation | Done. Seeded `FcRng`, headless sim, whole careers replay to a byte-identical profile (tested) | `src/sim`, `tests/unit/test_career_season.gd` |
| Progression only through rules | Done. XP, points, currency, badges and attributes change only through `FcCareerRules` functions fed by simulation results; the UI has no setter for them | `src/career/career_rules.gd` |
| Tamper fingerprint | Partial. `FcCareerProfile.checksum()` (SHA-256 of the canonical JSON) lets two copies be compared | profile |

## 2. The authoritative server contract (future)
The server is the only party that may change a profile. A client may only **request** actions.
1. **Identity.** Every request carries `profile_id`, `ruleset_version`, the client's last known profile `checksum`, a monotonically increasing sequence number and an account token (not designed yet).
2. **Allowed requests** (the server re-runs the same functions): create a profile (`FcPlayerBuild.validate` then create), raise an attribute (`FcCareerRules.raise_attribute`), unlock or equip a badge (`unlock_badge`, `set_badge_equipped`), spend currency on cosmetics (cosmetics only), queue for a match.
3. **Never accepted from a client:** XP, development or skill points, currency, attribute values, badge ownership, match results, statistics, milestone claims. A request containing any of these is rejected and logged.
4. **Results.** The server simulates the match (the simulation is deterministic and headless), derives the box score, and calls `FcCareerRules.apply_game` itself. Because the sim is deterministic from a seed, a replay can be re-simulated to audit any disputed result.
5. **Sequence and replay protection.** A request with a stale checksum or a repeated sequence number is rejected (the same idea as `_seen` box keys that stop a game paying twice offline).
6. **Local careers are never trusted online.** An offline career is imported only by sending its build to the server, which validates it and recomputes progression from the stored event log; a locally edited save cannot gain anything online.
7. **Event-sourced progression (recommended before online).** Today the profile stores the running totals. For online, every grant (game, training, milestone) should also be appended to an event log with its inputs, so a server can rebuild a profile from events and detect drift. This is a small additive change to `FcCareerRules` (return the event, not only mutate), listed under open work.

## 3. Gaps to close before any online mode
1. **Accounts and authentication**: nothing exists. Needs a privacy policy and age rules first (`docs/LEGAL_CHECKLIST.md`, section 5).
2. **A transport and a server**: a headless Godot or a separate service that runs `FcGameSimulator` and `FcCareerRules`. The code is already headless; the work is the network layer, matchmaking and persistence (a database).
3. **Live play design**: the simulation is possession-based and not real time. 3v3 and 5v5 live matches with friends need either (a) turn or tactic-based matches simulated by the server (fits the existing engine, recommended first) or (b) a real-time engine (a new product).
4. **Squads and friends**: a social graph, invitations, private matches. All new.
5. **Anti-cheat and moderation**: rate limits, report tools, name filtering for the creator's free-text fields (`first_name`, `last_name`, `country`).
6. **Event log for progression** (section 2, item 7).
7. **Role/usage choices** (phase 4 open item) must be part of the validated request set.
8. **Currency design**: cosmetic-only currency, never purchasable XP, points, badges or attributes (project rule: no pay-to-win; `docs/LEGAL_CHECKLIST.md`, section 3 for random items).
9. **Rankings and seasons**: how an online season relates to the offline 20-season career (recommended: online uses its own capped "season" ladders; the offline career is separate; both use the same build and progression rules).

## 4. Risks
- **Shared catalog drift:** if the attribute catalog or ratings change, old online profiles must be re-validated under `ruleset_version`; keep versions and write a migration for every change.
- **Balance online:** badge bonuses are capped at +4 per composite, but ranked play needs its own balance pass.
- **Free text:** names and countries are free text today; online needs filtering.
- **Clock and randomness:** the server must be the only source of seeds; a client-chosen seed would let a client pick favourable results (offline, `on_create_career` uses the clock for the league seed, which is fine locally and must not be used online).

## 5. Recommendation
Keep building the single-player Career Mode (phase 5 is next), add the event log to `FcCareerRules` when the career RPG systems are in (it is cheaper then), and start online work only after the founder approves: accounts and privacy first, then a server that runs the existing rules, then asynchronous squad play before any live match mode.
