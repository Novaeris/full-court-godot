# Writing sets and tournaments (Creator Studio, D-067)

Creator Studio publishes a folder of JSON files. Sets and tournaments are two more kinds of file in that folder; the Studio validates them
when you press Validate and refuses to publish a release that breaks a rule. Numbers must be whole numbers.

## Sets (`sets/<set_id>.json`)

A set is a named group of cards plus the packs that sell them. The file name must match `set_id`.

```json
{
  "set_id": "winter_holiday",
  "name": "Winter Holiday Set",
  "kind": "timed",
  "starts_at": 1766275200,
  "ends_at": 1767484800,
  "description": "Two weeks only.",
  "card_ids": ["jericho_hale_winter", "ansel_voss_winter"],
  "pack_ids": ["winter_pack"],
  "requires_features": ["set_v1"]
}
```

- `kind` is `permanent` (default) or `timed`. A timed set needs `starts_at` and `ends_at`: **unix seconds, UTC** (use any "unix timestamp
  converter"; 14 days is 1,209,600 seconds). A permanent set must not have them.
- The base set is `"base": true` and permanent. The bundled **Founding Series** is the base set (`sets/founding_series.json`); only one set
  can be the base set.
- **A card belongs to one set only.** A variation of a card is a new `card_id` (a new card file) in a new set; the player file is shared.
- A pack is sold by at most one set, and every card in that pack must be in the same set.
- Cards and packs that are in no set are always available.

### What happens when a timed set ends
- Its packs and cards leave the store (the Store shows "Ends in 3 days" while it runs).
- **Cards players already own stay forever.** Keep the card files in later releases: removing a card file from a release makes players'
  copies show as unavailable.
- Reward packs are not affected: a season or challenge can still give a pack.
- To bring a set back, publish a release where the set has a new `starts_at` and `ends_at`.
- Offline play uses the device clock (so the date can be cheated offline); online play uses the server's clock.

## Tournaments (inside a season file, `seasonal/<season_id>.json`)

Tournaments are single-elimination brackets. They already lived in the season file; two optional fields were added.

```json
{
  "tournament_id": "holiday_cup",
  "name": "Holiday Cup",
  "size": 16,
  "starts_at": 1766275200,
  "ends_at": 1767484800,
  "entry_fee": {"currency": "credits", "amount": 500},
  "teams": [ ...15 teams... ],
  "rewards": {
    "champion": {"credits": 5000, "pack_ids": ["winter_pack"]},
    "finalist": {"credits": 2000},
    "semifinal": {"credits": 1000},
    "quarterfinal": {"credits": 500},
    "early": {"credits": 100}
  }
}
```

- `size` is 4, 8, 16 or 32 (leave it out for the original 8). `teams` must list exactly `size - 1` opponents (you are the last entrant);
  each is `{"name", "abbreviation", "rating"}` (rating 30 to 99) or `{"name", "card_ids": [13 cards]}`.
- Using `size`, `starts_at` or `ends_at` requires the **season** file's `requires_features` to include `"tournament_v2"`.
- `starts_at` and `ends_at` limit when people can **enter**; a run already started can always be finished.
- Rewards by placement: `champion`, `finalist` (lost the final), `semifinal`, `quarterfinal`, and `early` (lost before the quarterfinals,
  only in brackets of 16 and 32). A placement with no reward pays nothing.
- A placement also moves the ranked rating (`tournament_bonus` in `data/dynasty/ladder.json`; `early` pays 0 there).

## Checking your files
Validate in Creator Studio, or from the project: `godot_console --headless --path . --script res://tests/run_tests.gd -- --filter=content`.
