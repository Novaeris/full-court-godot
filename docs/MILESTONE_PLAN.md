# Milestone Plan (DRAFT for founder review)

Status: **draft v2, 2026-11-16.** The founder answered the first round of questions (recorded as D-029); this version
reflects them. The order is still waiting for approval. Once approved it replaces the "Next" list in `docs/ROADMAP.md`.

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
1. **Owner reputation and changing jobs** (decided: the player cannot lose, but can transfer to another team "like
   a job"): the owner's approval and results build a career reputation; at season's end the owner gets job offers
   from other franchises (better reputation = better franchises) and may transfer. A good run also unlocks more room
   (bigger loan limit). *Built first (done 2026-11-16: reputation, offers, transfer).*
2. **Ticket pricing depth**: separate prices for playoffs *(done 2026-11-16)*; season tickets vs single games and a simple "special
   promotion night" lever are still open.
3. **AI teams propose trades to you** (inbox with accept/decline) *(done 2026-11-16)*; rival GMs reacting to your moves is still open.
4. **Staff chemistry and coaching philosophy fit** (the data already exists: staff philosophy, player personality).
5. **Facilities beyond seats and suites**: practice facility (development speed), medical center (injury recovery),
   each a project like the arena ones *(done 2026-11-16)*.
6. **The owners' meeting** (founder request 2026-11-16: relocation and expansion are in; teams vote on rule changes,
   expansion and similar things in a part of the offseason). Proposal, for review (nothing built):
   - *When*: a stage of the offseason after the playoffs and before the draft; 2-5 agenda items per year.
   - *Agenda types*: **expansion** (add teams to a valid league size, an expansion fee shared among owners, an expansion
     draft, realignment of conferences and divisions); **relocation** (a struggling AI team, or the player's own team, asks to
     move to a new city; approval needed); **competition rules** (playoff size and format, draft lottery odds, draft rounds,
     roster limits, season length); **money rules** (salary cap level and growth, luxury tax, revenue sharing, rookie scale).
   - *Voting*: one vote per franchise; simple majority for most items, a supermajority (e.g. three quarters) for expansion,
     relocation and cap-changing rules. Each AI owner votes by self-interest and a personality (what helps their team
     now: small markets favour revenue sharing, bubble teams favour more playoff spots, contenders dislike talent
     dilution); the tally shows each team's vote and reason.
   - *The player's role*: one vote, a read on how each owner leans, and *influence* (from owner reputation and market size)
     to spend on lobbying or on proposing one item a year; supporting another owner's item can buy support for yours.
   - *Staging*: (a) meeting with rule tweaks, expansion and relocation, AI voting and a tally; (b) influence, lobbying and
     player proposals; (c) the details: expansion draft with protected lists, realignment, arena for relocated teams.
   - *Fits the code*: league rules are already data classes with `validate()`; valid league sizes are known
     (`FcLeagueStructure`); the schedule builder and standings accept any valid structure; saves can hold 100 teams (D-005).
     New work: AI voting model, the agenda and tally screen, an expansion-team generator and expansion draft,
     relocation (city, arena, fan base), save versioning for changed rules and structure.
   - *Risks*: AI votes could drift the league (every change is checked with the league health tools); saved-structure changes
     need migrations; one new screen and a lot of tests.
Done when: a scripted 20-season owner playthrough exercises every lever, stays valid, and the books and league
health checks stay in range.
Needs from you: whether relocation/expansion belong in v1.

## M2. Long-run health and balance (size L, partly overlaps M1)
Goal: **50-season** Owner Mode leagues (decided: the founder wants a 50-year simulation) stay interesting and fair.
Scope: league talent and age drift, dynasties, finance drift (inflation, cap growth), salary-cap growth over time,
league expansion effects, save size and load time over 30 seasons, performance (seconds per season).
Done when: a 50-season, 30-team run passes the health tools: several champions, stable talent and ages, no team
permanently broke or permanently rich, saves under an agreed size, a season under an agreed time.
A first 50-season run on 2026-11-16 found and fixed two real problems (a payroll integrity break from contract raises, and seasons slowing down as old contracts piled up); the details are in `docs/ARCHITECTURE.md` ("50-season health"). A second run after the fixes is the baseline for M2.

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
Decided: art and audio will be made with AI tools by the founder. Mobile is for **Dynasty Mode only** (D-030), so Owner and
Career Mode UI is designed for desktop (mouse, large windows); touch layouts are needed only for Dynasty.
Needs from you: the look you want (references, mood, colours). Reminder for later (M8): AI-made assets need a rights
and store-disclosure check.

