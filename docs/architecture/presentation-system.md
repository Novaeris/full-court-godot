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

## Navigation (M1)
- `FcNavigator` gains a registry (screen id to builder) and a back stack for full screens.
- **Full screens:** Game Center, full-page Player Profile, Calendar, Daily Report, Network, Trade Machine, Draft Night, Bracket, Stat Center, Legacy, Sim Settings.
- **Modals:** the Owner tabs stay; quick looks (the profile modal, confirmations) remain modals.

## New kit components (M1)
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

## Screen specs
(Each screen adds its hero, main and rail spec here when it is built.)
