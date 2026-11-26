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
| Ledger (`FcGameState.ledger`) | saved data | Keys of everything processed besides games (a game's `played` flag and id are its own record): `event:<season>:<kind>`, `report:<season>:<day>`, `award:<season>:<period>:<n>`. | M2 |
| Audit (`FcSeason.day_log`) | saved data | One entry per processed day: game ids, injuries, returns, event keys, transaction ids, standings checksum. | M2 |
| `FcSimIntegrity` | pure | Checks a state against the integrity invariants below. | M2 |

## Data foundation (M2, built; save data version 5)
| Data | Where | Kept |
|---|---|---|
| Stable game id | `FcScheduledGame.id` (`FcIdGenerator` kind `"game"`), assigned when the schedule is built and when each playoff game is created | always |
| Compact result line | `FcScheduledGame.line`: periods, the three best scorers of each team (`[player, pts, reb, ast, team]`), player of the game | while the season is held in detail (current and previous season) |
| Day log | `FcSeason.day_log[day]`: `g` game ids, `i` new injuries, `r` returns, `c` standings checksum (regular season), `e` event keys and `t` transaction ids (filled by the clock, M7) | while held in detail |
| Game logs | `FcSeason.game_logs[player]`: one row per game for the watched team's players and the Career player | current season (archived with the season) |
| Starts and shots at the rim | `FcSeasonStats` extra columns `gs`, `rim_m`, `rim_a` (not copied into career rows); counted by the simulator without drawing any random number, so results are unchanged | season |
| Followed games | `FcSeason.followed` (ids, max 20) and `followed_boxes` (box score and play-by-play) | while held in detail |
| Transactions | `FcWorld.transactions` (`add_transaction`): id (kind `"txn"`), date, kind, text, team, other team, players; its news item carries `txn` | last 3,000 |
| Rating history | `FcWorld.rating_history[player]`: `[year, overall, potential]` at every season's end | always |
| Jersey numbers | `FcPlayer.jersey_number`, kept valid by `FcRosterNumbers.ensure_all` after roster changes and on load | always |
| Owner objectives | `FcGameState.owner_objectives[year]` (`FcOwnerObjectives`): set at season start, judged at season end | always |
| Sim preferences | `FcGameState.sim_prefs` over `DEFAULT_SIM_PREFS` | always |
| Ledger | `FcGameState.ledger`: processed keys and the date they were processed (`ledger_mark` refuses a second time) | always |

Shot charts show the three shot kinds the simulation actually decides (at the rim, mid-range, three). Exact court spots are not simulated, so drawing them would invent data. A finer spot model would be a simulation change and is recorded as a limitation (D-077).

`FcGameAvailability.capabilities(season, game, user_team, next_user_game)` is the single rule deciding which game actions a screen may offer (the table in the roadmap, decision D).

The v4 to v5 migration (`FcSaveMigrator._v4_to_v5`) does three things:
- gives every stored game an id from the world's counter, season by season;
- links each stored box score to its game;
- leaves everything else empty, so no history is invented. Numbers are given out on load, and objectives are set for the current season on load.

It is tested on a real v4 save (`tests/fixtures/save_v4_owner.sav`, written by `tools/make_save_fixture.gd`).

## Day processing order (M7)
1. Games for the day (regular season or playoffs). A game is played only while its `played` flag is false (its id identifies it everywhere).
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
