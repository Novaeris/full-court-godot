# Integration audit (Phase 1)

Date: 2026-11-21. Baseline commit: `dcfbd4f`. Scope: do Owner, Career and Dynasty (and Creator Studio's content) agree on identities,
definitions, position rules, rating calculations and content references, and do the modes hand over to each other cleanly?

How to read it: **Verified** = checked, with the test that keeps it true. **Fixed** = a defect was found and corrected in Phase 1.
**Open** = known, not changed (with the reason). Test totals are NOT repeated here; see [TESTING.md](TESTING.md).

## How the modes share identity (the design as audited)

- Owner and Career use the canonical `FcPlayer` (`src/data/player/player.gd`), kept in `FcWorld` and referenced by integer ID. Career's
  `FcCareerProfile` stores only the `player_id`.
- Dynasty does **not** keep `FcPlayer` objects. It keeps published player definitions and card editions (JSON in a content release) and,
  when a game is played, `FcDynastyCatalog.make_player` builds throwaway `FcPlayer` instances for the simulation. Profile saves hold card
  IDs, counts and display snapshots only. This is intentional (D-043 to D-046), so the audit checks that the two paths agree on
  **definitions, position rules and rating calculations**, not that one instance is shared.

## Findings

| # | Finding | Status | Evidence |
|---|---|---|---|
| 1 | One attribute/tendency definition source (`data/definitions/`). Every attribute and tendency key in the bundled player files, the generation position profiles, the Career archetype bonuses and the badge requirements exists in it. | Verified | `test_attribute_keys_in_every_data_file_exist_in_the_definitions` |
| 2 | One rating calculation. Every mode uses `FcPlayerRatings.load_default()`; a Dynasty card's displayed overall equals the shared rating of the player built from it; the rating survives the `FcPlayer` save round trip; an Owner-generated player given a card's attributes rates identically. | Verified | `test_dynasty_players_are_rated_by_the_same_calculation_as_owner_players`, `test_a_dynasty_player_and_a_generated_player_with_equal_attributes_rate_equally` |
| 3 | Position rules were copied in five places (`FcPosition.ABBREVIATIONS`, `FcContentValidator.POSITIONS`, `FcDynastyContentRules.STARTER_POSITIONS` plus an inline list in `check_player`, and the Dynasty collection filter). Only one pair was cross-checked. | **Fixed** | New `FcPosition.PLAYABLE`; the others now reference it. `test_every_position_list_is_the_one_in_fc_position` |
| 4 | Cards keep their published primary and secondary positions when built into players; the secondary is never the primary. `secondary_position` is validated by `FcDynastyContentRules.check_player` (an earlier note that it might not be was wrong). | Verified | `test_dynasty_card_players_keep_their_published_positions` |
| 5 | Badges have one source (`data/career/badges.json` through `FcBadges`), which Dynasty content validation also uses. Badge effects name real rating composites, prerequisites exist, and every badge on a bundled card exists. | Verified | `test_badges_name_real_composites_and_prerequisites` |
| 6 | The bundled Founding Series passes the shared release validator, and every reference in it resolves (card to player, pack to cards, challenge reward to cards, starter pack, active season). | Verified | `test_the_bundled_release_passes_the_shared_validator`, `test_every_reference_in_the_bundled_release_resolves`, plus `test_dynasty_founding.gd` |
| 7 | Dynasty economy: defaults live in `data/dynasty/economy.json`; a release's `dynasty_config` overrides key by key (`FcDynastyConfig.build`). Override keys must be a known default, a release field or a `starter_*` setting. | Verified | `test_the_economy_has_one_authoritative_source_per_key` |
| 8 | Active-release loading, fallback to the bundled starter, damaged and cyclic release chains, and rollback. | Verified (already covered) | `test_content_loader.gd` |
| 9 | Invalid releases are rejected: bad checksum, tampered or unlisted files, unsafe paths, unsupported features, newer schema; dangling references (card to missing player, pack to missing card, reward to missing card). | Verified | `test_content_format.gd`, `test_dynasty_content.gd`, `test_dangling_references_are_rejected_by_the_shared_validator` |
| 10 | A profile whose roster holds a card that a newer release no longer has: the lineup reports "not in the current content release", play refuses to start (`FcDynastyPlay` checks `FcDynastyLineup.problems` first), and the match builder skips the card rather than crashing. | Verified | `test_a_roster_card_missing_from_the_release_is_reported_and_skipped_safely` |
| 11 | Mode hand-over in the real app: menu, Owner, menu, Career, menu, Dynasty, menu. Each keeps its own state; Owner and Career saves share `FcSaveManager` and a Dynasty profile never appears there; loading each save opens the right mode with the same team or player; Continue opens the newest save. All paths use scratch folders. | Verified | `tests/live/test_live_mode_transitions.gd` |
| 12 | `FcDynastyCatalog.make_player` splits a card's display name on the first space (one word becomes first name plus "-"). Identity is display-only in Dynasty and does not affect the simulation. | Open (accepted, low) | Revisit if a content name needs a different split; Creator Studio could publish first and last names separately. |
| 13 | Nothing warns a content author when a new release removes a card that players may own. Owned cards survive as placeholders (`available: false`) and the lineup check covers the roster, but Studio gives no publish-time warning. | Open | A design decision for the content pipeline; not a defect. Raise with the founder before Phase 5. |
| 14 | Career is not part of `--selftest` (`FcApp._run_self_test` covers Owner and Dynasty). | Open (low) | The Career flow is covered by `test_career_season.gd`, `tools/career_playthrough` and the live transition test. |
| 15 | `on_continue` lists only Owner and Career saves; Dynasty profiles have their own store and entry screen. | By design | Documented; the live test pins it. |
| 16 | The live runner logs 2 engine errors ("Lambda capture at index 0 was freed") that are counted as non-failures. They predate Phase 1. | Open | Find the test that frees a node while a lambda still holds it. |
| 17 | Dynasty simulation IDs are synthetic (user slots 1-13, opponent 101+) and map back to `card_id` through a map that is never saved. Owner and Career boxes use real `FcPlayer` IDs. | By design | A fact for Phase 2: any event log or replay must carry that map. |

## What was not covered

- Cross-checking `data/career/events.json` and `data/career/progression.json` against the definitions and badges (not examined in Phase 1).
- Mobile and device behaviour (manual validation, see `DEVICE_VALIDATION.md`).
- Saved-data changes: **none** were made in Phase 1, so no version bump or migration was needed.
