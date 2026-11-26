# Franchise Experience Overhaul: validation record

Evidence for each milestone of [the programme](../roadmap/franchise-experience-overhaul.md).

- **Test totals** are in [TESTING.md](../TESTING.md) only.
- **Pictures** live in `docs/validation/franchise/` (that folder has a `.gdignore`):
  - `before/`: the code before the programme (commit `37d86a9`), at 1280x720 and 1920x1080
  - `after/`: the final state (M16)
  - one folder per milestone for its own screens

## Visual review checklist (applied to every new or redesigned screen)
| Check | Pass condition |
|---|---|
| Hierarchy | One clear hero. The eye reaches the most important number first. |
| Identity | Team colours, crest and wordmark where the screen belongs to a team |
| Density | No large empty areas at 1280x720. At 1920x1080, content uses the width up to the 1600 px maximum. |
| Spacing and type | Token spacing only. At most 3 type sizes per region. |
| States | Hover, focus, selected, disabled and empty states all present |
| Motion | Screen, tab and selection transitions; reduced motion respected |
| Resize | Viewport audit passes from 800x600 to 2560x1080 at 3 text sizes; no overflow |
| Honesty | No invented data. Future dates show no results. Actions match the stored data. |

## Milestone records
### M0
- **Before pictures:** `franchise/before/`. 19 screens at 1280x720 and 1920x1080 (menu, the 13 Owner tabs, Owner game day, post-game, replay, Career hub, Dynasty hub).
