# Progress Log

Newest first. Written so someone returning after a break can see where things stand.
The repository was published to GitHub on 2026-11-17 at the founder's request (public: https://github.com/Novaeris/full-court-godot, remote `origin`, branch `main`). Later commits stay local until the founder asks for a push.

## 2026-11-20: content publishing (Creator Studio to the game), D-042

Built in six milestones, each committed and pushed at the founder's request: the shared format (`src/content/`: manifest, canonical checksums over raw bytes, safe paths, validator, card revision rules), the immutable local store with a crash-safe active pointer, owner approval bound to one draft and single use, the publisher, the draft workspace, the game-side loader (fallback along `previous_release_id`, then the bundled starter release, with a visible report), rollback, ownership by stable ids, preferences, and `App.content`. Creator Studio is a separate Godot project (`creator_studio/`) reaching `src` and `data` through git-ignored junctions (`./tools/link_studio.ps1`); it has one screen with drafts, a check report, a confirmed approval button and a release list with rollback. Tests: 758 (48 new). Also verified: Studio smoke test, `./tools/publish_demo.ps1`, and a fresh clone (link script, import, full suite, Studio smoke).
Not built (by design): remote hosting or accounts, Dynasty gameplay, a visual card editor (drafts are edited as files for now), a save-format change (ownership will be stored by id when Dynasty adds it, with a `DATA_VERSION` bump and migration).
Notes for the founder: the bundled starter content (`data/content_starter`) is minimal placeholder data used only as the last fallback; Studio's default content folder is `Documents/FullCourtContent`; the first Studio run after cloning needs `--import` twice (see docs/ARCHITECTURE.md).

## 2026-11-19: Career Mode playable, then a stabilization pass

Career Mode phases 1-6 are built (D-038 to D-040): creator, progression, season simulation, the RPG layer (decisions, contracts, relationships, rivalries, sponsorships), potential-capped player-directed growth, and a scouting report and draft pick. A whole career plays start to finish (`./tools/career_playthrough.ps1`), and `./tools/career_click_test.ps1` clicks through the Career screens.
Stabilization pass (no game rules changed, no save-format change, `DATA_VERSION` unchanged): the profile id contract was corrected (D-041: text, unique per save, not globally unique), online claims about Career were reworded as deferred (proposed, awaiting founder approval), the balance tool's wording and thresholds were reconciled, and the README, roadmap, milestone plan, Career plan, testing guide and CLAUDE.md were brought up to date. Validation outputs, including the test count (710), are in `docs/validation/`.
Next (founder): play several Owner seasons and several Career builds by hand (save and resume, offseason, contracts, retirement), then a visual and usability pass, then freeze core rules.

## 2026-11-18: stability sign-off

Response to an outside review: explicit pricing modes in the playthrough tool, a debt restructuring rule that keeps D-029 (D-036), AI financial discipline, a hard-limit fix, an owner stress tool, multi-seed economy runs, reconciled docs and GitHub Actions CI. Result and every number: `docs/STABILITY_REPORT.md` (597 tests, CI green, conditional sign-off). Open: a founder decision on small-market owners who need repeated restructuring.

## 2026-11-17: the "finish the list" session

