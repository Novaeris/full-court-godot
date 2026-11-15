# Progress Log

Newest first. Written so someone returning after a break can see where things stand.
Nothing has been pushed anywhere: the repository is local only (no remote).

## 2026-11-15, autonomous stretch (founder away)

State at the end of this stretch: **347 automated tests pass**, everything committed locally.
Run the tests with `./tools/run_tests.ps1`.

### Built since the founder left
1. **Simulation calibrated to the 2010-2020 NBA** with three era presets (`early_2010s`, `mid_2010s` default, `late_2010s`), realistic stars (scoring leaders about 30-32 ppg, 25+ ppg players 6-8), realistic rotations. Check: `./tools/simulate_games.ps1` and `... leaders`.
2. **Calendar** (dated schedule with rest and travel limits), **standings with tiebreakers**, **playoffs** (division leaders or seeding, conference or league brackets, byes, 2-2-1-1-1 home court), champion, awards, season statistics. Play one: `./tools/play_season.ps1`.
3. **Player progression and retirement**, **contract expiry, AI re-signing, draft (2 rounds, rookie scale), free agency** under the salary rules, legal rosters, **staff rollover**. Verified over several consecutive seasons: `./tools/play_seasons.ps1 seasons=6`.
4. **Owner Mode business engine**: demand and ticket pricing, revenue and expense lines, fan interest, brand, cash, debt, valuation; owner levers (ticket price, marketing, facilities); AI teams run themselves. See the books: `./tools/finances.ps1`.
5. **Game controller** (`src/game/game_controller.gd`): the API a screen uses (advance days, playoffs, next season, owner decisions, hiring/firing, owner report, autosave). Saves continue identically after loading.

6. **A first UI** (main menu, new league wizard, team choice, dashboard with Overview / Standings / Schedule / Roster / Finances / Staff / League tabs). **How to play**: open `project.godot` in Godot 4.7 and press F5 (see README.md). The automated tests prove the screens build and the game can be played through them; they cannot judge how it looks or feels, so please look at it and tell me what to change.

7. **Injuries**: players get hurt during games (more when fragile, more minutes), miss games, return, and severe injuries cost athleticism. Medical staff skills are not wired in yet.

### Decisions made for you (all recorded in docs/DECISIONS.md, D-021 to D-025)
Era presets and star usage; league balance (team spread tightened); no draft lottery; simple AI (best affordable player); finance constants (about 11% average margin, a third of teams lose money); price scaling with season length. Every number is in a JSON file under `data/` and can be changed.

### Known gaps and things to watch
- **UI is a first plain version**: no box score viewer, no draft / free agency / trade screens, no theme polish, no mobile layout.
- Dynasties: in a 6-season test one team won 4 titles with a 71-9 record. The AI never trades and keeps stars via the own-player exception; watch league parity. Candidates: trades, player moves for money/role, aging curves.
- League average age drifts young (about 24.6 after six seasons; real is about 26). Retirement and the draft supply are the levers.
- Overtime games are about 2% (real about 5-6%): end-of-game fouling and timeouts are not modeled.
- Not built: trades, injuries, scouting uncertainty, draft lottery, awards beyond MVP/leaders/All-League/Finals MVP, Hall of Fame, records book, sponsorship contracts, loans, arena renovation projects, staff chemistry, Dynasty-mode roster control, mobile layouts, exports.

### How to continue
Read docs/ROADMAP.md ("Next") and say "continue". Work order I intend to follow: UI shell, trades, injuries, history/records, scouting, Dynasty mode controls, deeper simulation.

## Earlier
See docs/ROADMAP.md "Completed" and the git history (`git log --oneline`).
