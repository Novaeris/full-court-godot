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
The bundled starter release is a 2-card fallback, far below a 13-card roster, so Dynasty shows an onboarding state until the founder publishes a real release from Creator Studio. Tests use fixtures; nothing official is invented. *Historical (as of the first Dynasty milestone): since D-055 the bundled release is the Founding Series (46 cards from 40 original players) and Dynasty is playable from a fresh install; the founder's own content is still to come. Current status: [FEATURE_MATRIX.md](FEATURE_MATRIX.md).*

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
| 2 | Content integration (schema extensions, validators, `FcDynastyCatalog`) | done |
| 3 | Collection and card presentation | done (domain + screens; look not yet judged by eye) |
| 4 | Team builder | done |
| 5 | Simulation integration | done (no simulator change needed) |
| 6 | Economy and packs | done |
| 7 | Challenges and rewards | done |
| 8 | Tournament | done |
| 9 | Season and progression | done |
| 10 | Hub and UX polish | done headless; needs a visual pass in the editor |
| 11 | Full integration and release validation | done headless (see below) |

## Verification (headless) and what still needs human eyes
Verified by automated tests and `./tools/dynasty_check.ps1`: the loop (profile, starter collection, pack opening and reveal, duplicates, direct purchase, lineup, games, challenge progress and claim, tournament, season, save and reload, newer release keeps owned cards). Timings on this machine: 32-card catalog 0.3 s, 1000 pack rolls 0.06 s, a simulated game with save about 25 ms, profile load 2 ms.
NOT verified: how the screens look and feel (card design, spacing, reveal animation timing, text sizes) and mouse/keyboard feel in the real window; please open Dynasty in the Godot editor (F5), try `./tools/dynasty_sample_draft.ps1` for sample content, and tell Claude what to change. Mobile touch layouts, online play and cosmetic effects beyond frame colours are not built. *Historical: mobile touch layouts for Dynasty were built later (UI polish and release validation, checked in a phone-sized window and an emulator, not on a physical device); online play and extra cosmetics are still not built. See [FEATURE_MATRIX.md](FEATURE_MATRIX.md).*

## Founder decisions still needed
- Official content: players, editions, artwork, pack prices and odds, challenges, season and tournament teams, and the `dynasty_config` starter collection (needs at least 13 different players and a lineup-friendly spread of positions).
- The shard and mastery numbers in `data/dynasty/economy.json` (defaults are placeholders for tuning).
- Legal review before any paid feature or any random pack bought with real money (docs/LEGAL_CHECKLIST.md); none is built.

## Founder decisions taken with recommended answers
See `docs/DECISIONS.md` D-043 to D-046.
