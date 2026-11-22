# Basketball data integrity matrix (Stage 2)

Who owns each piece of player, team, roster, uniform and statistical data, who reads it, and where it is duplicated or can drift. Evidence is a file and line; items marked **[R]** were reported but not opened line by line in this audit. Findings (S2-*) are in [BASKETBALL_AUTHENTICITY_AUDIT.md](BASKETBALL_AUTHENTICITY_AUDIT.md).

## Player
| Field | Source of truth | Consumers | Duplication or drift |
|---|---|---|---|
| Player id | `FcIdGenerator` (`world.ids`), stored on `FcPlayer.id` (`player.gd:20`) | every system by id | Dynasty simulation uses synthetic ids mapped back to cards (`dynasty_match.gd`) **[R]**; Career profile stores `player_id` |
| Name | `FcPersonIdentity` (first, last, nickname) via `FcNameGenerator` | tables, box scores, news, replay text | Box scores copy the name at game time (`season_stats` lines hold "name"); no duplicate full names inside a league (measured) |
| Birth date, age | `FcPersonIdentity.birth_date`; `FcPlayer.age_on(date)` (`player.gd:46`) | rosters, scouting | derived, no copy |
| Country (nationality) | `FcPersonIdentity.country` | profile | none found |
| Height, weight, wingspan, handedness | `FcPlayerPhysical` (150-250 cm, 50-200 kg, validated) | roster tables, composites, visuals | Visual resolver may re-derive build from a hash when physical data is absent (`player_visual.gd`) |
| Positions | `FcPlayer.primary_position`, `secondary_position` (`FcPosition.Id`, never renumbered) | simulation lineups, Dynasty slot rules, UI | Dynasty uses its own five slot names mapped from `FcPosition.PLAYABLE`; one list |
| Archetype / attributes | `FcAttributeSet`, Career `archetype` id | composites, UI | Career archetype stored on the profile as well as derived attributes |
| Jersey number | **none for league players.** Career: `FcCareerProfile.jersey_number` | Career hub title (`app.gd:580`), visuals | **Three unrelated notions**: Career chosen number, hashed `jersey_for` (retired banners), `0` in view models. Collides in 13.3% of teams (measured). S2-JER-1 to 4 |
| Draft year / class | **none on the player** | n/a | S2-PLY-2 |
| Status, injury | `FcPlayer.status`, `games_out`, `injury` | simulation availability, UI | `world.injury_history` keeps past injuries separately |
| Visual identity | `appearance` dictionary on Career/Dynasty subjects; otherwise derived by hash from a key (`player_visual.gd`) | portraits, figures | For league players the look is a hash, not stored; stable by key |

## Team and franchise
| Field | Source of truth | Consumers | Duplication or drift |
|---|---|---|---|
| Team id | `FcIdGenerator`; `FcTeam.id` | everything by id | stable across seasons |
| Name, abbreviation | `FcTeamIdentity` (nickname, abbreviation 2-4 upper) + city name | tables, scorebug, news | box scores copy abbreviations at game time; unique in measured leagues (guard recommended, S2-TEAM-2) |
| Colours, logo | `FcTeamBranding` (primary, secondary, accent hex, `logo_key`) | `team_look.gd`, `uniform_preview.gd`, crests | contrast not validated (S2-TEAM-1) |
| Arena | `FcArena` via `FcTeam.arena_id` (name, capacity, year built) | owner finances, UI | unique names in measured leagues |
| Conference / division | `FcLeague` structure | schedule, standings, rivalries | validated by `FcLeague.validate` |
| Franchise history | derived from `world.careers` and season records (`FcFranchiseHistory`) | History screens, storylines, legacy | season-level "last team" (S2-HIS-1); retired numbers derived, cached by year |

## Roster, contract, transaction
| Field | Source of truth | Consumers | Duplication or drift |
|---|---|---|---|
| Roster membership | `FcTeam.roster.player_ids` (max from league rules via `roster.max_size`) | simulation, UI, validation | the contract also names a team (`FcContract.team_id`); `FcWorld.validate` requires they agree |
| Roster limits | `FcLeagueRules.roster_min/max` (13/15 default) | `trade_desk.gd`, `game_controller.gd` signing/release, offseason | `max_size` is copied onto each `FcRoster` in 4 places (`world_generator.gd:164`, `expansion.gd:163`, `offseason.gd:607`, `owners_meeting.gd:321`) **[R]**: a rules change must update the copy |
| Contract | `FcContract` (+ years, bonuses) | cap, payroll, trades | one active per player (validated) |
| Transactions | `FcGameController` (user), `FcTradeDesk`, `FcTrades` (AI, offseason), `FcOffseason`, `FcExpansion` | | pre-validated; see audit section 3D |
| Lineup / starters | derived by the simulation from rosters and coach settings; recorded as `EV_STARTER` rows | game-day preview, replay | preview shows "the same five the game starts" (feature matrix) |

## Uniform and equipment
| Field | Source of truth | Consumers | Duplication or drift |
|---|---|---|---|
| Uniform colours | **derived from `FcTeamBranding`** in the UI | `uniform_preview.gd`, `player_figure*.gd` | no home/away/alternate data; no per-kit validation |
| Number on uniform | view model field `jersey` (0 for league players and cards) | `uniform_preview.gd` | see Jersey |
| Name on uniform | player name in the view model | figures | n/a |
| Accessories, shoes, socks, compression gear | **not modelled** | n/a | gap |

## Game and statistics
| Field | Source of truth | Consumers | Duplication or drift |
|---|---|---|---|
| Events | `FcGameEventLog` rows (six integers) written by the simulator | `FcPlayByPlay`, replay, narration | period and score are derived, not stored |
| Box score | `FcBoxScore` from the simulator | post-game, news, season stats | the log reproduces it (`test_game_events`) |
| Season statistics | `FcSeasonStats` (one line per player per season, team of latest game) | leaders, awards, careers | S2-HIS-1 |
| Career rows | `world.careers[pid]` rows `[year, team, stats...]`, replace-by-year | history, legacy | same limit |
| Retention | Owner/Career: last 20 watched games with events; Dynasty: last 5 replays, 25 summaries | replay, game history | documented (FEATURE_MATRIX) |
