# UI/UX Polish and Presentation Milestone: plan

Status 2026-11-20. Approved by the founder with decisions D1 to D7 (see `docs/DECISIONS.md`, D-047 to D-050).
Phases 0 to 2 are the first implementation milestone. **Phase 3 and later do not start without a report to the founder
(work done, test results, screenshots, open issues) and an explicit go-ahead.**

Goal: a cohesive, premium Full Court UI: one design system, three presentation personalities, collectible-quality cards
and pack opening, one player identity everywhere, a results-first post-game screen, consistent motion and audio.
Presentation stays separate from authoritative game logic.

## 0. Guardrails (apply to every phase)

Do not change: simulation logic, player development, player generation, Dynasty pack outcomes, card content formats, save
data structures, Creator Studio publishing contracts. Screens call controllers, never engines. Presentation code never
writes game state and never uses game RNG. Anything outside the existing UI architecture is listed in section 8 and needs
approval. Every phase ends with the full suite green, the screenshot matrix updated and one commit.

## 1. Founder decisions (approved 2026-11-20)

| # | Decision |
|---|---|
| D1 | Icons: **Lucide** (ISC licence), bundled as SVG. |
| D2 | A **UI-only sidecar store** (`user://ui_state.cfg`) is approved (for example "seen card" markers). |
| D3 | A **read-only box-score pass-through** to the post-game screen is approved **if Phase 0 confirms it is needed**. |
| D4 | Audio sourcing is **deferred to Phase 11**. No unlicensed assets are introduced, ever. |
| D5 | Player visuals **T0 to T2 now**; the architecture is designed for T3 and T4 but they are **not implemented**. |
| D6 | Owner and Career are **desktop-designed**; smaller screens stay usable, not mobile-optimised (minimum supported window 800x600). |
| D7 | Career uses the **Broadcast** presentation skin. |
| Kept | Procedural pack artwork; results-first gameplay presentation (no live playback); Creator Studio entry point is development-only. |
| Added | **Consistent Player Visual Identity** (Phase 7): one deterministic, shared resolver; no game RNG; never modifies player data; tested. |
| Fixed earlier | Hardwood Night palette; Barlow Condensed (display) and Inter (body). |

## 2. Phase 0 findings (verified in the code, 2026-11-20)

