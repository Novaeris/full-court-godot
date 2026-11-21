# Checkpoint 6: Dynasty polish and Creator Studio restyle (Visual Identity Phase H)

Date 2026-11-21. Screenshots in `phase_h/`: `dynasty_hub_1280x800.png`, `dynasty_lineup_1280x800.png`, `creator_studio.png`.

## What changed
- **Bracket (`FcBracket`)**: the Dynasty tournament bracket is drawn as columns of match boxes joined by connector lines (a later match sits between the two that feed it), the winner marked with a check and the loser dimmed, the score, and an accent edge on your own match. Everything is also text (`summary()`, tooltip). On a phone it is a stack of match panels (checks in text), on a narrow desktop window the drawing scrolls sideways. It draws only the rounds `FcDynastyTournament.bracket_view` gives it.
- **Lineup picker**: the default Godot dialog with a Tree is now a kit dialog (`FcModal`) holding an `FcTable`: each candidate card as a portrait chip with its edition, position, an overall badge, the difference against the current player, and the key composite ratings; double-click or "Choose selected player". Deleting a Dynasty team now uses the kit's destructive confirm (focus starts on Cancel).
- **Progress bars** in Dynasty helpers are `FcProgress`.
- **Creator Studio** (same kit as the game): the Novaeris mark and a "A Novaeris tool" credit, kit buttons (primary for Check, Create and Approve and publish), type scale and headings from the tokens, and **read-only card previews**: the selected draft's cards are drawn with the game's own `FcCardFace` (up to eight), so a creator sees how a card will look. Previews only read the draft's `cards/` and `players/` files; nothing is written. **No authoring editors were added** (as agreed). The theme gained ItemList styling (surface, border, accent selection), which also fixes the grey default lists in the Studio.

## Verified
`test_ui_bracket` (6): match count and size, later matches sit between their feeders, words for every match, empty bracket, touch layout gives panels with checks and scores. Creator Studio smoke (`studio_smoke.gd`) passes (create, fail, fix, approve and publish twice, roll back, read back with the game's loader). Full unit and live suites pass.

## Not done, said plainly
- The Dynasty hub, collection, packs and market keep their current layouts: they were already the strongest screens (rarity frames, flip, pack reveal). A seasonal banner, progress rings and a reward claim animation are left for the animation pass or later; an Owner-mode playoff bracket was not drawn (the season engine's series are not exposed as a bracket view and building one is new logic, not a restyle).
- The Studio is unchecked with a real mouse on a second monitor; only the headless smoke run and one screenshot were done.
