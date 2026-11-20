# Dynasty Mode: audit, plan and progress (started 2026-11-20)

Replaces the old draft's "no packs / paid features" recommendations with the founder's 2026-11-20 assignment: a complete, offline, free-to-play card-collection mode built on the existing simulation and the Creator Studio content pipeline. `docs/DYNASTY_MODE_DRAFT.md` is kept as history.

## Audit (Milestone 0)
**Already implemented and reused**
- Shared content pipeline (`src/content/`): manifest, validator, local store, publisher, loader with fallback, `FcContentCatalog`, `FcContentService` (held by `App.content`). Kinds: player, card, pack, challenge, seasonal, support. Features today: `card_rarity_v1`, `pack_fixed_v1`.
- Simulation: `FcGameSimulator.simulate(home, away, rng)` takes two `FcGameTeam` (lists of `FcSimPlayer`). `FcSimPlayer` already accepts per-player `composite_bonus` (Career badges, reusable for card badges) and `role` inputs (`role_bonus` picks starters, `minutes_pref` shapes the rotation). So Dynasty needs NO simulator change: it builds a `FcGameTeam` by hand.
- `FcPlayer` + `FcDefinitionSet` (28 attributes, tendencies), `FcPlayerRatings` (overall), `FcRng` (seeded, forkable), `FcBadges`, `FcCareerRules.composite_bonus`.
- Save conventions (header + checksum + tmp/bak), UI theme/tables, test runner and `FcContentFixture`.

**Missing**: all Dynasty domain code, saves, UI; content schema for pack odds/prices, card market price, challenges, season, tournaments, economy config, badges and tendencies on players.

**Incompatibilities / gaps in the content schema** (extended compatibly through new `requires_features`; old releases and the bundled starter still load):
| Gap | Extension |
|---|---|
| Packs have only a fixed `card_ids` list | `pack_odds_v1`: `price`, `cards_per_pack`, `odds` (basis points summing to 10000), `guarantees`, `pity` |
| No direct-acquisition price | `card_market_v1`: card `price` {currency, amount} and `acquirable` |
| Players have no badges/tendencies/secondary position/team | optional player fields `secondary_position`, `badges` (Career badge keys), `tendencies`, `team` (checked by the validator) |
| Challenge / season / tournament definitions have no shape | `challenge_v1`, `season_v1` (seasons carry milestones and tournaments) |
| No economy numbers | `dynasty_config_v1`: support definition `dynasty_config` overrides `data/dynasty/economy.json` |
The bundled starter release is a 2-card fallback, far below a 13-card roster, so Dynasty shows an onboarding state until the founder publishes a real release from Creator Studio. Tests use fixtures; nothing official is invented.

## Approach
- **Layers**: records in `src/data/dynasty/`, pure domain services in `src/dynasty/` (no UI), the screen API `src/game/dynasty_controller.gd`, screens in `src/ui/dynasty/`. Screens never edit balances or grant cards.
- **Save**: its own file per profile (`user://dynasty/<slot>.dyn`, `FcDynastyStore`), own version `FcVersion.DYNASTY_DATA_VERSION` and `FcDynastyMigrator`, same checksum/tmp/bak safety. Owner and Career saves (`DATA_VERSION`) are untouched. `FcDynastySession.commit()` runs every state change atomically (undo on failure, undo if the save fails).
- **Identity**: player (content) / card (content edition, `card_id`) / ownership (profile record per card_id with quantity and a history snapshot) / release (provenance). Editions never merge; a card missing from a later release stays owned and shows as unavailable.
- **Simulation**: `FcDynastyMatch` maps the roster to an `FcGameTeam`; the simulator stays unaware of Dynasty.
- **Randomness**: packs/opponents use `FcRng(profile seed).fork(label)`; outcomes are decided only when a pack is opened and are persisted before the reveal.

## Milestones and status
| # | Milestone | Status |
|---|---|---|
| 0 | Audit | done (this file) |
| 1 | Domain foundation (profile, ledger, ownership, roster record, store, session) | done |
| 2 | Content integration (schema extensions, validators, `FcDynastyCatalog`) | |
| 3 | Collection and card presentation | |
| 4 | Team builder | |
| 5 | Simulation integration | |
| 6 | Economy and packs | |
| 7 | Challenges and rewards | |
| 8 | Tournament | |
| 9 | Season and progression | |
| 10 | Hub and UX polish | |
| 11 | Full integration and release validation | |

## Founder decisions taken with recommended answers
See `docs/DECISIONS.md` D-043 to D-046.
