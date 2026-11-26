# Owner Mode presentation audit (all 13 tabs)

Date: 2026-11-21. Scope: Release Validation milestone, Phase 5. Owner Mode stays desktop-designed (D6, D-030); the 800 x 600 minimum must hold.
Method: every tab was rendered at 1280 x 800 with `tools/screenshot.ps1` (pictures in `docs/validation/owner_audit/`, league of 8 teams, 20 days played)
and read against: typography and hierarchy, panel spacing, KPI/status presentation, table readability, button consistency, empty states,
confirmation dialogs, hover/focus/pressed/disabled/selected states, horizontal overflow, small-window behaviour. The real-viewport screen matrix
(`tests/live/test_live_screen_matrix.gd`) measured overflow and focus at 800 x 600 up to 2560 x 1080 and three text sizes.

## What was found and fixed

| # | Finding | Where | Fix |
|---|---|---|---|
| 1 | **Two tabs looked open at once.** The tab bar released the other buttons only when the player clicked; every screen rebuild reopens the tab the player was last on programmatically, so "Overview" kept its open look next to the real tab. | All 13 tabs (the tab bar is shared with Career and Dynasty) | `FcTabBar.select` now sets every button's state (`src/ui/kit/tab_bar.gd`). Regression test: `tests/unit/test_release_fixes.gd`, and the live matrix. |
| 2 | **The action row (Next Day ... Main Menu) did not wrap.** At Large text it needed 844 px, so the whole dashboard was wider than an 800 px window (D6 broken at Large text). The old minimum-size probe could not see it; the real-viewport matrix did. | Owner dashboard header, every tab | The row is now an `HFlowContainer` (`src/ui/app.gd`): the buttons wrap onto a second line. |
| 3 | **Empty tables were a big blank box under the column titles** (Finances "Your seasons", Draft, Meeting, History's records, Market's latest draft, Hall of Fame). It looked broken. | 7 tabs | Every empty table built by `FcUiTables.table` now shows a muted "Nothing to show yet." under its titles. |
| 4 | Buttons with a short label ("X") were narrower than a finger (37 to 41 px). Found on the Dynasty lineup; the shared button is also used on Owner screens. | `FcButton` | Minimum width equals the minimum target size (32 px desktop, 44 px touch). |

## Reviewed and left as they are (intentional legacy presentation)

| Area | State | Why it stays |
|---|---|---|
| Tables | Superseded: Owner tables now use the kit `FcTable` (sortable, custom cells). The rest of this audit is historical; the current plan for these screens is docs/roadmap/franchise-experience-overhaul.md (D-077). | – |
| Staff toggles | "[ ] Re-sign my players" style toggle buttons | Works, is keyboard reachable, shows state in text. A kit `FcToggle` would look better and is a candidate when the Staff tab is next touched. |
| Text-heavy panels | Overview "League rules", Finances and Staff paragraphs are plain labels | They are information, not controls. A KPI strip already leads the Overview. More KPI strips (Finances, Roster) are a good next step, not a defect. |
| Hierarchy | Heading (Barlow Condensed, accent colour) > body (Inter) > muted notes | Consistent on all 13 tabs. |
| Confirmations | Destructive actions (release player) show the existing confirmation flow; leaving a game to the menu uses `FcModal` | Unchanged. |
| Disabled/hover/focus/pressed/selected | Come from the shared theme for every button, tab and table row | Verified by the contrast and keyboard-reach audits (Phase 12) and the new focus-style check. |

## Frequently used screens, in order of priority

Overview, Roster, Finances, Market and Schedule are used every session. All five were checked at 1280 x 800 and at 800 x 600 (after fixes 1 and 2
nothing is clipped at any text size). The older tables (Roster, Schedule, Standings) are dense but readable; the biggest remaining polish would be
KPI strips on Finances and Roster (not done: it is a redesign, not a fix, and Owner Mode is not the mobile target).

## Not done on purpose

- No gameplay action was changed; the screens call the same controller methods.
- No Owner screen was rewritten to use more of the component kit.
