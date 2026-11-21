# Progress Log

Newest first. Written so someone returning after a break can see where things stand.
The repository was published to GitHub on 2026-11-17 at the founder's request (public: https://github.com/Novaeris/full-court-godot, remote `origin`, branch `main`). Later commits stay local until the founder asks for a push.

## 2026-11-21: High-fidelity player visuals and cinematic pack opening implemented (D-059)
Promoted the approved prototypes to production in four checkpoints. A: the production figure (`hd_enabled = true`), age, height, weight and position flow from Owner and Career data into the visual without touching identity or saves; body proportions and footwear; Dynasty keeps curated art with the stable procedural fallback. B: `FcPortraitBake` with a hard 20 MB budget, measured in a window (roster of 400: 386 ms to 19 ms per forced redraw; 89 to 99% hit rates; ceiling held under pressure). C: the five-stage reveal is the default with a Cinematic or Quick setting, rarity-scaled (common and uncommon quick), legendary with the player name as the banner, integrity and reduced-motion tests. D: tests, evidence (400-player variety, bodies, ages, in-game before and after, storyboards, video) and documentation. Open: human review of timing, speakers and phones (see `docs/PLAYER_VISUAL_PROPOSAL.md`, section 0).

## 2026-11-21: Visual Identity and UI Transformation milestone (D-057, D-058)

Plan of record: `docs/VISUAL_IDENTITY_PLAN.md` (approved by the founder, run without hard stops: screenshots and a summary per checkpoint in `docs/validation/ui/visual_identity/`, each phase committed and pushed).
- **A** brand assets keyed from the supplied banners, asset spec, palette resolved by contrast tests. **B** `FcTable` prototype (400 rows build in 4 ms, scroll step 0.24 ms), states, six-state tests. **C** team identity (crest shapes, 23 emblems chosen from the nickname, wordmark, uniform colours; every team of a generated league has a different crest). **D** main menu, splash, credits, three mode cards, save cards, export icons. **E** the player figure rebuilt with detail by size and derived face proportions, chip and tile family, golden identity fixture. **F** every Owner tab onto the new parts (portraits, crests, multi-select trades, stacked finance bars, sparkline). **G** Career hub hero with level, XP and a radar. **H** Dynasty bracket and lineup dialog, Creator Studio restyle and card previews. **I** championship celebration, achievement banner, four new sounds, quick mute. **J** this final pass.
- **Final checks:** unit suite 1235 and live suite 91 pass, the Windows release was exported again and its packaged self-test says SELFTEST OK, the package inspector passes with the brand files required and the source banners excluded, the Owner and Career real-click tools pass (the Career one found a real layout regression from the taller hero, fixed by making the hub scroll).
- **Not changed:** simulation, economy, pack mechanics, saves, controller rules. One additive read-only method (`finance_series()`).
- **Open items** are in `docs/RELEASE_READINESS.md` (section "Visual Identity milestone") and the checkpoint notes: no hand-made portrait or menu art exists (everything is procedural), screen transitions are a fade only, hardware checks (phone, gamepad, screen reader, high contrast) are still not done, and the founder's eyes on the animation timing are needed.

## 2026-11-21: Release validation and Dynasty content readiness

- **Release tests.** New real-viewport screen matrix (`tests/live/test_live_screen_matrix.gd`): every Dynasty screen (both layouts), all 13 Owner tabs, Career steps and menus x 7 window shapes x 3 text sizes, dialogs, ultrawide. It found and we fixed: Owner action row not wrapping at Large text (broke the 800 px rule), two tabs open at once after a rebuild, blank empty tables, buttons narrower than a finger, a post-game score bug wider than a 360 px phone. Release-readiness unit tests now cover all 11 mobile Dynasty screens at 3 text sizes and all 13 Owner tabs at small and large text.
- **Dynasty content.** The bundled release is now the Founding Series (40 original players, 46 cards, 5 packs, 14 challenges, a season, 2 tournaments), built through the real publisher (D-055). Verified end to end from a fresh install (`tools/dynasty_initial_check.ps1`, `docs/DYNASTY_FOUNDING_REPORT.md`). Economy untouched.
- **Builds.** Windows release exported, package checked (`tools/inspect_export.ps1`), packaged self-test extended to Dynasty and passing. Android preset added (D-056), debug APK built and run on an emulator, which found two phone display defects (fixed). Android hardware validation, iOS: outstanding (`docs/DEVICE_VALIDATION.md`, `docs/PLATFORM_BUILDS.md`).
- **Owner presentation audit** of all 13 tabs (`docs/validation/OWNER_PRESENTATION_AUDIT.md`), **manual audit** status (`docs/validation/MANUAL_QUALITY_AUDIT.md`), **release report** with the six categories (`docs/RELEASE_READINESS.md`).
- Tests: unit 1133 pass, live 75 pass; tools and simulation checks all pass.
- **Founder decisions open:** package name and keystore, keep or replace the Founding Series, lawyer review, portrait lock, music.