1. **`last_game` is not enough for the post-game screen (D3 applies).** `FcDynastyMatch.summarize()` returns only the user's side: score, margin, overtimes, opponent, a short team block (points, rebounds, assists, steals, blocks, threes, free throws) and the user's player lines. It has **no period scores, no opponent player lines and no shooting splits**. The full `FcBoxScore` (period scores, both sides' players, totals, advanced) exists inside `FcDynastyPlay` but is dropped. Phase 9 needs the transient box passed through `FcDynastyController.last_game` (in memory only, never saved).
2. **Owner Mode already keeps full boxes**: `controller.season().recent_boxes` holds `FcBoxScore` dictionaries (period scores included). `box_score_text()` renders them as text.
3. **Awards exist for Owner**: `FcSeason.awards` holds `mvp`, `scoring_champion`, other single-winner awards (by player id) and `all_league_first` / `all_league_second` (player id lists). Dynasty cards have no awards.
4. **Career records seasons** (`FcCareerProfile`: one row per season with `games`, `points`, `rebounds`, `assists` and an `awards` list), `milestones` (claimed keys) and `stage` (up to LEGACY). There is no separate "achievements" system; Phase 7 presents seasons, awards and milestones.
5. **Appearance data exists only for Career players** (`skin`, `hair`, `face`, `facial_hair` from `data/career/build_rules.json`). Teams have `FcTeamBranding` colours (`primary`, `secondary`, `accent`) and a `logo_key` with no art. Dynasty cards have a single `art` path (`FcContentCatalog.art_path`). There are no full-body, pose, uniform or equipment fields anywhere, so T3 and equipment have no data today.
6. **Text size bug confirmed.** `FcUiTheme.build` sets only `default_font_size`; `FcUiTables.label(text, size)` and `FcCardView` use absolute sizes, so headings do not follow the Small/Normal/Large setting.
7. **No colours are hardcoded in screens** (screens use `FcUiTheme` and `FcDynastyStyle`), but font sizes are literal at almost every label call; the Phase 0 lint test ratchets both.
8. **The full test suite takes about 10 minutes** on the founder's machine; use `--filter=` for quick loops.
9. **Dynasty cards are fixed-size artwork.** Their text does not follow the text-size setting (a larger font would clip inside a 150x214 card); Phase 4 scales a card by its size instead.
10. **The unit test runner cannot test anything that needs the scene tree.** It runs inside `_initialize`, before the first frame, and nodes added then are not "inside the tree": tweens, timers, focus and `Range` signals silently do nothing (a `Timer.start()` reports "not inside the scene tree"). This is why the existing 819 tests never exercised animation. Milestone 1 adds a second runner (`tests/run_live_tests.gd`) that starts after the first frame and lets tests `await`.
11. **The main menu does not fit the D6 minimum window.** Measured on the original code (commit `6c963ac`), the smallest window each screen needs is below. `main_menu` (820 px wide) is wider than the 800 px minimum; Phase 3 must fix it. Every Dynasty screen needs about 789 px because of the nine-button navigation row, which is the reason for the Phase 3 bottom navigation and the Phase 8 mobile layouts. Owner and Career screens already fit 800 px.

| Screen | Width | Height |
|---|---|---|
| main_menu | 820 | 303 |
| new_league | 775 | 403 |
| career_home / career_creator | 432 / 744 | 196 / 121 |
| dynasty_entry | 532 | 303 |
| dynasty_hub, collection, packs, lineup | 789 | 148 |
| owner_overview, owner_roster | 715 | 179 |

(Heights are small because tabs scroll. These numbers are the ratchet baseline, `tests/support/ui_layout_baseline.json`; the main menu height rose from 303 to 338 in milestone 1 because of the new Reduce motion setting and the development-only gallery button.)

## 3. Visual identity and design system

**Foundation: Hardwood Night.** Tokens in `FcUiTokens` (`src/ui/ui_tokens.gd`):

- Surfaces: background `#0B1020`, surface `#111A2E`, raised `#18233D`, border `#2A3856`.
- Colours: primary `#F58C29`, info `#3DA5FF`, gold `#FFC857`, success `#3DD68C`, warning `#F5B93A`, danger `#F2605D` (lightened from the proposed `#F0524F` because the contrast test found it below 4.5:1 on raised surfaces).
- Text: `#EAF0FA`, muted `#9AA8C2`, disabled `#5F6B84`. A unit test requires at least 4.5:1 for text on every surface, in every skin.
- Type: display Barlow Condensed (headings, big numerals), body Inter (tabular figures for stats). Scale 40, 32, 28, 22, 18, 15, 13, 11, multiplied by the text scale (Small 0.87, Normal 1, Large 1.2).
- Spacing 4, 8, 12, 16, 24, 32, 48. Radii: control 6, panel 12, card 12, modal 16. Three elevation levels. Motion 90 / 180 / 280 ms.
- Touch target 44 px on touch layouts, 32 px on desktop.
- Rating ramp (slate, cyan, orange, gold) from `data/ui/rating_tiers.json`; rating colours are never rarity colours.
- Rarity styles in a registry with a safe fallback for unknown ids (Phase 4).

**Three personalities, one system.** A mode skin (`FcModeSkin`) may change only a whitelist: accent colour, background treatment, density, header style, motion intensity, numerals. Components are never forked per mode, and every skin must pass the contrast test (a franchise accent that is too dark is lightened until it passes).

| Skin | Mode | Character |
|---|---|---|
| Broadcast | Post-game in every mode, Career | Condensed uppercase numerals, scorebug and lower-third layouts, stat-comparison bars, team-colour wipes |
| Collectible | Dynasty | Saturated accents, textured and spotlight backdrops, foil and shimmer, rarity glow, the loudest motion and audio |
| Franchise | Owner | Calm palette tinted by the user's franchise colours, letterhead headers, KPI strips, status chips, dense tables, minimal motion |
| Neutral | Menu, settings, shell | Plain Hardwood Night |

**Responsive model.** Desktop and mobile are separate presentation targets (a layout profile service arrives in Phase 3).
Desktop: dense layouts, horizontal navigation, larger tables and dashboards. Mobile (Dynasty is the release target):
touch-first, bottom navigation, stacked layouts, condensed statistics, 44 px targets. Shared components ship both
compositions. Owner and Career are tested at 800x600, 1024x768, 412x915 and 360x800 and must stay usable (nothing
clipped or unreachable, tables scroll inside their container), but are not redesigned for mobile (D6).

## 4. Component kit (`src/ui/kit/`)

Code-built `Control` subclasses with theme type-variations; each has the states default, hover, focus, pressed, disabled,
selected, loading and error where they make sense. A dev-only Component Gallery shows every component, state and skin.

- Core: `FcButton` (primary, secondary, destructive, ghost, icon), `FcTabBar`, `FcDropdown`, `FcToggle`, `FcChoiceGroup`, `FcSlider`, `FcProgress`, tooltip styling, `FcModal`, `FcToast` and `FcToastStack`, `FcPanel`, `FcDataTable`, `FcFilterBar`, `FcSearchField`, `FcLoading`, `FcEmptyState`, `FcRatingBadge`, `FcStatTile`.
- Broadcast set: `FcScoreBug`, `FcLowerThird`, `FcStatBar`, `FcStatLine`.
- Franchise set: `FcKpiStrip`, `FcLetterhead`, `FcStatusChip`.
- Services: `FcMotion` (tween helpers that honour reduced motion), `FcUiIcons` (Lucide loader), `FcUiFonts`.
- Collectible set (card face, carousel, inspector, compare, pack reveal): Phases 4 to 6.

## 5. Phases

Each phase lists objectives, files, dependencies, tasks, acceptance and tests.

### Phase 0: Guardrails (BUILT in milestone 1)
- **Files:** `tools/screenshot.gd` and `tools/screenshot_matrix.ps1` (Dynasty, Career, Gallery screens; size matrix), `tests/unit/test_ui_style_lint.gd`, `tests/unit/test_ui_layout.gd`, `tests/support/ui_style_scan.gd`, baselines under `tests/support/`, `docs/validation/ui/`.
- **Tasks:** ratcheting style lint; layout baseline (minimum window size per screen) that may not grow; baseline screenshots; the findings in section 2.
- **Acceptance:** suite green; baseline screenshots at 412x915, 1024x768 and 1280x800 (`docs/validation/ui/before` is the original code, `docs/validation/ui/milestone1` the result).
- **Delivered beyond the plan:** the live test runner (finding 10), `tools/run_live_tests.ps1`, a CI step for it, and screenshot options (`skin=`, `text=`, `section=`, `touch=`, `demo=`, true-pixel sizes).

### Phase 1: Tokens, fonts, theme, skins (BUILT in milestone 1)
- **Files:** `src/ui/ui_tokens.gd`, `ui_theme.gd`, `ui_fonts.gd`, `ui_contrast.gd`, `ui_mode_skin.gd`, `ui_rating_tiers.gd`, `assets/fonts/` (Inter, Barlow Condensed, OFL licence texts), `data/ui/rating_tiers.json`, `src/save/preferences.gd` (additive: reduce motion).
- **Tasks:** tokens; theme built from tokens with type-variations; text scale applied to every labelled size; skins with whitelist; contrast, scale, skin and preference tests; export scripts include `assets/`.
- **Acceptance:** Large text scales headings and labels; every existing screen renders with the new fonts and colours; no saved-data change. (Dynasty card faces keep fixed text sizes on purpose: finding 9.)
- **Deviations:** danger red lightened to `#F2605D` and the slate rating tier to `#A0AABF` after the contrast test failed; the audio and haptics preference fields are not added yet (they arrive with Phase 11, to avoid placeholder settings).

### Phase 2: Component kit, motion, gallery (BUILT in milestone 1)
- **Files:** `src/ui/kit/*`, `src/ui/ui_motion.gd`, `src/ui/ui_icons.gd`, `assets/icons/lucide/` (with licence), `src/ui/kit/component_gallery.gd`, `app.gd` (development-only gallery entry).
- **Acceptance:** headless state tests per component, live tests for tweens, timers, focus and input; gallery screenshots per skin and layout.
- **Deviations:** the Lucide icons are imported at 2x and limited to 20 px inside buttons (`icon_max_width`); the search field draws its own glyph because `LineEdit.right_icon` cannot scale; the toggle switch icons are drawn procedurally by the theme in the accent colour; the dev gallery entry is shown only in editor runs or with `--gallery`.

### Phase 3: Shell, navigation, notifications, layout profile (BUILT; founder go-ahead given after the milestone 1 report)
- **Built:** `FcLayoutProfile` (desktop or mobile from the OS, touch and window width, with a Settings override; safe-area margins), `FcNavigator` (hierarchical Back: each screen declares its parent), `FcModalHost` (a dialog stack: only the top one listens), `FcNotifier` (messages become toasts, with a history), `FcScreenHost` (frame, backdrop per skin, scroll area, bottom bar slot, dialog and toast layers), `FcNavBar` (top tabs on desktop, bottom bar with More on mobile), `FcApp._reset(title, opts)` (the compatibility shim: old screens still call `_reset(title)`), fade-in only when the screen changes, `run_with_loading` for slow actions, Escape and the Android back button, a redesigned main menu and a Settings screen, a confirmed delete, the three mode skins applied to the screens, the Owner letterhead and the Career lower-third.
- **Measured:** the smallest window the main menu needs fell from 820 to 393 px; Dynasty collection from 789 to 300 px and packs to 340 px; no screen got wider (`tests/support/ui_layout_baseline.json` is tightened). Owner and Career screens are usable at 800x600 (a screen wider than the window scrolls sideways instead of being cut off).
- **Deviations and decisions** (D-051): Back is hierarchical rather than a history stack; the old `app._message` label is kept hidden as the text record (tests and tools read it) while the toast is what the player sees; the only existing test assertion changed is the main-menu card text ("Owner Mode  (Available)" became a title plus a status chip); toasts pass clicks through on desktop (a toast once covered "Sign selected free agent"; found by `tools/click_test.gd`, regression test added); the lower third shows text as given (upper-casing a player name broke the Career test and altered data); the bottom navigation belongs to the frame, not to a screen.
- **Not done (belongs to later phases):** Owner and Career screens still use `FcUiTables` (migrated in Phase 10); the Dynasty hub, lineup and tables are still desktop layouts that scroll sideways on a phone (Phase 8); no screen-to-screen slide transition (fade only); the notification history has no screen yet; no real-device check of safe areas or Android back.

### Phase 4: Card system (BUILT)
`FcCardView.build(row, options)` keeps its API; new `FcCardFace`, `FcRarityStyle` (registry with fallback), states hover / focus / **selected** / **inspected**, five sizes, flip, per-rarity treatments, owned / unowned / unavailable. Studio can reuse the face.
- **Built (autonomous run, founder pre-approved all remaining phases):** new src/ui/cards (FcRarityStyle: five rarities each with its own frame, background pattern and effects, with a safe fallback for unknown rarities; FcCardFace: the whole card drawn in one node with hover lift, focus ring, selected, inspected, face-down back, flip, a shader light sweep on rare and up, mastery frames, NEW and other tags, accessible text). FcCardView.build keeps its API, so every Dynasty screen already uses the new cards. The gallery has a Cards section (all rarities, states, sizes). Card text is drawn, so tests read a card's accessible_text().

### Phase 5: Collection, carousel, inspector, compare, completion (BUILT)
Grid and carousel browse modes (virtualised; carousel builds the focused card plus 3 neighbours each side), inspector overlay (zoom, tilt, flip) replacing the `AcceptDialog`, side-by-side compare, completion rings by team / rarity / edition, NEW markers (sidecar store, D2), featured card on the hub chosen from existing data, shared-element transitions. No new content fields.
- **Built (autonomous run, founder pre-approved all remaining phases):** FcUiState (user://ui_state.cfg, D-048: seen cards and browse mode; never in a save), FcCompletion and FcCompletionPanel (overall, by rarity and team), FcCardCarousel (nine pooled card nodes, keys, wheel, swipe), FcCardInspector (zoom, turn over, previous and next, attribute bars by rating tier, duplicate actions through the same controller calls), FcCardCompare (side by side, bars, badge split), NEW markers (first look baselines everything; opening a card clears its marker), a featured card on the hub, and a collection screen with a filter bar that rebuilds only the results. One node per card: 2,000 cards build in about 50 ms, so no virtualisation was needed (the plan's virtualised grid was dropped for that reason).

### Phase 6: Packs and reveal (BUILT)
Procedural pack art tinted by tier, odds disclosure, reveal state machine that only reads the committed `opening`; effect strength by rarity; skip at any time; duplicate chip with shard value; final summary. **Integrity tests:** profile save identical before and after the reveal; reveal order equals `opening["cards"]`; only `acknowledge_opening` is called; skip and full playback give the same result.
- **Built (autonomous run, founder pre-approved all remaining phases):** FcPackArt (procedural wrapper art tinted by the pack's best possible rarity, with a tear animation), FcPackReveal (pack tears open, cards lie face down, each click flips the next one in rolled order; effects by rarity: glow, light sweep, flash, particles, shake, a banner for legendary; skip at any time; summary best-first with NEW and DUPLICATE marks, what each duplicate is worth in shards, and the collection progress bar). Integrity: the reveal only reads the committed opening (tests prove the saved profile is byte-identical through reveal, skip and until Done, that the order equals the rolled order, that skipping equals watching, and that Done acknowledges exactly once). The market screen shows pack art, best pull, published odds and pity. The hardened test runner found and helped fix a real bug (a banner fade running on a freed label).

### Phase 7: Player showcase and unified profile (BUILT)
- `FcPlayerPresentation`: read-only adapter from an `FcPlayer`, Career profile or Dynasty card (identity, physical, role and playstyle summary, attributes, badges, stats, history, awards, progression).
- **Player visual resolver (`FcPlayerVisual`), consistent identity requirement:** a player has **one** visual representation wherever they appear (roster, profile, post-game, trade proposal, comparison, card, lineup). The resolver is **pure and deterministic**: input is a stable key (the entity's id plus the data it owns: Career `appearance`, Dynasty card art, team branding), output is a description of what to draw. It **never consumes game RNG** (a local hash of the key, not `FcRng`), **never reads or writes anything it does not own, and never modifies player data**. Every screen gets the visual only through the resolver.
- Tiers: **T0** monogram; **T1** card portrait art; **T2** stylised procedural bust and figure (Career uses stored `appearance`; Owner players use a look derived from the player id, never stored). **T3** (full-body pose sprites via an optional presentation manifest) and **T4** (richer or 3D rendering) are designed as provider slots behind the same interface and are **not implemented** (D5).
- `FcShowcaseStage` (spotlight, pedestal, idle parallax; asks the resolver for a named pose and uses the best available); `FcUniformPreview` (jersey from `FcTeamBranding` colours, number, abbreviation). Equipment has no data and is not built.
- Profile tabs: Overview, Attributes, Badges, Stats, History, Awards. A mode hides what it has no data for. Progression by mode: Career (level, XP, points, potential ceiling, season history), Owner (overall against potential and peak age), Dynasty (static ratings by design: mastery, frame, in-game stats).
- **Tests for identity:** same key gives the same visual description across calls and across screens; changing unrelated game state does not change it; the resolver leaves `FcRng` streams and player data untouched (fingerprint before and after); two different players differ; roster, profile, post-game, trade and comparison views obtain their visual from the same resolver call.
- **Built (autonomous run, founder pre-approved all remaining phases):** FcPlayerVisual (the one deterministic resolver: FNV-1a hash of a stable key, stored Career appearance wins, no game RNG, never writes data; tiers 0 monogram, 1 portrait art, 2 stylised procedural figure; tiers 3 and 4 reserved and not built, D5), FcPlayerFigure (draws every tier), FcPlayerPortrait, FcUniformPreview, FcShowcaseStage (idle bob; reduced motion still), FcPlaystyle (style summary from data/ui/playstyle_labels.json), FcPlayerPresentation (Owner player, Career player and Dynasty card become one read-only view-model) and FcPlayerProfile (tabs shown only where data exists). Dynasty cards now draw their player through the resolver, and two editions of one player share a face. The Owner roster's profile popup is the new profile; the card inspector has a Player profile button. Identity tests (D-050): pinned hash values, same visual on card, roster row, post-game line, trade, comparison, showcase and profile, face unchanged by team moves, ratings, injuries or time, no global RNG and no RNG words in the visual code, subjects and player data unmodified, 300 players give at least 250 distinct looks.

### Phase 8: Remaining Dynasty screens and mobile layouts (BUILT)
Hub (featured card, completion, recommended action), court-shaped lineup with tap-to-select, play, challenges, bracket, season reward track, market, profile entry. The full Dynasty loop completes in the click test at 412x915 with touch emulation.
- **Built (autonomous run, founder pre-approved all remaining phases):** Every Dynasty screen wraps its text and flows its columns so it fits a 412 px phone; tables become cards on a phone; the bottom navigation bar and touch-sized controls are used in the mobile layout; the starting five stand on a half court (FcLineupCourt); collection, detail, lineup, packs and play screens use the Phase 4-7 components.

### Phase 9: Post-game presentation (results-first, no sim change) (BUILT)
One shared screen for all modes in the Broadcast skin: final score hero, quarter-by-quarter line score, team comparison bars, top performers, player of the game (a display ranking from `data/ui/pog.json`, labelled as such), full player stat lines in tabs, season implications where supported (Owner record and standing; Dynasty season points and objectives; Career season record and the player's line against their average), rewards and progression earned. **Needs the D3 pass-through** of the transient `FcBoxScore` in `FcDynastyController.last_game` (not saved).
- **Built (autonomous run, founder pre-approved all remaining phases):** FcPostGameModel (pure view-model), FcPostGameScreen (score bug hero, line score, player of the game, performers, after-the-game, team comparison bars, team tabs) and FcPostGame adapters for Owner, Career and Dynasty; data/ui/pog.json; read-only box pass-through (D-053).

### Phase 10: Career and Owner polish (BUILT)
Career creator as steps with a live card and figure preview; Career hub on the shared profile; Owner franchise skin (franchise colours, letterhead, KPI strips), the 13 tabs on the kit; small-window pass for Owner and Career; Studio adopts the theme and card face.
- **Built (autonomous run, founder pre-approved all remaining phases):** Career creator is five steps (Identity, Body, Look, Skills, Review) with a live showcase preview built by the one visual resolver, one column so it fits a phone (744 px down to 360 px); the Career hub shows the player portrait and opens the shared profile; the Owner Overview uses KPI strips; Creator Studio adopts the game theme and fonts through a third junction (assets). The full 13-tab Owner conversion to the kit continues to be incremental (D6: Owner stays desktop-designed).

### Phase 11: Audio
`FcAudio` owned by `FcApp` (not an autoload); buses Master, UI, SFX, Music; data-driven sound map (`data/ui/audio.json`); missing files are silent. Identity "arena and hardwood": soft wood-and-leather taps for UI, paper-and-snap card flips, rarity stings in one key that climb (single bounce, chime, horn, crowd swell, arena horn and roar), a short ascending motif for rewards and achievements. Independent volumes and mutes, saved in `preferences.cfg`; the game is fully playable muted. Optional haptics toggle. **Sound sourcing is decided here (D4); nothing unlicensed is added.**

### Phase 12: Onboarding, UX states, accessibility sweep
First-run hints for Career and Dynasty; empty / loading / error / success audit; focus order and controller pass; contrast audit.

### Phase 13: Full Game Presentation and Release Readiness
Cross-mode visual consistency audit; complete navigation testing; resolution and aspect-ratio matrix (360x800 to 2560x1080, 4:3 and 21:9, text scales); animation performance validation; card collection performance (100, 500, 2,000 cards, grid and carousel); mobile usability review (Dynasty, device or emulator); audio review; accessibility review; regression across all game systems (suite, click tests, `studio_smoke`, simulation calibration, save integrity, pack outcomes identical for a fixed seed); final screenshot library in `docs/validation/`.

## 6. Animation specification

Tween-based through `FcMotion` (code-built UI; cheap and killable), `CPUParticles2D` for particles, a small number of `canvas_item` shaders (foil, sweep) that work on `gl_compatibility`; no HDR bloom, so glow is faked with gradients. At most one full-screen effect at a time; flashes under 3 per second; no animation inside a scrolling grid of more than 12 items; shaders paused off-screen; animation callbacks never call game-state methods. Reduced motion (a preference) makes every animation instant, except fades capped at 80 ms.

| Interaction | Behaviour | Time | Reduced |
|---|---|---|---|
| Screen push / pop | Slide 24 px plus fade | 220 ms | 80 ms crossfade |
| Tab / page change | Cross-fade | 150 ms | instant |
| Button hover / press | Brighten; press scales to 0.97 | 90 / 60 ms | colour only |
| Focus | Ring fades in | 100 ms | instant |
| Card hover | Lift, light sweep (rare and up) | 140 ms | outline only |
| Card flip | Scale X to 0, swap, back to 1 | 280 ms | fade swap |
| Card entrance / exit | Scale 0.85 to 1 plus fade, stagger 40 ms (max 8) | 200 ms | 80 ms fade |
| Carousel | Snap, centred card larger | 220 ms | instant snap |
| Grid to inspector | Card flies from its rectangle to centre | 260 ms | fade |
| Modal | Scrim fade, panel rises 12 px | 180 ms | fade |
| Toast | Slide in, hold 3 s (errors 6 s), fade | 200 ms | fade |
| Loading | Spinner or court-line sweep | loop | static dots |
| Pack open and reveal | Shake, tear, burst, fan out; common 0.35 s to legendary 1.4 s | skippable | cut |
| Progress / rewards | Bars fill, counters tick | 400 to 800 ms | jump |
| Post-game | Score counts up, bars draw in, player of the game slides in | about 1.5 s, skippable | jump |
| NEW marker | Soft pulse, three times | 1.5 s | static glow |

## 7. Testing and validation

- **Compatibility:** existing UI tests rely on `FcApp.setup()`, `show_tab`, `ui.ctl`, `_form` keys, `TAB_NAMES` and `FcUiTables.table` (a `Tree`); these stay stable.
- **Style lint:** `test_ui_style_lint.gd` counts literal `Color(` and literal font-size overrides in `src/ui` outside the theme, tokens and kit, and fails when a count rises above `tests/support/ui_style_baseline.json` (lower the baseline when a screen is migrated).
- **Layout baseline:** `test_ui_layout.gd` records each screen's minimum window size and fails if it grows (`tests/support/ui_layout_baseline.json`); later phases tighten it toward the Dynasty mobile target.
- **Components:** headless build and state tests for every component, in every skin, text scale and touch mode.
- **Motion:** `FcMotion` reduced mode gives end states immediately; non-reduced tweens are stepped manually in tests.
- **Presentation integrity:** pack reveal, player visuals, presentation adapters and the post-game screen never change game state (fingerprint before and after) and consume no game RNG.
- **Screenshots:** `tools/screenshot_matrix.ps1` renders the matrix (needs a window); the gallery is the component reference. Shaders cannot be checked headless, so visual checks are screenshots plus a manual checklist.
- **Regression:** the full suite, `click_test`, `career_click_test`, `ui_playthrough`, `studio_smoke`, and `simulate_games` unchanged.

## 8. Changes outside the existing UI architecture (all approved)

| # | Change | Why | Boundary |
|---|---|---|---|
| H1 | `user://ui_state.cfg` sidecar store (`FcUiState`) | "NEW" markers outlive a session without touching the Dynasty save | Not a save; no `DATA_VERSION` bump; safe to delete; first open treats existing cards as seen |
| H2 | Additive fields in `preferences.cfg` (reduce motion now; audio and haptics in Phase 11) | Settings required by the brief | Already separate from saves; loads with defaults |
| H3 | Pass the transient `FcBoxScore` through `FcDynastyController.last_game` | The post-game sections need period scores and both teams (confirmed by Phase 0 finding 1) | Read-only, in memory, never saved, no sim change |
| H4 | Optional player-visual manifest (`data/ui/player_visuals.json`) for T3 | Lets pose assets attach later without a card-format change | Presentation layer; **not built** until assets exist |
| H5 | `assets/` directories (fonts, icons, audio, shaders) | Fonts, icons, sound, shaders | Export scripts verified to include `assets/` |

## 9. Risks

Rebuild-on-navigate (the Phase 3 shim mitigates); Phase 7 scope (tiers ship independently); procedural figures looking cheap (keep T2 stylised); derived playstyle labels disagreeing with the sim (label as a summary, never feed back); skins drifting into three UIs (whitelist plus Phase 13 audit); card grid performance on mobile (virtualise, pause shaders); compatibility renderer limits (test shaders on a real Android device in Phase 4); synchronous sims freezing the window (loading overlay first); asset licensing (every asset follows `docs/LEGAL_CHECKLIST.md` section 4); audio fatigue (cooldowns, independent volumes); slow full suite (about 10 minutes).

## 10. Progress log

- 2026-11-20: plan approved; milestone 1 (Phases 0 to 2) built and reported. The founder said "continue"; Phase 3 was built (report in `docs/PROGRESS_LOG.md`). **Phase 4 onward wait for the founder's go-ahead.**
- 2026-11-20: Phase 4 built: card system
- 2026-11-20: Phase 5 built: collection, carousel, inspector, compare, completion
- 2026-11-20: Phase 6 built: packs and reveal
- 2026-11-20: Phase 7 built: player showcase and unified profile
- 2026-11-20: Phase 8 built: remaining Dynasty screens and mobile layouts
- 2026-11-20: Phase 9 built: post-game presentation
- 2026-11-20: Phase 10 built: Career and Owner polish
