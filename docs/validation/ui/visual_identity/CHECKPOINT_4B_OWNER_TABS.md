# Owner redesign, part 2 (Visual Identity Phase F2 to F5)

Date 2026-11-21. Screenshots in `phase_f/owner_<Tab>_1280x800.png` for Finances, Staff, Draft, Market, Trades, Meeting, History, League, News (a real league, 20 days in).

## What changed
- **Every Owner table is now an `FcTable`.** `FcUiTables.table` calls became `FcTable.from_strings` (the same data, sortable, keyboard and mouse, numbers sort as numbers): History, League, News, Finances, Staff, Draft log and board, Market, Meeting, Trades offers, plus the career tabs that used it. No plain Tree is left in the Owner mode, and no ItemList.
- **People get portraits:** the Draft board, free agents, trade assets and the expansion protect list use the player chip (portrait, name) with rating badges; Team Choice at the start of a league shows each team's crest, a best-player badge and a fan-interest bar.
- **Trades and protect lists** used ItemList multi-select: `FcTable` gained a multi-select mode (click or Space toggles, `selected_ids()`), so you pick several players and picks with portraits.
- **Finances** shows where the money came from and went for the latest settled season as two stacked bars (`FcStackedBar`, from the real revenue and expense categories; every segment is also written out with amount and share, so colour is never the only carrier). Chart colours are tokens (`FcUiTokens.CHART`), each at least 3:1 on every surface (tested).
- **Forms:** every OptionButton in app.gd is an `FcDropdown`; the "[x]/[ ]" delegation buttons on the Staff tab are `FcToggle` switches; Release and Fire use the destructive button variant.
- **Tall tabs scroll:** each Owner tab is wrapped in a vertical scroll, so an 800x600 window never clips a tab (the tables had grown taller than the old trees).
- **Table fixes found on the way:** columns are never narrower than their titles and squeeze together in a narrow container; the header clips; an empty `from_strings` table shows one quiet line instead of a big empty state; an empty table lays out its header.

## Existing tests changed (D-058)
Tests that read Trees now read `FcTable` rows (`test_ui`, `test_news`); `tools/click_test.gd` handles both. Layout baselines: `new_league` height 376 to 440 (the pickers are `FcDropdown`). The style baseline for `app.gd` dropped again (sized labels 76 to 69).

## Not done, said plainly
- The New League wizard still uses a grid of dropdowns and `SpinBox`es (themed, working); the extension and offer spinners are still `SpinBox`. A bespoke `FcSpinner`/`FcSelect` was not built because the themed controls already follow the kit's colours, focus rings and touch sizes, and a wrapper would add code without changing what the player sees.
- No new gameplay: the draft lottery reveal, the pick timeline and the trophy shelf from the plan are not built (they need new screens, not a restyle).