## 2026-11-20: UI/UX polish, Phase 4 (card system)

new src/ui/cards (FcRarityStyle: five rarities each with its own frame, background pattern and effects, with a safe fallback for unknown rarities; FcCardFace: the whole card drawn in one node with hover lift, focus ring, selected, inspected, face-down back, flip, a shader light sweep on rare and up, mastery frames, NEW and other tags, accessible text). FcCardView.build keeps its API, so every Dynasty screen already uses the new cards. The gallery has a Cards section (all rarities, states, sizes). Card text is drawn, so tests read a card's accessible_text(). Results: docs/validation/ui/phase4_results.txt.

## 2026-11-20: UI/UX polish, Phase 5 (collection, carousel, inspector, compare, completion)

FcUiState (user://ui_state.cfg, D-048: seen cards and browse mode; never in a save), FcCompletion and FcCompletionPanel (overall, by rarity and team), FcCardCarousel (nine pooled card nodes, keys, wheel, swipe), FcCardInspector (zoom, turn over, previous and next, attribute bars by rating tier, duplicate actions through the same controller calls), FcCardCompare (side by side, bars, badge split), NEW markers (first look baselines everything; opening a card clears its marker), a featured card on the hub, and a collection screen with a filter bar that rebuilds only the results. One node per card: 2,000 cards build in about 50 ms, so no virtualisation was needed (the plan's virtualised grid was dropped for that reason). Results: docs/validation/ui/phase5_results.txt.

## 2026-11-20: UI/UX polish, Phase 6 (packs and reveal)

FcPackArt (procedural wrapper art tinted by the pack's best possible rarity, with a tear animation), FcPackReveal (pack tears open, cards lie face down, each click flips the next one in rolled order; effects by rarity: glow, light sweep, flash, particles, shake, a banner for legendary; skip at any time; summary best-first with NEW and DUPLICATE marks, what each duplicate is worth in shards, and the collection progress bar). Integrity: the reveal only reads the committed opening (tests prove the saved profile is byte-identical through reveal, skip and until Done, that the order equals the rolled order, that skipping equals watching, and that Done acknowledges exactly once). The market screen shows pack art, best pull, published odds and pity. The hardened test runner found and helped fix a real bug (a banner fade running on a freed label). Results: docs/validation/ui/phase6_results.txt.

## 2026-11-20: UI/UX polish, Phase 7 (player showcase and unified profile)

FcPlayerVisual (the one deterministic resolver: FNV-1a hash of a stable key, stored Career appearance wins, no game RNG, never writes data; tiers 0 monogram, 1 portrait art, 2 stylised procedural figure; tiers 3 and 4 reserved and not built, D5), FcPlayerFigure (draws every tier), FcPlayerPortrait, FcUniformPreview, FcShowcaseStage (idle bob; reduced motion still), FcPlaystyle (style summary from data/ui/playstyle_labels.json), FcPlayerPresentation (Owner player, Career player and Dynasty card become one read-only view-model) and FcPlayerProfile (tabs shown only where data exists). Dynasty cards now draw their player through the resolver, and two editions of one player share a face. The Owner roster's profile popup is the new profile; the card inspector has a Player profile button. Identity tests (D-050): pinned hash values, same visual on card, roster row, post-game line, trade, comparison, showcase and profile, face unchanged by team moves, ratings, injuries or time, no global RNG and no RNG words in the visual code, subjects and player data unmodified, 300 players give at least 250 distinct looks. Results: docs/validation/ui/phase7_results.txt.

## 2026-11-20: UI/UX polish, Phase 8 (remaining Dynasty screens and mobile layouts)

Every Dynasty screen wraps its text and flows its columns so it fits a 412 px phone; tables become cards on a phone; the bottom navigation bar and touch-sized controls are used in the mobile layout; the starting five stand on a half court (FcLineupCourt); collection, detail, lineup, packs and play screens use the Phase 4-7 components. Results: docs/validation/ui/phase8_results.txt.

## 2026-11-20: UI/UX polish, Phase 9 (post-game presentation)

FcPostGameModel (pure view-model), FcPostGameScreen (score bug hero, line score, player of the game, performers, after-the-game, team comparison bars, team tabs) and FcPostGame adapters for Owner, Career and Dynasty; data/ui/pog.json; read-only box pass-through (D-053). Results: docs/validation/ui/phase9_results.txt.

## 2026-11-20: UI/UX polish, Phase 10 (Career and Owner polish)

Career creator is five steps (Identity, Body, Look, Skills, Review) with a live showcase preview built by the one visual resolver, one column so it fits a phone (744 px down to 360 px); the Career hub shows the player portrait and opens the shared profile; the Owner Overview uses KPI strips; Creator Studio adopts the game theme and fonts through a third junction (assets). The full 13-tab Owner conversion to the kit continues to be incremental (D6: Owner stays desktop-designed). Results: docs/validation/ui/phase10_results.txt.

## 2026-11-20: UI/UX polish, Phase 11 (audio)

FcAudio (owned by FcApp, FcAudio.cue), FcAudioSynth, data/ui/audio.json sound map with 17 sounds on UI/SFX/Music buses; rarity stings in C major climbing in five tiers; every button clicks; toasts, flips, pack tears, rewards and game results have cues; Sound panel in Settings with volumes, mute and vibration (preferences.cfg [audio]). No third-party audio (D-054). Results: docs/validation/ui/phase11_results.txt.

## 2026-11-20: UI/UX polish, Phase 12 (onboarding, UX states, accessibility sweep)

FcHints (data/ui/hints.json: 7 first-run hints for Dynasty and Career screens, dismissed state in the UI sidecar file, Hints controls in Settings, a Hints card with Got it and Turn hints off); audit tests for empty states (every Dynasty tab on a new profile, both layouts), focus reach (every enabled button and card takes focus), dialog back handling and a wider contrast audit (rarity colours on their cards, mastery frames, accents). Results: docs/validation/ui/phase12_results.txt.

## 2026-11-20: UI/UX polish, Phase 13 (full game presentation and release readiness)

test_release_readiness.gd (window-shape matrix, D6 800 px and phone-with-large-text ratchets, navigation, performance), regression digest against the pre-UI commit, simulation/economy/click/Studio checks, final screenshot library, docs/RELEASE_READINESS.md. career_click_test.gd updated for the five creator steps; CI links Studio assets. Results: docs/validation/ui/phase13_results.txt.

## 2026-11-20: UI/UX polish, Phase 3 (shell, navigation, notifications, layout), D-051

Built after the founder reviewed milestone 1 and said "continue". `src/ui/shell/` (`FcScreenHost`, `FcNavigator`, `FcModalHost`, `FcNotifier`, `FcLayoutProfile`) plus `FcNavBar`; `FcApp` now sits on the shell. Visible results: a redesigned main menu (mode cards with status chips; 820 px down to 393 px), a Settings screen (text size, reduce motion, layout override, tutorial, content folder), a confirmed Delete, toasts instead of the bottom message line, Escape and Android back, a loading overlay for slow actions, the three skins applied (Owner letterhead and team colours, Career lower third and grid, Dynasty spotlight), and Dynasty navigation as top tabs on desktop and a bottom bar with More on mobile. Dynasty collection and packs already fit a 412 px phone; the hub and lineup still scroll sideways (Phase 8). Owner and Career fit 800x600, and wider screens scroll sideways.
Found by the click test and fixed with a regression test: a toast covered a button and swallowed the click (toasts now pass clicks through on desktop). Also fixed: the lower third no longer re-cases text (a Career test caught it). One existing assertion changed on purpose (the main-menu card text). Tests: see `docs/validation/ui/phase3_results.txt`. Not yet: Owner and Career screens on the kit (Phase 10), Dynasty mobile layouts (Phase 8), a notification history screen, real-device checks. **Phase 4 (card system) waits for the founder's go-ahead.**

## 2026-11-20: UI/UX polish, milestone 1 (Phases 0 to 2), D-047 to D-050

Plan approved by the founder (`docs/UI_POLISH_PLAN.md`); this milestone built the foundation and **stops before Phase 3** (screen shell, navigation, notifications, responsive layouts), which needs the founder's go-ahead.
- **Phase 0, guardrails:** a ratchet that counts style literals in `src/ui` (`test_ui_style_lint`), a ratchet on the smallest window each screen needs (`test_ui_layout`, baseline measured on the original code), a live test runner for anything that needs the scene tree (`tests/run_live_tests.gd`; the unit runner cannot test tweens, timers, focus or `Range` signals), an extended screenshot tool and `tools/screenshot_matrix.ps1`, and before/after screenshots in `docs/validation/ui/`. Findings are in the plan (section 2): `last_game` lacks period scores (D-049 applies), the main menu is 820 px wide (above the 800 px minimum), the text-size setting did not scale headings.
- **Phase 1, tokens and theme:** `FcUiTokens`, Inter and Barlow Condensed (`assets/fonts`, OFL), `FcUiTheme` rebuilt on the tokens with type-variations, `FcModeSkin` (Neutral, Broadcast, Collectible, Franchise; whitelist only), `FcUiRatingTiers` (`data/ui/rating_tiers.json`), `FcUiContrast`, the Reduce motion preference, and a text scale that reaches headings and labels. The contrast test made two colours lighter (danger red, slate tier).
- **Phase 2, component kit:** `src/ui/kit/` (buttons, tabs, choice groups, dropdowns, toggles with drawn switches, sliders, progress, search, filter bar, modal, toasts, loading, empty states, data table with a compact card form, rating badge, stat tile, line and bar, scorebug, lower third, KPI strip, letterhead, status chip), `FcMotion` (reduced-motion aware), Lucide icons (`assets/icons/lucide`, ISC), and the development-only Component Gallery (main menu in editor runs, or `--gallery`).
- **Tests:** 882 passed (819 before, 63 new) plus 21 live tests; Owner click test 67/0, Career click test 18/0, Studio smoke PASS. No simulation, generation, progression, pack, card-format, save-format or Studio code was changed (the only non-UI source change is `reduce_motion` in `preferences.cfg` handling).
- **Not yet:** Phase 3 onward. Existing screens still use `FcUiTables`; they now wear the new theme but have not been migrated to the kit. Audio and the UI-only sidecar store come in their phases.

## 2026-11-20: Dynasty Mode built (offline), D-043 to D-046

Per the founder's assignment (founder asleep; recommended answers used): all of `docs/DYNASTY_MODE_PLAN.md` milestones 0 to 11. Domain layer in `src/dynasty/`, records in `src/data/dynasty/`, a separate versioned profile file (`FcDynastyStore`), `FcDynastyController`, screens in `src/ui/dynasty/`, content schema extensions validated in `src/content/dynasty_content_rules.gd`, tests prefixed `test_dynasty_*`. The simulator was not changed. Official content is not invented: the bundled starter release is too small to play, so Dynasty shows an onboarding message until a real release is published; `./tools/dynasty_sample_draft.ps1` creates a clearly labelled invented draft for trying it. Not visually reviewed (headless only). See the plan file for open decisions.

## 2026-11-20: content publishing (Creator Studio to the game), D-042

Built in six milestones, each committed and pushed at the founder's request: the shared format (`src/content/`: manifest, canonical checksums over raw bytes, safe paths, validator, card revision rules), the immutable local store with a crash-safe active pointer, owner approval bound to one draft and single use, the publisher, the draft workspace, the game-side loader (fallback along `previous_release_id`, then the bundled starter release, with a visible report), rollback, ownership by stable ids, preferences, and `App.content`. Creator Studio is a separate Godot project (`creator_studio/`) reaching `src` and `data` through git-ignored junctions (`./tools/link_studio.ps1`); it has one screen with drafts, a check report, a confirmed approval button and a release list with rollback. Tests: 758 (48 new); Dynasty brings the suite to 819. Also verified: Studio smoke test, `./tools/publish_demo.ps1`, and a fresh clone (link script, import, full suite, Studio smoke).
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
