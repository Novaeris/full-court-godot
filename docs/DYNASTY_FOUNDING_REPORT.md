# Dynasty initial content: the Founding Series (D-055)

2026-11-21. How the first complete Dynasty release was made, what it contains and what was verified. Source of truth: `tools/dynasty_founding_content.gd` (data),
`tools/build_starter_content.gd` (builds through `FcDraftWorkspace` -> `FcPublisher`, the same code Creator Studio uses, with a build-tool approval record),
output `data/content_starter/` (release `fcr_2036b76f032b29c4`). Nothing was hand-edited after publishing, and no validation was bypassed.

## Contents

| Part | Count / detail |
|---|---|
| Players | 40 original invented players, 8 per primary position (PG, SG, SF, PF, C); 33 have a secondary position; 16 play styles (floor general, pest guard, sharpshooter, slasher, three-and-D, rim protector, glass cleaner, stretch big...), each with its own attribute shape, badges and tendencies |
| Cards | 46: 40 "Founding Edition" base cards + 6 extra editions with attribute overrides (Lockdown, Corner, Enforcer, Pace-and-Space, and two Anniversary) |
| Rarity | common 10, uncommon 10, rare 10, epic 11, legendary 5. Game overall: common 47-52, uncommon 56-60, rare 65-68, epic 67-76, legendary 81-85 |
| Starter collection | 15 cards (10 commons + 5 uncommons), at least 3 per position, team overall 56, 2,000 credits and 5 tokens |
| Packs | Starter (fixed 15), Rookie (500 credits, 3 cards, guarantee: 1 uncommon+), Pro (1,800 credits, 4 cards, 1 rare+), Elite (8 tokens, 5 cards, 2 rare+, pity: epic every 5th), Reward (free, 2 cards, used as challenge reward). Odds add up to 10,000 in each |
| Market | Every common (500 credits), uncommon (1,200) and rare (3,500) base card; epic and legendary come only from packs and rewards |
| Challenges | 14 across all seven categories (scoring, shooting, playmaking, defense, rebounding, team composition, collection), rewards in credits, tokens, shards and packs |
| Season | "Founding Season": 4 milestones (20/50/90/140 points), 2 objectives, all 14 challenges, 2 tournaments: Founders Cup (200 credits, rival ratings 52-70) and Pro Invitational (2 tokens, ratings 64-82) |
| Not changed | Economy defaults (`data/dynasty/economy.json`), pack mechanics, simulation, save formats, the publishing contract |

## What was verified (all through `FcContentService` / `FcDynastyController`, as a fresh install does)

`./tools/dynasty_initial_check.ps1` and `tests/unit/test_dynasty_founding.gd` (6 tests):

1. The empty content folder falls back to the bundled release, and the release is playable (13+ players, legal starting five).
2. All 5 positions and all 5 rarities are present; mean overall rises with every rarity step and legendary is 25+ points above common.
3. A new profile receives the 15 starter cards, a valid automatic lineup and a full 13-slot roster (5 starters, 7 bench, 1 reserve).
4. Published odds add to 10,000; over 200 seeded rolls every Elite Pack held two rare-or-better cards, and a pack that is due for pity always held an epic or better.
5. A duplicate (found by opening Rookie Packs) converts to shards; the pack purchase, challenges (11 claimed after 12 easy games), milestones and both tournaments (entered, played to a placement, rewards paid) complete.
6. Save, close, reopen: cards and credits identical.
7. On the Android emulator the same release loads from the APK and a profile survives an app restart.

## Not verified / open

- Mastery application, the Market purchase flow, Lineup editing with secondary positions through the screens (covered by older unit tests with the test fixture, not re-walked with this release by hand).
- Balance feel over many hours: the economy was deliberately not tuned. In the 12-game check an even team won 8 of 12 easy games and placed quarter-final in both tournaments.
- An existing profile created on a different release: `FcDynastyOnboarding.sync_release` handles it (unit-tested with the fixture), not tried with a real old profile.
- The names are invented but not checked against any database (legal review).
