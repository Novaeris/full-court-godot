# Progress Log

Newest first. Written so someone returning after a break can see where things stand.
Nothing has been pushed anywhere: the repository is local only (no remote).

## 2026-11-15, autonomous stretch (founder away)

State at the end of this stretch: **424 automated tests pass**, everything committed locally.
Run the tests with `./tools/run_tests.ps1`.

### Built since the founder left
1. **Simulation calibrated to the 2010-2020 NBA** with three era presets (`early_2010s`, `mid_2010s` default, `late_2010s`), realistic stars (scoring leaders about 30-32 ppg, 25+ ppg players 6-8), realistic rotations. Check: `./tools/simulate_games.ps1` and `... leaders`.
2. **Calendar** (dated schedule with rest and travel limits), **standings with tiebreakers**, **playoffs** (division leaders or seeding, conference or league brackets, byes, 2-2-1-1-1 home court), champion, awards, season statistics. Play one: `./tools/play_season.ps1`.
3. **Player progression and retirement**, **contract expiry, AI re-signing, draft (2 rounds, rookie scale), free agency** under the salary rules, legal rosters, **staff rollover**. Verified over several consecutive seasons: `./tools/play_seasons.ps1 seasons=6`.
4. **Owner Mode business engine**: demand and ticket pricing, revenue and expense lines, fan interest, brand, cash, debt, valuation; owner levers (ticket price, marketing, facilities); AI teams run themselves. See the books: `./tools/finances.ps1`.
5. **Game controller** (`src/game/game_controller.gd`): the API a screen uses (advance days, playoffs, next season, owner decisions, hiring/firing, owner report, autosave). Saves continue identically after loading.

6. **A first UI** (main menu, new league wizard, team choice, dashboard with Overview / Standings / Schedule / Roster / Finances / Staff / League tabs). **How to play**: open `project.godot` in Godot 4.7 and press F5 (see README.md). The automated tests prove the screens build and the game can be played through them; they cannot judge how it looks or feels, so please look at it and tell me what to change.

7. **Injuries**: players get hurt during games (more when fragile, more minutes), miss games, return, and severe injuries cost athleticism. Medical staff skills (injury prevention, rehabilitation) change how often and how long.

8. **News tab** (injuries, big games, champions, awards, signings, retirements) and a **box score viewer** for your team's last 20 games (Schedule tab).

9. **AI trades** (offseason, contenders swap youth for veterans with rebuilding teams under the salary rules).

11. **Player profile** popup (Roster tab): bio, all ratings, personality, tendencies, contract, career line.
10. **Career statistics** (kept forever) and **archiving** of seasons older than two years so saves stay small.

### Decisions made for you (all recorded in docs/DECISIONS.md, D-021 to D-025)
Era presets and star usage; league balance (team spread tightened); no draft lottery; simple AI (best affordable player); finance constants (about 11% average margin, a third of teams lose money); price scaling with season length. Every number is in a JSON file under `data/` and can be changed.

### Known gaps and things to watch
- **UI is a first plain version**: no box score viewer, no draft / free agency / trade screens, no theme polish, no mobile layout.
- Dynasties: in one 6-season test (30 teams, seed 2026) a team won 4 titles with a 71-9 record, but eight-season runs of 20-team leagues with two other seeds spread the titles across 4-5 champions, so it looks seed-specific. The AI now makes simple one-for-one offseason trades; keep watching parity.
- League average age drifts young (about 24.6 after six seasons; real is about 26). Retirement and the draft supply are the levers.
- Overtime games are about 2.6% (real about 5-6%). Tried (2026-11-16): late-game intentional fouling by the trailing team plus hurry/stall tempo. Over 8,000 games it left the rate unchanged (about 2.7%) and raised pace and fouls, so it was reverted. The gap is probably in how final margins cluster (ties need a heavier peak near zero); a different approach (e.g. last-possession logic, closer-game variance) is needed.
- Market tab (free agents + latest draft) is read-only; no signing or draft interaction yet.
- Human trades work (Trades tab, one-for-many swaps under the cap rules); the AI never proposes trades to the user.
- Hall of Fame and record book exist (History tab); a records page for team records and retired numbers is not built.
- Free-agent signing and releasing work in-season; there is no negotiation (you pay the asking price) and no offseason bidding screen.
- Not built: draft pick trading, contract negotiation (prices are the asking prices), trades proposed to the user by AI teams, awards beyond MVP/leaders/All-League/Finals MVP, named multi-year sponsor contracts, staff chemistry, Dynasty-mode roster control (the user cannot set lineups or minutes yet), mobile layouts, exports.

### How to continue
Read docs/ROADMAP.md ("Next") and say "continue". Work order I intend to follow: UI shell, trades, injuries, history/records, scouting, Dynasty mode controls, deeper simulation.

## Earlier
See docs/ROADMAP.md "Completed" and the git history (`git log --oneline`).