The founder asked for the whole remaining list (economy, Owner features, polish, decisions) to be finished, with a commit and push after each part. What was done, in order (each is its own commit on `main`):
1. **Long-run economy** (`FcEconomy`): inflation, a cap that follows league profit, new-arena project, AI building projects, dividends (also an owner button). `tools/economy_check.ps1` plays AI-only leagues for 50 seasons: 12, 30 and 64 teams all pass (cap $140M to about $0.8-0.9B, margins 4-10%, cash under 3x the cap).
2. **Relocation**: the owner chooses the city and renames the team (D-034).
3. **Overtime**: 2.3% to about 4.0% of games (real: 5-6%).
4. **Staff chemistry** and the GM's negotiation skill in deals.
5. **Season tickets and promotion nights.**
6. **AI reactions** (trade wariness, meeting rapport, neighbours lose fans when a team moves in).
7. A real bug found by the UI playthrough and fixed with a regression test: contracts agreed before the league minimum salary rose were below the new minimum.
8. **First-time tutorial**, player settings, a central theme and text sizes.
9. **Windows export** (`export_presets.cfg`, `tools/export_windows.ps1`, `docs/RELEASE.md`).
10. **Decisions and legal**: `docs/LEGAL_CHECKLIST.md`, `docs/LOOK_AND_FEEL.md`, a review of `docs/MILESTONE_PLAN.md`, D-034 and D-035.
Tests: 581 pass (was 542). The click test (67 clicks) and the UI playthrough (4 seasons, 12 teams, relocate and expand on) report 0 problems.
Follow-up the same day, in plan order: M1 (20-season playthrough with every lever), M2 (a 50-season run with the owner playing found and fixed that the owner's prices ignored inflation; 50 seasons take about 6 s each and a 5.2 MB save), M4 (tooltips, About/licenses/logs, sizes), M5 (tester zip, `--selftest`), M3 (late fouling), and draft designs for M6 and M7. The unit suite now takes about 10 minutes (584 tests).
Still needing the founder: look-and-feel references, a lawyer for the checklist, and a go-ahead on the plan.

## 2026-11-16 hand-off: where Owner Mode stands

**542 automated tests passed at the time of this 2026-11-16 hand-off (596 now; see `docs/STABILITY_REPORT.md`)** (`./tools/run_tests.ps1`), plus two long checks that drive the real UI:
`./tools/click_test.ps1` (54 simulated mouse clicks through a whole season and offseason) and
`./tools/ui_playthrough.ps1 seasons=3 teams=30` (many owner features over several seasons, saving and loading
mid-draft). Everything is committed locally; nothing is published.

### Try this first (about 10 minutes)
1. Open `project.godot` in Godot 4.7 and press F5. **New Game**, pick 12 teams for a quick league, Owner Mode, choose a team.
2. **Finances** tab: press "Use suggestion" for the ticket price; try concession prices and the merchandise range.
3. **Staff** tab: tick "Re-sign my players", "Run the draft" etc. to let your general manager do things, and set a philosophy and budget.
4. Press **To End of Regular Season**, **Play All Playoffs**, then **Begin Offseason**. In the **Draft** tab invite a prospect to a workout, pick one, then in the **Market** tab sign a free agent (change the offer and see how he reacts), and **Finish Offseason**.
5. **Trades** tab: try a trade with players and a draft pick.

### What exists in Owner Mode now
- **Business**: ticket price (with a suggested price), marketing, concession prices, merchandise range, sponsorship style, loans, arena projects (seats, suites), arena quality, revenue sharing between markets, business executive effects, a league finance comparison, franchise value.
- **People**: hire and fire staff; the GM, coaches, scouts, medical staff and business executive all have effects. Staff changes are reported as news.
- **Players**: roster, profiles, careers; sign free agents and release players (with negotiation: salary and years), re-sign decisions at season end, trades with players and draft picks (AI teams value picks by the original team's strength).
- **Draft**: a lottery option; a scouted board with ranges (better GM and scouts, narrower ranges), 5 workouts, your own picks, a staff pick option, trading picks; the AI trades picks too.
- **Offseason flow**: Begin Offseason -> the draft -> a free-agency window before the AI teams sign -> Finish Offseason.
- **Delegation**: the GM can re-sign, run the draft, sign free agents, trade and cover injuries, steered by your philosophy (win now / balanced / rebuild) and budget; his skill sets how well he judges players; a report card grades him.
- **League**: history, champions, awards, records, Hall of Fame, all-time leaders, news.

### Known gaps (also see the older list below)
- (Updated 2026-11-18) Overtime games are about 3.5-4.4% (4.4% before the 2026-11-18 turnover recalibration, about 3.7% after) (real about 5-6%) after two sim changes; close games are slightly too frequent.
- (Updated 2026-11-18) The UI has a central dark theme, text sizes, a tutorial and tooltips; it is still plain tables and buttons, desktop only, and the real look waits for the founder's references. Staff chemistry, season tickets, promotion nights and playoff prices exist.
- A small-market owner who starts with a high payroll loses money in season 1 (valid challenge, recovered by season 3 in testing).
- (Updated 2026-11-19) Career Mode is built and playable (see the 2026-11-19 entry); Dynasty Mode (card collecting) is defined (D-029) but not built. The old watch-only mode that was called "dynasty" in the code is now "Spectator".

### Questions for the founder
1. ~~Career Mode: what does the player do in it?~~ Answered and built (see the 2026-11-19 entry).
2. Is the pace of the free-agency/draft flow right (the offseason now has a draft screen and a window, and the GM can skip them)?
3. Do you want me to continue with Owner Mode depth (staff negotiation, named sponsors) or begin Dynasty Mode next?

## (older) 2026-11-15, autonomous stretch (founder away)

State at the end of this stretch: **469 automated tests pass**, everything committed locally.
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
- (Superseded 2026-11-17: see "Overtime rate" and "Late-game fouling" below; the rate is now about 3.5-4.4% (4.4% before the 2026-11-18 turnover recalibration, about 3.7% after).) Overtime games were about 2.6% (real about 5-6%). Tried (2026-11-16): late-game intentional fouling by the trailing team plus hurry/stall tempo. Over 8,000 games it left the rate unchanged (about 2.7%) and raised pace and fouls, so it was reverted. The gap is probably in how final margins cluster (ties need a heavier peak near zero); a different approach (e.g. last-possession logic, closer-game variance) is needed.
- Market tab (free agents + latest draft) is read-only; no signing or draft interaction yet.
- Human trades work (Trades tab, one-for-many swaps under the cap rules); the AI never proposes trades to the user.
- Hall of Fame and record book exist (History tab); a records page for team records and retired numbers is not built.
- Free-agent signing and releasing work in-season; there is no negotiation (you pay the asking price) and no offseason bidding screen.
- Not built: trades proposed to the user by AI teams, awards beyond MVP/leaders/All-League/Finals MVP, named multi-year sponsor contracts, staff chemistry, Dynasty-mode roster control (the user cannot set lineups or minutes yet), mobile layouts, exports.

### How to continue
Read docs/ROADMAP.md ("Next") and say "continue". Work order I intend to follow: UI shell, trades, injuries, history/records, scouting, Dynasty mode controls, deeper simulation.

## Earlier
See docs/ROADMAP.md "Completed" and the git history (`git log --oneline`).
