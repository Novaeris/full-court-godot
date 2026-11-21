# Checkpoint 1: design system and component gallery (Visual Identity Phase B)

Date 2026-11-21. Screenshots in `phase_b/` (Component Gallery, 1280x800, 1920x1080 and 800x600): `gallery_colour_*`, `gallery_table_*`, `gallery_states_*`.

## What changed
- **Tokens (D-057):** Court Orange `#FF8A24`, Championship Gold `#FFB547`, Electric Blue `#39A9FF`, Court Slate `#17233D` adopted because every text/surface pair still passes 4.5:1; `SURFACE_HIGH #202F4D` and `PRIMARY_DEEP #E65300` added. Found by the new fourth surface: STEEL and DANGER failed 4.5:1 on it, so both were lightened (`#7C9DCB`, `#F5726F`), the franchise skin accent is now ensured against `SURFACE_HIGH`, and the disabled-text colour was lifted to `#6A7791`.
- **FcTable** (`src/ui/kit/table.gd`, `table_row.gd`, `mini_bar.gd`): virtualised (about 14 row controls whatever the length), sortable headers (stable, blanks last, numbers start high to low), selection kept across refresh by row id, keyboard (arrows, PageUp/Down, Home/End, Enter), mouse and double-click, ellipsis with tooltip, cells for text, number, rating badge, mini bar and any control (player portrait in the gallery), empty state, and the touch card stack. `FcDataTable` and the `Tree` path are untouched until each Owner tab migrates.
- **States:** `FcEmptyState.error()` / `.success()`, new `FcSkeleton` (pulses, still under reduced motion), all in the gallery.
- **Deferred on purpose:** the form controls (`FcSpinner`, `FcSelect`, `FcListPicker`, `FcPickerModal`) arrive in Phase F/H with the first screen that needs each, as the plan says ("each only when its screen needs it").

## Prototype gate (plan 5.1), measured headless on this machine
| Gate | Result |
|---|---|
| 400 rows: build / scroll step / sort | 4.2 ms / 0.24 ms / 3.2 ms (budget 150 / 4 / 60) |
| 1,000 rows: build / scroll step / sort | 4.7 ms / 0.23 ms / 6.8 ms |
| Row controls for 1,000 rows | 14 |
| Sorting, selection, keyboard, scrolling, ellipsis, touch fallback, empty state, focus outline | covered by `test_ui_table` (10) and `test_live_table` (10), all passing |
| Portrait / crest cells at 44 px | portrait works (screenshot); crests arrive with Phase C |
**Decision: go.** The fallback (themed `Tree` with icon columns) is not needed.

## Reviewed in the screenshots, fixed
- Sample names repeated in the first rows: made varied. Touch card stack showed an empty title from the portrait column: cards now skip picture columns and use the first text column as the title.
- Not verified: scrolling feel with a real mouse wheel or touch drag (headless), hover/tooltip look. These are on the manual list for Checkpoint 7.
