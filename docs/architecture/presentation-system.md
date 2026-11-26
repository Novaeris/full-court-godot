# Presentation system

Status: design approved (D-077). Filled in as M1 and the screen milestones land. Builds on the existing design system (D-047, D-057): `FcUiTokens`, `FcUiTheme`, `src/ui/kit/`, `src/ui/shell/`, and the player and team look resolvers.

## Rules
- **Data:** screens get their data from the controller (`FcGameController`, `FcCareerController`) and never call engines directly. Components take plain values or view-models.
- **Styling:** colours, sizes, spacing and motion come from tokens. The style lint (`tests/unit/test_ui_style_lint.gd`) only allows the counts to go down.
- **Actions:** a screen only shows an action the data can fulfil (`FcGameAvailability`, decision D).
- **Motion:** transitions follow `FcMotion` and the reduced-motion setting.

## Composition rule
Each major screen has:
1. **Hero region:** identity or matchup, a full-bleed team-colour band, display type.
2. **Main data region:** the screen's job (table, calendar, chart, board).
3. **Context rail:** related facts and next actions.

Avoid grids of identical cards. Use broadcast-style lower thirds, scoreboard strips and charts where they say more than a table. Each screen's composition spec is listed below as it is built.

## Navigation (M1, built)
- `FcNavigator` has a route registry (`register(id, builder(args))`) and a back stack: `set_root`, `open(id, args)` (push), `replace`, `back_in_stack()` (pop, rebuilding the screen below with its own arguments), `stack_back()` (the Back action a stack screen hands to `enter`), bounded at `STACK_LIMIT` (24).
- `last_motion` / `take_motion()` tell the shell how to animate: `FcScreenHost.transition_in(screen, motion)` fades, and slides 48 px from the right on push and from the left on pop (`FcMotion.nudge_in`, instant with reduced motion).
- The Owner dashboard registers as route `dashboard` and is the root of the Owner stack (`FcApp._register_routes`).
- **Full screens:** Game Center, full-page Player Profile, Calendar, Daily Report, Network, Trade Machine, Draft Night, Bracket, Stat Center, Legacy, Sim Settings.
- **Modals:** the Owner tabs stay; quick looks (the profile modal, confirmations) remain modals.

## Backdrops (M1, built)
`FcScreenHost` draws the mode skin's backdrop. Owner (`FcModeSkin.FRANCHISE`) now uses `franchise`: a team-colour wash from the top edge fading into the night background, plus faint court arcs. It is drawn with vertex colours so it appears on the first frame.

## New kit components (M1, built; gallery section "Season and franchise experience")
| Component | Purpose |
|---|---|
| `FcLineChart` | Trend lines over seasons or days (finances, ratings, standings) |
| `FcHeatZones` | Shot chart by zone or spot |
| `FcCalendarGrid` | Month grid with day cells and event chips |
| `FcScoreboardStrip` | Games of one day: crests and score or tip time |
| `FcNewsCard` | Headline card by importance tier |
| `FcMatchupBanner` | Two-team hero banner |
| `FcTeamHeader` | Franchise hero header |
| `FcResultBadge` | W/L, final or upcoming badge |
| `FcContractBar` | Salary by year with options |
| `FcPlayerCardGrid` | Roster as tiles |
| `FcSimProgress` | Days processed, ticker, pause reason, cancel |
| `FcRaceTable` | Ranked race with trend and gaps |

## Owner tabs
Each of the 13 Owner tabs is built from an `FcOwnerContext` in `src/ui/owner/` (M1 moved Trades, Meeting, Draft, Market, Finances, Staff, News, League and the History records page out of `FcApp` with no change in behaviour). The context carries the controller, message and refresh callables, `after_draft`, `open_tonight`, and `memory` (the last sub-page and the selected trade partner).

## Screen specs
(Each screen adds its hero, main and rail spec here when it is built.)