## M5. Platforms and builds (size XL)
Goal: the game runs on Windows first, then Mac; **mobile (Android and iOS) carries Dynasty Mode only** (D-030).
Scope: Windows export and installer, then Mac; for mobile only the Dynasty card game needs touch layouts and phone
performance (the simulation core must run on phones for matches; the "gl_compatibility" renderer was chosen for this);
platform save locations; automated builds; crash logs the player can send.
Done when: a build installs and plays a full season on each target.
Needs from you: later, for Dynasty on phones: devices (or emulators) and Apple/Google developer accounts.

## M6. Career Mode (size XL; defined, not scheduled)
Goal: the player creates one player and takes them through a roughly **20-year** RPG-style career (decided).
Scope (from the founder's description; to be detailed with the founder before building): player creation, progression
as an RPG (skills, choices, milestones), contracts and team changes, the daily life of a career, an ending.
Randomized players and the existing simulation, so it reuses the core.
Done when: a 20-season career can be played start to finish and the simulation of the rest of the league stays healthy.
Needs from you: a detailed design (what the player does each season, what choices exist, how it ends).

## M7. Dynasty Mode (size XL+; defined, not scheduled)
Goal: a **card-collecting game inspired by NBA 2K MyTeam** (decided), with **static players that the founder makes**,
and some paid features. This is a different product from Owner and Career Mode: a collection of cards, lineups,
game types, and probably online features.
Scope: card and collection data model, how cards are obtained (design needed), lineup building, matches using the
existing game simulation, progression and rewards, and the paid features.
Risks to settle before building: random paid card packs are treated as gambling-like "loot boxes" in some countries,
and this project's rule is "no pay-to-win"; the online parts (accounts, servers, fairness, cheating) are a large
new area; static players must be original (no real players or names).
Needs from you: the design, the list of paid features, and the card set (names, art, ratings).

## M8. Pre-release (size L, can start early on legal items)
Goal: the game can be released safely.
Scope: legal review of invented names and place names (a lawyer, per D-020 and rule 9), license and privacy review,
the free-to-play and "no pay-to-win" decisions in practice (what is sold, if anything), store pages, age rating,
localisation of the interface, balance passes with outside testers, accessibility, a bug-reporting path.
Done when: the checklist in a release document is green. Nothing is published before you decide.
Needs from you: business decisions (price model, release order, who tests).

## Proposed order and why
1. **M1 and M2 together** (Owner Mode complete and healthy for 50 seasons): it is the first mode and everything
   else reuses these systems.
2. **M4 UI polish (desktop)** next, then **M5 PC builds** (Windows, then Mac): the biggest gap between "works" and
   "feels like a game", and cheaper to fix before the other modes multiply the screens. Mobile belongs to M7 (Dynasty).
3. **M3 Simulation depth** in parallel with M4/M5 where convenient (it is mostly separate code).
4. **M6 Career Mode** (shares the core) once Owner Mode is shippable and the design exists.
5. **M7 Dynasty Mode** last: a separate product with its own systems, design and legal questions, and the only mode on
   mobile (touch UI, phone builds, store accounts).
6. **M8** legal items start early (loot boxes, AI-made assets, names); the rest at the end.

## Risks and how this plan handles them
- **Three products in one**: Owner/Career share a core, but Dynasty (card collecting, paid features, probably online) is a different product. Mitigation: it is last and gets its own design phase.
- **Scope growth**: Owner Mode keeps gaining levers. Each addition must pass the health tools (finances, league
  health, playthrough) before the next starts.
- **A beginner-friendly UI is a rework risk**: the UI is built in code and tuned only at 1280x800; M4 and M5 will
  touch every screen. Mitigation: keep screens thin (the controller API does the work), keep the click test.
- **Balance drift**: every new system can change the economy. Mitigation: the health tools run after each change.
- **Solo-developer bus factor**: everything is documented in `docs/` and in the progress log.
- **IP risk**: invented names are generated, real places are used. Mitigation: D-020 and a legal review in M8.

## Decided (2026-11-16, founder; see D-029)
- The Owner Mode player cannot lose but can transfer teams like a job. Owner Mode targets a 50-year simulation; Career Mode about 20 years.
- Career Mode = create a player, RPG progression. Dynasty Mode = MyTeam-style card collecting with static, hand-made players and paid features.
- Art and audio: AI-generated by the founder. Platform after Windows: mobile.

## Decisions I still need from you
1. Do relocation and expansion belong in Owner Mode v1 (M1)?
2. The look and feel you want for the UI (M4): references, mood, colours.
3. Career Mode design details when you are ready (M6), and the Dynasty Mode design, paid features and card set (M7).
4. Do you agree with the order above, or what moves first?
