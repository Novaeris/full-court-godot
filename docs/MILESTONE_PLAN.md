# Milestone Plan (DRAFT for founder review)

Status: **draft, written 2026-11-16, nothing here is approved yet.** Please reorder, cut or add. Once you approve it,
this replaces the "Next" list in `docs/ROADMAP.md`.

How to read it
- Each milestone has a **goal** (what is true when it is finished), **scope**, **done when** (how we will know) and
  **needs from you** (decisions only you can make).
- **Size** is a rough guess in working stretches ("S" = a few hours of my work, "M" = a day, "L" = several days,
  "XL" = a week or more). My estimates have been too small as often as too large; treat them as order of magnitude.
- Owner Mode comes first (decision D-028). Career Mode is on the plan but **blocked until you describe it**.
- Rules that apply to every milestone: tests first-class, docs updated with the code, saves versioned, nothing pushed
  or published without your say-so, original names and branding only.

## Where we are (M0, done)
Engine, league, seasons, offseason, finances, a plain but complete UI, and most of Owner Mode: business levers,
staff, players, trades with picks, the draft with scouting, delegation to the GM, sponsors. About 480 automated tests,
a mouse-click test and a multi-season playthrough test. Details: `docs/PROGRESS_LOG.md`.

## M1. Owner Mode feature-complete (size L)
Goal: a player can own a franchise for many seasons and every major lever from `docs/GAME_DESIGN.md` exists.
Scope (in rough order):
1. **Owner expectations and job security**: the owner's approval (already computed) gets consequences: warnings,
   a bad run can end your ownership (sell or be forced out) and a good run unlocks more room (bigger loan limit).
   Needs a decision from you: should you be able to *lose* the game?
2. **Ticket pricing depth**: separate prices for playoffs, season tickets vs single games, and a simple "special
   promotion night" lever.
3. **AI teams propose trades to you** (inbox with accept/decline) and rival GMs react to your moves.
4. **Staff chemistry and coaching philosophy fit** (the data already exists: staff philosophy, player personality).
5. **Facilities beyond seats and suites**: practice facility (development speed), medical center (injury recovery),
   each a project like the arena ones.
6. **Franchise events**: relocation and expansion (saves can grow to 100 teams per D-005), a new arena.
Done when: a scripted 20-season owner playthrough exercises every lever, stays valid, and the books and league
health checks stay in range.
Needs from you: "can you be fired?", and whether relocation/expansion belong in v1.

## M2. Long-run health and balance (size M, partly overlaps M1)
Goal: 30-season leagues stay interesting and fair.
Scope: league talent and age drift, dynasties, finance drift (inflation, cap growth), salary-cap growth over time,
league expansion effects, save size and load time over 30 seasons, performance (seconds per season).
Done when: a 30-season, 30-team run passes the health tools: several champions, stable talent and ages, no team
permanently broke or permanently rich, saves under an agreed size, a season under an agreed time.
Needs from you: how long a playthrough should realistically last (10 years? 30?).

## M3. Simulation depth (size L)
Goal: games feel like real basketball at the level a manager can notice.
Scope: overtime rate (still about 2.6% vs 5-6%; one fix tried and reverted), timeouts, matchups and positions,
end-of-game situations, fouls and foul trouble, pace and style choices that matter, home-court detail, more
realistic injuries. Each change is recalibrated with `tools/simulate_games.ps1` (the 16 league checks stay in range).
Done when: all league-average checks pass in all three eras AND the overtime rate, clutch scoring and close-game
rates are inside real-world ranges.

## M4. UI polish and onboarding (size L)
Goal: someone who has never seen the game can start and understand it.
Scope: a real visual theme (colours, fonts, spacing), clearer layouts at several window sizes, tooltips and short
explanations next to every lever, a first-game tutorial, settings (volume, text size, save slots), box-score and
standings screens with more information, a proper save/load screen, error messages in plain language.
Done when: you and two fresh testers can play a season without help; the click test and screenshots cover every
screen at two sizes.
Needs from you: the look you want (references, mood, colours), and whether there is art/audio.

## M5. Platforms and builds (size XL)
Goal: the game runs on Windows first, then Mac, then Android and iOS.
Scope: Windows export and installer; touch-friendly layouts and small screens (the UI is code-built, so this is a
rework of layout code); platform save locations; performance on phones (the "gl_compatibility" renderer was chosen
for this); automated builds; crash logs the player can send.
Done when: a build installs and plays a full season on each target.
Needs from you: which platform after Windows, and devices to test on (or accept emulators).

## M6. Dynasty Mode (size XL)
Goal: deep multi-decade control: lineups, minutes, tactics, development plans, roster moves by hand.
Scope: coach-level controls (starters, rotation, minutes, tactics), player development choices, deeper scouting,
a roster-management UI, a mode-specific start (take over a team as GM/coach). Shares the core with Owner Mode.
Done when: a Dynasty playthrough test exercises every control and the AI gives fair opposition.
Needs from you: how Dynasty differs from Career Mode (see M7), and whether Dynasty is premium (design doc says
"likely").

## M7. Career Mode (size: unknown, BLOCKED)
Goal: to be defined by you. I will not design or build anything for it until you describe it.
Questions: What role does the player take (player, coach, executive)? What is the loop and how does it end? How is it
different from Dynasty Mode?

## M8. Pre-release (size L, can start early on legal items)
Goal: the game can be released safely.
Scope: legal review of invented names and place names (a lawyer, per D-020 and rule 9), license and privacy review,
the free-to-play and "no pay-to-win" decisions in practice (what is sold, if anything), store pages, age rating,
localisation of the interface, balance passes with outside testers, accessibility, a bug-reporting path.
Done when: the checklist in a release document is green. Nothing is published before you decide.
Needs from you: business decisions (price model, release order, who tests).

## Proposed order and why
1. **M1 and M2 together** (Owner Mode complete and healthy for 30 seasons): it is the first mode and everything
   else reuses these systems.
2. **M4 UI polish** next: the biggest gap between "works" and "feels like a game", and cheaper to fix before
   platforms multiply the work.
3. **M3 Simulation depth** in parallel with M4 where convenient (it is mostly separate code).
4. **M5 Platforms** once the UI is stable (touch layouts depend on it).
5. **M6 Dynasty** after Owner Mode is shippable. **M7 Career** when you have defined it.
6. **M8** legal items can start any time; the rest at the end.

## Risks and how this plan handles them
- **Scope growth**: Owner Mode keeps gaining levers. Each addition must pass the health tools (finances, league
  health, playthrough) before the next starts.
- **A beginner-friendly UI is a rework risk**: the UI is built in code and tuned only at 1280x800; M4 and M5 will
  touch every screen. Mitigation: keep screens thin (the controller API does the work), keep the click test.
- **Balance drift**: every new system can change the economy. Mitigation: the health tools run after each change.
- **Solo-developer bus factor**: everything is documented in `docs/` and in the progress log.
- **IP risk**: invented names are generated, real places are used. Mitigation: D-020 and a legal review in M8.

## Decisions I need from you (short list)
1. Can the player lose Owner Mode (forced to sell)? (M1)
2. How long is a typical playthrough meant to be? (M2)
3. What look and feel do you want, and is there any art or audio budget? (M4)
4. Which platform after Windows? (M5)
5. What is Career Mode, and how does it differ from Dynasty Mode? (M7)
6. Is Dynasty Mode a paid mode? (M6, M8)
7. Do you agree with the order above, or what moves first?
