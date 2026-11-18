# Career Mode: draft design for the founder to correct (M6)

Status: **DRAFT written by Claude on 2026-11-17 using recommended answers. No code exists and none will be written until the founder approves or changes this.** The founder defined the idea (decision D-029): create one player and take them through an RPG-style career of about 20 years, with randomized players, using the same league and simulation core as Owner Mode.

## The idea in one paragraph
You create a player (name, position, body, a few starting traits), enter the draft or sign as a free agent, and live a 20-season career. Each season you make a few meaningful choices (training focus, contract, team, how you behave), the simulation plays the league around you, and your player grows, peaks, declines and retires. The game ends with a career summary and a Hall of Fame verdict. The rest of the league (Owner Mode's league core) keeps going, so teams, coaches and rivals feel alive.

## Recommended answers to the questions that decide the design
1. **How much do you control during games?** Recommended: none moment to moment in v1. You choose role, minutes goal and playing style; the existing simulation plays the games. (A "key moments" mini-choice, such as who takes the last shot, can come later.)
2. **What does a season look like?** Recommended: five stops: (a) offseason training plan (spend a limited number of "development points" on attribute groups), (b) the season in weeks with events (injury, slump, a teammate conflict, a media moment) that ask for a choice, (c) the trade deadline (ask for a trade or stay), (d) the playoffs, (e) the season review (awards, stats, contract talks).
3. **Progression:** Recommended: the existing attribute and progression system (`FcPlayerProgression`) with the player's own choices on top: development points, coaching quality of the current team, practice facility, age curve. Potential is hidden at first and revealed through scouting reports.
4. **Personality and choices:** Recommended: the seven personality traits already in the data (loyalty, ambition, ego, money focus, professionalism, temperament, adaptability) drift with your choices and change how coaches, teammates, agents and fans react (playing time, trade requests, contract offers).
5. **Contracts and teams:** Recommended: you negotiate with your agent's help (a skill that improves with reputation); free agency and trades happen as in Owner Mode but you are the asset. Team changes are your own choice or forced by trades.
6. **Money and life:** Recommended: light. Earnings, endorsements and one or two lifestyle choices that affect stats (health, focus). No full life simulation in v1.
7. **How does it end?** Recommended: forced retirement by age or injury, or your choice from age 34. Then an ending screen: career stats, awards, rings, Hall of Fame score (the Hall of Fame record book already exists), and the option to start a new player in the same saved league.
8. **Difficulty and failure:** Recommended: you can have a bad career (cut, benched, injured) but never a "game over" before the end of the 20 years; a cut player can sign elsewhere or play overseas for a season.
9. **League size and world:** Recommended: the same league creation screen as Owner Mode, defaulting to a smaller league (12-30 teams) so seasons are quick.

## What can be reused (so the build is smaller than it sounds)
- The league, schedule, standings, playoffs, awards, records and Hall of Fame (`src/league/`, `src/data/season/`).
- Player generation, attributes, personality and progression (`src/gen/`, `src/league/player_progression.gd`).
- The offseason, draft, free agency, contracts and cap rules, trades, AI teams and the economy.
- The game simulation for games and box scores.
- Saves, the controller pattern (a new `FcCareerController` that screens call), the UI theme, tutorial and tooltips.

## What must be new
- A career state in the save (the player id, development points, choices, events, agent and reputation), with a save migration.
- Player creation screens and a career dashboard (different tabs from Owner Mode: Me, Team, Schedule, Contract, Training, Events, Career).
- An event system (data-driven JSON of events with conditions and choices, like the existing JSON definitions).
- The player's "role" feeding the simulation (starter or bench, minutes, usage) so that choices change the box score.
- An ending and a career summary screen.

## Proposed build order (each step playable and tested)
1. Create a player and join a league (draft or free agency); play one season on autopilot; see the stats.
2. Training plan and progression choices; season review.
3. Contracts, agent, free agency and trades from the player's side.
4. Events and personality.
5. Retirement, ending screen, Hall of Fame, new player in the same league.
6. Polish and balance a full 20-season career with the long-run checks (a 20-season career playthrough tool like `tools/ui_playthrough.ps1`).
Rough size: XL (several weeks of work), most of it screens and events, little simulation.

## Questions only the founder can answer
- Is "no control of games in v1" acceptable, or is a playable key-moment layer essential?
- How much text and story (events) do you want, and in what tone?
- Is the player's goal winning, stardom, money, legacy, or a choice at the start (archetypes)?
- Should real-time or turn-based pacing matter (days vs weeks vs seasons)?
