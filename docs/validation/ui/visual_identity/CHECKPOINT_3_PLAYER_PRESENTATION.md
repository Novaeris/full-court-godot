# Checkpoint 3: shared player presentation (Visual Identity Phase E, moved ahead of Owner and Career)

Date 2026-11-21. Screenshots in `phase_e/`: `portrait_sheet_a.png` (96 sample headshots at 56 px, one player at 24 to 128 px, the player family), `portrait_variety.png` (every skin tone by every hair style, the facial-hair options, the full-body stage), `crop_family.png`. Regenerate them with `tools/screenshot.gd screen=gallery section=Portraits` and `section="Portrait variety"`.

## What changed (presentation only: no saved data, no `FcPlayer` field, no DATA_VERSION change)
- **Identity gained derived proportions** (`FcPlayerVisual.proportions`): head width, jaw (round, square, pointed), eye spacing and size, brow weight, nose, mouth (smile, neutral, smirk), an optional headband and a skin warmth shift, all from a hash of the key, never stored and never random. Players with identical skin, hair and face options still look like different people (tested: 30 such players give at least 20 distinct faces). Grey hair is now one colour in twelve (there is no age in a visual, so a grey head on a young face should be rare).
- **A rebuilt procedural figure** (`FcPlayerFigure`): a head outline with a real jaw, ears, eyes with whites and highlights, brows, nose, mouth and cheeks, soft shading with a light from the upper left, a rim light, sleeveless jersey with arms, collar and armhole trim, a headband, a moustache with goatee and beard, and a lit hair highlight. **Detail follows size**: below about 30 px silhouette, hair and jersey; eyes from 30; brows, nose, mouth, ears and shading from 56; rim light, lips and trim from 90, so a small portrait stays clean and is still recognisably the same person. The full-body stage got thicker legs, shoes and shorts trim.
- **Crops:** `FcPlayerPortrait` takes `"bust"` or `"head"` (`FcPlayerFigure.draw_headshot`), used for row portraits.
- **One family of sizes** (`FcPlayerCards`): `FcPlayerChip` (a list row: head, name, detail, rating badge), `FcPlayerTile` (Owner and Career card, 112x160 and 150x214, the same sizes as the Dynasty `FcCardFace`), and the Dynasty cards and the profile for the larger sizes. Owner and Career colour by **rating tier**, Dynasty by **rarity**; the two colour sets are kept apart (D-047).
- Style lint exempts `src/ui/player/` (portraits are drawn art; its four baseline entries were removed).

## Not done on purpose, and why
- **Rarity frame upgrades** (corner ornaments, layered borders) were not changed: the existing `FcRarityStyle` frames (plain, double, bevel, ornate, foil) already differ per rarity with their own patterns and sweep, and re-drawing them is better judged once the Dynasty Hub is redone in Phase H. 
- **Raster art for featured players** (category B) is only specified (`docs/ASSET_SPEC.md`); none was made.

## Verified
`test_player_identity_golden` (9): **50 fixed keys keep their exact faces** (fingerprints in `tests/support/player_identity_golden.json`; regenerate with `tools/build_identity_golden.gd` only after reviewing the contact sheet), faces are varied, proportions stay in range, sizes and crops never change identity (portraits at six sizes x two crops, the stage, the tile and the chip), a Dynasty card of a player has the player's face and a new team changes only the jersey, chip/tile text and tier colour, the family sizes equal the card sizes. The existing identity tests (deterministic, name-independent, team-independent) still pass.

## Reviewed in the screenshots, fixed
- Arms stuck out past the frame and the stage figure looked like a T-pose: shoulders narrowed and arms hang straight down, portraits clip to their frame. Too many grey heads: hair-colour weighting.
- Honest limits: this is stylised flat art. At 128 px the faces read as friendly cartoon people, not photographs; the plan's "approved custom artwork" route (`art_path`) is where hand-made quality comes from for featured players.
