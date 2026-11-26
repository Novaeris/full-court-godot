# Season calendar and simulation clock

Status: design approved (D-077). This document is filled in as M2, M6, M7, M8 and M9 land. Every section below says which milestone builds it.

## Goals
- One authoritative way to move time forward. Every button on every screen calls it.
- Every game, event, transaction, report and award is processed **exactly once**, even if the game crashes.
- The same seed gives the same league whether the user advances one day at a time, a week at a time or straight to the playoffs.
- Past dates show only what really happened. Future dates show only fixtures and events.

## Building blocks
| Part | Kind | Role | Milestone |
|---|---|---|---|
| `FcSeasonEngine` (exists) | pure | Plays the games of one day (`play_day`, `play_playoff_day`). Builds the playoffs and awards. | – |
| `FcLeagueCalendar` | pure | Turns season data and `data/rules/calendar.json` into dated events: camp, opening night, All-Star, trade deadline, end of regular season, playoffs, finals, lottery, draft, free agency, meeting. | M5/M6 |
| `FcSeasonClock` | pure | `advance_until(target, prefs)` and `_process_day()`, the only place where a day is processed. | M7 |
| `FcSimLedger` | saved data | Keys of everything processed: `game:<id>`, `event:<season>:<kind>`, `txn:<id>`, `report:<season>:<day>`, `award:<season>:<period>:<n>`. | M2 |
| `sim_audit` | saved data | One row per processed day: game IDs, event keys, transaction IDs, standings checksum, RNG fork label. | M2 |
| `FcSimIntegrity` | pure | Checks a state against the integrity invariants below. | M2 |

## Day processing order (M7)
1. Games for the day (regular season or playoffs). Each game checks and marks its `game:<id>` key.
2. Injuries and recoveries.
3. League activity: AI trades during the trade window, injury signings.
4. Calendar events that fall on this date.
5. Period awards and races.
6. The day log (report), keyed `report:<season>:<day>`.
7. Move the date forward.

## Determinism and recovery (decision B)
- **Random numbers.** Each day draws from `rng.fork("day:<season>:<day>")`. It never shares a stream with the UI, so how the days are grouped cannot change their results.
- **Saves.** Saves happen only at day boundaries, using `FcSaveManager.save`, which writes a tmp file, verifies it, then renames it and keeps a `.bak`.
  - Normal: after every stop.
  - Fast and Instant: every 7 sim days, and at the stop.
  - Also after any user transaction.
- **After a crash.** The last good save loads (falling back to the tmp or bak copy if needed). Replaying the lost days gives identical results.

## Integrity invariants (`FcSimIntegrity`, M2)
- Each game ID is played at most once.
- The played games are exactly the scheduled games before the current cursor.
- Standings rebuilt from the results match the stored standings.
- No duplicate ledger keys, transaction IDs, report days or award keys.
- Box-score totals match the team totals.

## Pause rules and speeds (M7)
- **Speeds:** Normal, Fast and Instant. They differ only in what is shown.
- **Pause reasons:**
  - user-team game, playoff game
  - important injury
  - trade or contract offer, important transaction
  - trade deadline, draft, All-Star
  - season transition
  - Career blockers
- **Other teams' games:** "auto-sim non-user games" can be turned off to stop on every day that has games.

## Offseason dates (M9)
- `offseason_stage` stays the state machine.
- The calendar gives each stage a date measured from finals day.
- On offseason days with no games the date still moves forward.
- `start_next_season` runs on camp day.
