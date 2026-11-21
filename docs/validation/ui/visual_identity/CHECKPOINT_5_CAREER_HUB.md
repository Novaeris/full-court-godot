# Checkpoint 5: Career hub (Visual Identity Phase G)

Date 2026-11-21. Screenshots in `phase_g/`: `career_hub_1280x800.png` (a created player, level 1), `career_menu_1280x800.png`.

## Data check first (decision 6)
`data/career/progression.json` and `src/career/career_rules.gd` already define XP (`xp_for_level = 120 * (level-1)^1.55`, max level 50), level, development points (3 a level, bonus every 5), skill points (one every 2 levels), potential and milestones. The hub shows only those, from `FcCareerController.card()` and `.progress()`. No level, achievement or stat was invented, and nothing in the rules changed.

## What changed
- **A hero panel (`FcCareerHub.hero`, `src/ui/career/`)**: the player large on the showcase stage (the same figure as the profile and every list), overall and potential as big rating badges, archetype and position tags, "Level N" with a gold XP bar (and the text "XP n (x of y to the next level)"), development and skill points, body and team line, the profile button. The old two text lines are gone but every number in them is shown.
- **Card tab:** a radar of the attribute groups (average now as a filled shape, what the player can reach as a gold outline; `FcRadar`, also readable as text in its tooltip) beside the grouped attribute tables (all attributes kept, sortable).
- **Career home:** a panel with a primary "Create a player" button; the developer sentence pointing at `docs/CAREER_MODE_PLAN.md` is removed. The hub footer no longer says games "arrive in the next phase" (they have for a while).
- Plain Godot progress bars in the Develop tab and Dynasty helper became `FcProgress`.
- New: `FcRadar`, `FcCareerHub`, `test_ui_career_hub` (5 tests: the rules' numbers appear, both badges and the XP bar are right, the profile callback, the radar averages and keeps every attribute row, a radar needs three groups and describes itself in words). All 135 existing career tests still pass.

## Not done, said plainly
- The Season, Develop and Skills tabs keep their working layouts (tables, dropdowns, buttons); their tables are `FcTable` already. A history timeline, trophy shelf and achievement banner were not built: the rules produce milestones and history rows but no achievement list to display, and inventing one is out of scope.
- The Career creator's inputs are themed default controls; its preview stage and tabs are already kit.
