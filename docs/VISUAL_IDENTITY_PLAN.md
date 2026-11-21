# Full Court — Visual Identity & UI Transformation Plan

Approved by the founder 2026-11-21 (D-057). Phases A-J run without hard stops: at each checkpoint Claude captures real Godot screenshots, writes a short summary into `docs/validation/ui/visual_identity/`, fixes anything it is not confident in with its best recommendation, then commits and pushes. Progress is recorded at the end of this file.


## 0. Context and key finding

The previous UI polish milestone (docs/UI_POLISH_PLAN.md, D-047 to D-056) already shipped a real foundation, which this milestone
**extends and does not rebuild**: `FcUiTokens`, `FcUiTheme` (code-built Theme, no .tres), `FcUiModeSkin` (4 skins), the kit (`src/ui/kit/`, ~30
components), `FcScreenHost`/`FcNavigator`/`FcLayoutProfile`/`FcModalHost`/`FcNotifier`, the card system (`src/ui/cards/`), player presentation
(`src/ui/player/`), `FcMotion` (reduced motion), `FcAudio` + synth, accessibility foundations, and the test net (1133 unit + 75 live tests,
viewport matrix, style-lint ratchet, contrast tests, script-error logger). Their public contracts are preserved.

Your proposed palette is already nearly what ships: BG #0B1020 (identical), SURFACE_RAISED #18233D (vs #17233D), GOLD #FFC857 (vs #FFB547),
PRIMARY #F58C29 (vs #FF8A24), INFO #3DA5FF (vs #39A9FF). Only the elevated tier (#202F4D) is missing.

Where it still looks like a prototype is outside the kit:
1. `src/ui/app.gd` (2,710 lines) builds every Owner/Career/menu/settings screen imperatively with legacy `FcUiTables` (plain `Tree`, 28 sites), 19 `OptionButton`, 17 `SpinBox`, 3 `ItemList` and 80 hard-coded label sizes. 12 of 13 Owner tabs are bare `Tree`s.
2. No brand art at all: no logo, splash, credits, team logo system, mode artwork or atmosphere; default Godot boot splash; empty icon slots in both export presets.
3. No data visualisation (Finances is labels and spinners; bracket is text panels).
4. Uneven quality: Dynasty collection/inspector/pack reveal and the shared post-game screen are strong; Career home/hub/develop, Owner trades/meeting/draft/staff/finances, About, new-league wizard and Creator Studio are default-control forms.
5. Player identity appears only in Career hub, post-game and profile; Owner rosters, standings, draft and trades show none.

## 1. Current UI architecture audit (retained findings)

- Scenes: only `scenes/main.tscn` (bare Control + `FcApp`) and `creator_studio/scenes/main.tscn`; all UI is code-built. Keep this pattern.
- Shell: `FcScreenHost` (backdrops flat/grid/spotlight, safe area, 1600 px content cap, overlay for modals/toasts, bottom bar); `FcNavigator` (hierarchical Back, D-051); `FcLayoutProfile` (desktop/mobile, 700/1100 px breakpoints, `phone_scale`, `safe_margins`).
- Kit: Button, ChoiceGroup, DataTable, Dropdown, EmptyState, FilterBar, KpiStrip, Letterhead, Loading(+Overlay), LowerThird, Modal, NavBar, Panel, Progress, RatingBadge, ScoreBug, SearchField, Slider, StatBar, StatLine, StatTile, StatusChip, TabBar, TabPages, Toast(+Stack), Toggle, ComponentGallery.
- Cards: `FcCardFace` (MINI 75x107, SMALL 112x160, STANDARD 150x214, DETAIL 225x321, HERO 300x428; flip, hover, `card_sweep` shader), `FcRarityStyle` (5 rarities, intensity 0-4), carousel, inspector, compare, `FcPackArt`, `FcPackReveal`.
- Players: `FcPlayerVisual.resolve` (FNV-1a deterministic identity; tiers T0 monogram, T1 `art_path` texture, T2 procedural figure; T3/T4 reserved, D-050). Identity fields: skin (6), hair style (8), face (6), facial hair (4), build (3), hair colour (5), uniform from team colours + number. `FcPlayerFigure` (156 lines `_draw`), `FcPlayerPortrait`, `FcShowcaseStage`, `FcUniformPreview`, `FcPlayerPresentation` (shared view-model), `FcPlayerProfile`.
- Saved appearance exists only for Career (`FcCareerProfile.appearance`); league players derive their look from their key and are not stored; `FcPlayer` has no appearance field (and will not get one).
- Team identity: `FcTeamBranding` = primary/secondary/accent hex + `logo_key` string ("no art exists yet"); `FcLetterhead` crest = abbreviation on colour, self-labelled stand-in.
- Motion: `FcMotion` single `reduced` flag (fades capped 80 ms); tweens in kit/cards/showcase; no AnimationPlayer, no screen transition system beyond a fade.
- Audio: `FcAudio` (8 voices, buses Master/UI/SFX/Music; not an autoload), `FcAudioSynth`, `data/ui/audio.json` 17 cues (the `.ogg` paths do not exist; all synth). `ui_back` has no call site. Settings already has mute + 4 volume sliders + haptics.
- Accessibility today: 3 text sizes, reduced motion, contrast helper/tests, focus rings, 44 px touch targets, modal focus. Missing: colour-blind/high-contrast modes, `[input]` map, gamepad/screen-reader validation.
- Scaling: 1280x800 `canvas_items` + `expand`; Owner/Career minimum 800x600 (D6); phone portrait for Dynasty.
- Coupling: Owner/Career screens call `FcGameController`/`FcCareerController` directly (~226 sites in app.gd); Dynasty only through `FcDynastyController`. Presentation changes touch neither.
- Test net to keep green: `test_ui_style_lint` (ratchet down only), `test_live_screen_matrix` (7 window shapes x 3 text sizes), contrast tests, `ScriptErrorLogger`, `tools/click_test.ps1`, `career_click_test.ps1`, `ui_playthrough.ps1`, `screenshot.ps1`/`screenshot_matrix.ps1`.

## 2. Complete screen inventory

**Shared (app.gd):** Main menu (3 art-less mode cards; saves in a `Tree`); Settings (kit, good); About (plain labels + TextEdit, serves as credits, no Novaeris/third-party credits); Component gallery (dev); loading overlay; confirm modals. Missing: splash, credits, dedicated save-management view.
**Owner:** New League wizard (default-control grid); Team Choice (`Tree`); Tutorial panel; Dashboard with 13 tabs: Overview (KPI strips good, rest labels/Tree), Standings, Schedule, Roster (13-col Tree), Finances (4 sub-pages, spinners/labels), Staff ("[x]/[ ]" buttons), Draft, Market, Trades (OptionButton + 2 ItemLists), Meeting, History, News, League. Modals: Player profile, Post-game.
**Career:** Home (one paragraph + 2 buttons, placeholder copy pointing at a docs path); Creator (5 steps; stage/preview are kit, inputs default Godot); Hub (lower-third header, 64 px portrait) with Card, Season, Develop, Skills tabs (Trees, labels, plain ProgressBar); stale footer ("calendar and games arrive in the next phase"). Modals: Player profile, Post-game.
**Dynasty:** Entry/profile list; Hub (featured card); Collection (best screen); Lineup (custom court; picker is default `AcceptDialog`+Tree); Packs + Pack reveal; Market; Play; Challenges; Tournament (text bracket); Season. Modals: Inspector, Compare, Carousel, Post-game.
**Creator Studio:** one screen (`studio_app.gd`, 318 lines): ItemLists, RichTextLabel, LineEdit; shares Theme/tokens, no kit, no previews.

## 3. Visual deficiencies (ranked)

1. No brand presence (logo, splash, credits, icons, Novaeris).
2. Dev-style main menu (saves table, art-less identical-structure cards).
3. Owner screens are bare Trees with no crests/portraits/sorting.
4. Career is forms, not an RPG; player is not the centrepiece.
5. Team identity = abbreviation + colour only.
6. Default controls bypass the kit (OptionButton/SpinBox/ItemList/AcceptDialog/TextEdit).
7. Player faces only in a few places; procedural figure quality unproven at small sizes.
8. No charts where data clearly exists (see section 5 evidence list).
9. No transitions or celebration moments; `ui_back` cue unwired.
10. Stale/placeholder copy; duplicated Dynasty-local helpers (`FcDynastyUi.wl/btn/heading/note/panel`).
11. Accessibility gaps; elevated surface tier missing.

## 4. Design system: extend, never rebuild

- Keep `FcUiTokens` / `FcUiTheme` / `FcUiModeSkin`. No `.tres` Theme.
- Token additions (each contrast-tested): `SURFACE_HIGH` #202F4D; GOLD/PRIMARY candidates **only if every text/surface pair still passes 4.5:1, otherwise existing values stay** (confirmed decision 2); `GLOW_*` alpha tokens; rarity accents consolidated from `FcRarityStyle`; numeric type roles (Inter tabular figures, already loaded) and a hero-numeral size. No new fonts.
- Logo orange (sampled from the supplied art) is compared with PRIMARY; the contrast result decides.
- Six interaction states (Default/Hover/Pressed/Focused/Selected/Disabled) enumerated by a new `test_ui_states` for every kit control.
- Consistent states: `FcEmptyState` and `FcLoading` exist; add `FcErrorState`, `FcSuccessState`, `FcSkeleton` (table/card loading placeholder), all in the gallery.
- Atmosphere: extend `FcScreenHost` backdrop modes (arena haze, court-line floor); procedural first.
- **Localization-ready layout practices** (new standing rules): no string concatenation for sentences (use format placeholders), no fixed-width label assumptions (containers wrap/ellipsize, tested at 130% text), no text baked into art, numbers/dates/currency formatted through one helper (`FcFormat`) that can later become locale-aware, UI strings gathered in `data/ui/` or wrapped via `tr()` on new screens, icons never carry meaning without a text label, RTL not implemented but containers use `anchors`/`size_flags` not hard-coded x offsets. New screens add a "pseudo-locale" test (strings padded +40%) to the viewport matrix to catch clipping.

## 5. Component development priorities (revised)

Order: **1 FcTable, 2 FcTeamCrest/team identity, 3 shared player presentation, 4 essential charts, 5 form controls and supporting components.**

**5.1 FcTable (first, as a prototype before any Owner screen migrates).**
Design: custom virtualised row control (not `Tree`) so rows can hold crest, portrait, badges, bars; same data in as `FcDataTable.build` so its API and mobile card fallback stay; old `Tree` path stays behind the existing function until each tab is migrated.
Prototype gate (built in the component gallery and a headless benchmark; screenshots + numbers presented at Checkpoint 1):
- Sorting (click header, stable, numeric/text/custom keys, indicator, keyboard activate).
- Selection (single, row-activate signal, keeps selection across refresh by row id).
- Keyboard navigation (arrows, PageUp/Down, Home/End, Enter, type-ahead optional) and focus visuals.
- Scrolling (mouse wheel, drag, scrollbar, touch fling on mobile).
- 400, 1,000 rows: build time and per-frame cost budgets (e.g. build < 50 ms for 400 rows headless; scroll holds 60 fps via row pooling).
- Portrait and crest cells at 32-48 px, rating badges, mini bars.
- Mobile fallback (cards) and ellipsis/tooltips at 3 text sizes.
- Accessibility: focus order, contrast of selected/hover rows.
Go/no-go: if the prototype fails a gate, fall back to a themed `Tree` with icon columns and report before proceeding.

**5.2 FcTeamCrest + team identity system** (see section 8).

**5.3 Shared player presentation** (see section 9).

**5.4 Charts: only where a real screen and dataset exist.** Evidence list (build exactly these, nothing speculative):
| Component | Screen and real data |
|---|---|
| `FcSparkline` | Owner Overview: owner profit / team value by season (finance engine yearly books); Roster/profile: ovr by season (`FcPlayer` history); Career hub: ovr over seasons (`FcCareerProfile.history`) |
| `FcBarChart` (stacked) | Owner Finances: revenue and expense categories from the books `tools/finances.ps1` already prints |
| `FcRadar` | Player profile and Career card: attribute groups (already computed for `FcStatBar`) |
| `FcBracket` (connectors) | Owner playoffs (season engine playoff series) and Dynasty tournament (`FcDynastyTournament.bracket_view`) |
No line chart, heat map or other chart is built unless a later screen proves a need.

**5.5 Form controls and supporting components:** `FcSpinner` (replaces SpinBox), `FcSelect` (wraps `FcDropdown`, replaces OptionButton), `FcListPicker` (replaces ItemList), `FcPickerModal` (replaces Dynasty AcceptDialog), `FcModeCard`, `FcSaveCard`, `FcSplash`, `FcCredits`, `FcScreenTransition`, `FcRatingDelta`, `FcXpBar`, `FcAchievementBanner`, `FcTrophyShelf` (each only when its screen phase needs it; trophy shelf and achievements display existing data only).

**5.6 app.gd extraction (incremental, approved).** Success is defined by architecture, not line count:
- Clear separation: screen-building code moves to `src/ui/menu/`, `src/ui/owner/`, `src/ui/career/` classes, mirroring `FcDynastyScreens*`.
- Explicit dependencies: each screen class receives what it needs (host, controller, navigator) through constructor/static args; no reaching back into FcApp internals.
- Reusable components: shared sections move to the kit, not copied per screen.
- Centralised navigation: all screens use `FcNavigator`/`_reset`-style registration; no screen manages its own back logic.
- Public contracts preserved: `show_*`, `on_*`, `build_tab` names stay as thin delegating methods so tests/tools keep working.
- No duplicated building logic; migrate one tab/screen at a time, each commit green. A test asserts every pre-existing public `show_*`/`build_tab` still exists.

## 6. Main menu (substantial, own phase with checkpoint)

Must include: proper Full Court branding; polished startup; distinct artwork per mode; atmospheric background; attractive save cards; prominent Continue; responsive layouts.
- **Startup:** Novaeris splash (skippable, ~1.5 s, static under reduced motion) fading into the Full Court title; Godot `boot_splash` set to a Midnight Navy Full Court/Novaeris image so no default Godot splash shows.
- **Background:** layered atmosphere from the Full Court banner language: dark arena haze, spotlight cones, reflective court floor with orange court lines; procedural/vector first; subtle slow drift (off under reduced motion).
- **Three mode cards with different compositions (not recoloured clones):**
  - Owner (franchise): wide landscape card, a front-office "skyline + court blueprint" composition, a live mini KPI strip (from the latest save, never invented), steel-blue/orange accent.
  - Career (broadcast): tall portrait card dominated by the player stage (the generated figure on a spotlight with lower-third text), orange accent.
  - Dynasty (collectible): card with a fanned stack of three rarity-framed `FcCardFace`s with sweep light, gold accent.
  Layout: Owner wide / Career tall / Dynasty tall-ish in an intentionally asymmetric hero row on desktop; vertical stack on narrow/mobile.
- **Continue hero:** most recent save with team crest, mode chip, season, record/stage, "Continue" primary button.
- **Save cards (`FcSaveCard`):** crest/portrait, name, mode chip, season/date, status chip (ok/corrupt/needs-content), load/delete in an overflow menu; delete keeps its confirm modal. Replaces the `Tree`; `FcSaveManager` untouched.
- **Save management feedback:** toast on save/load/delete success and failure, "last saved" timestamp in headers, autosave indicator only if autosave exists (not invented), visible error state with the save status text when a file is unreadable.
- **Footer:** Settings, Credits, Quit; small Novaeris mark bottom corner.
- **Responsive:** 800x600 to ultrawide at 3 text sizes; mobile portrait stack. **Screenshots at 1280x800 and 1920x1080 are mandatory at Checkpoint 2 before any further mode redesign.**
- No fabricated stats: mode-card details show real save data or static descriptive copy only.

## 7. Screen-by-screen recommendations

**Owner (desktop-first; no mobile work):** persistent front-office header (crest, record, cap/cash chips, phase action). Overview: tile dashboard (next game, standings snapshot, finance sparkline, owner meter, news, job offers). Standings: crests, seed/clinch badges, L10 bars, playoff line; bracket when playoffs start. Schedule/results: crest-vs-crest rows + existing post-game. Roster: `FcTable` with portrait, position badge, OVR/POT badges, contract bar, health chip; profile opens existing modal (+radar, ovr sparkline). Finances: KPI strip + stacked bars + `FcSlider`s; sponsors/loans as cards. Staff: cards with portrait, role, rating bars, `FcToggle`. Draft: prospect board with portraits and scouting-confidence bar, lottery reveal, pick timeline. Market, Trades (`FcListPicker`s with portraits, balance meter), Meeting (vote board with crests), History/League/News (trophy shelf, champions timeline, news cards). New League wizard and Team Choice (crest cards) in kit controls.
**Career (RPG):** hub centred on the player: large `FcShowcaseStage`, OVR/POT hero numerals, archetype badge, level + XP bar, development/skill points, reputation. Tabs: Profile (radar, grouped bars with "can reach" ghost), Develop (skill cards, `FcRatingDelta`), Season (next game card, role/coach/contract cards, rival/chemistry chips), Badges, History (timeline from `history`, trophies, milestones). Creator inputs in kit controls. Fix stale copy.
**Career data verification (decision 6).** Checked `FcCareerProfile`: it already stores `xp`, `level`, `development_points`, `skill_points`, `reputation`, `currency`, `coach_trust`, `chemistry`, `rival_player_id/wins/losses`, `training_used`, `sponsor_deal`, `history[]`, `decisions[]`, `stage`; rules in `data/career/progression.json` and `badges.json`. So XP and level **do exist** and may be displayed; achievements/milestones will be derived only from `history`, badges and existing career events; no new achievement or XP rules are introduced. Before Checkpoint 5 I will read `progression.json` to confirm the XP-to-next-level formula and show only values the rules compute.
**Dynasty:** hub banner and featured card spotlight; collection retained (set-completion rings); lineup picker as `FcPickerModal` with card previews; market price badges; challenges as reward cards with progress rings; tournament as `FcBracket`; season as milestone track; rewards claim moment; upgraded pack opening.
**Creator Studio:** visual restyle (kit Panel/Button/Table/Modal, Novaeris footer) and read-only live previews of cards/players/packs using `FcCardFace`/`FcPlayerVisual`; art slot status. **No new authoring editors.**

## 8. Team identity system (expanded)

Goal: every fictional team has a recognisable visual identity from existing data; **team data model unchanged** unless a separately approved change is needed. Everything derives deterministically from `FcTeamBranding` (colours, `logo_key`) + team id/name/city.
- **Crest shapes:** 6-8 silhouettes (shield, roundel, hexagon, diamond, pennant, banner, etc.) chosen by hash of team key (or `logo_key` when set).
- **Emblems/symbols:** a library of ~40 abstract/sport/city-neutral vector glyphs (bird, star, bolt, wave, peak, flame, crown, anchor, wheel, tree...) drawn in `_draw`/SVG; theme chosen by hash and, when possible, by city/region data (coastal, mountain, etc.) without fabricating facts.
- **Colour combinations:** use existing primary/secondary/accent; contrast guard (`FcUiContrast`) auto-picks light/dark foreground; reject low-contrast pairs for text.
- **Wordmarks:** team-name lockups in Barlow Condensed (city line + nickname line), horizontal and stacked.
- **Optional mascot identity:** deferred; Phase scope only reserves an optional `mascot` slot in the presentation spec; no art generated now.
- **Uniform colour treatments:** home/away/alt from the same colours (home = primary, away = light neutral with primary trim, alt = secondary); shared by `FcUniformPreview`, player figures, cards and score bugs.
- Sizes 16-128 px, simplified variants below 32 px; used in every table, header, score bug, card, bracket and save card.
- **Team identity consistency validation:** a test iterates every generated team in a seeded league (and the starter content), asserts crest/wordmark/uniform render without error, are deterministic, differ between teams (distinctness metric), and pass contrast.

## 9. Shared player presentation (moved ahead of Owner and Career)

Foundation for Owner, Career and Dynasty; deterministic identity and saves unchanged (no `FcPlayer` field, no DATA_VERSION change).
**Quality standards (all evaluated from real Godot screenshots, not code review):**
- Facial variety: expand face shapes and features beyond 6 faces, add eye/brow/nose/mouth variants and expression neutral/confident, plus age cues from player age.
- Skin tones: wider, perceptually balanced palette with believable undertones and shading; no tone rendered flat or ashen under rarity lighting.
- Hair variety: more styles (fades, afros, braids, locs, short, bald, headband/sleeves as accessories), colours incl. greys with age, facial hair variety.
- Facial proportions: consistent head/shoulder ratio across builds and heights; no uncanny eye spacing.
- Lighting and shading: top-left key light, rim light, soft gradient and contact shadow, consistent across all sizes.
- Uniform presentation: jersey with number, stripes/trim from team colours, readable number at medium size, crest on chest where it fits.
- Portrait cropping: headshot, bust and full-figure crops with fixed safe margins; same player is clearly the same person across crops.
- Consistent appearance across sizes: 24, 32, 48, 64, 96 px portraits and card sizes show a recognisable identity; simplified detail at tiny sizes.
**Card family:** one `size` enum maps to existing `FcCardFace` sizes: roster chip (row), small roster card, medium selection card, large collectible, full profile. Frames upgraded for rarity (layered border, inner glow, corner ornaments, existing sweep). Owner/Career use rating-tier frames, Dynasty uses rarity.
**Evaluation method:** a contact-sheet tool (`tools/portrait_sheet`, built on `tools/screenshot.gd`) renders e.g. 120 seeded players x 5 sizes plus all skin/hair combinations; reviewed at Checkpoint 3.
**Cross-mode player identity validation:** test that the same player key/team yields identical `FcPlayerVisual.resolve` output in Owner, Career and Dynasty contexts, that sizes never change identity fields, and a golden-hash fixture for ~50 seeded players so future changes to the figure are deliberate.

## 10. Asset strategy (three categories)

**A. Generic generated league players:** improved deterministic procedural portraits (section 9). No raster art.
**B. Featured Dynasty players:** approved custom artwork through the existing `art_path` pipeline (T1).
**C. Menu and mode artwork:** dedicated branded artwork; procedural/vector first, raster only when approved by you.
**Asset specification** (`docs/ASSET_SPEC.md`, enforced by a checker in `tools/` and Creator Studio):
| Item | Spec |
|---|---|
| Player card art (B) | PNG, transparent, 512x640 (4:5), head-and-torso bust, 32 px safe margin, subject centred, sRGB, no baked text/rarity frame |
| Player thumbnail | auto-derived 128x160 at import; headshot crop metadata optional |
| Menu mode art (C) | PNG/WebP lossless, 1920x1080 layered pieces or 3840 px wide backdrop, cover-scaled never stretched; focal point metadata; also a 960x540 low-quality variant for mobile |
| Brand lockups | PNG with alpha at 4096/2048/1024/512 wide; mark 1024/512/256/128 square |
| Icons | Windows .ico (16-256), Android 192, adaptive 432 (66% safe zone), monochrome, iOS 1024 |
| Naming | `snake_case`, `data/content_*/art/<player_id>.png`, `assets/brand/<name>_<variant>_<size>.png`, `assets/ui/menu/<mode>_<layer>.png` |
| Compression | UI art imported lossless (no VRAM compression for portraits/logos), backdrops ok with lossy WebP/ETC2 variant; Android ASTC/ETC2 already enabled; texture memory budget tracked |
| Fallback | missing/invalid art never errors: T1 falls back to T2 figure, brand falls back to text wordmark, mode art to procedural composition; checker reports, game runs |
| Provenance | each shipped art file lists source (hand-made/commissioned/generated) and legal-review status in `assets/ART_PROVENANCE.md`; **no unapproved external or AI-generated artwork enters a shipped build** (LEGAL_CHECKLIST.md section 4 applies) |
Export presets exclude source/preview folders.

## 11. Logo and branding integration

Supplied: Full Court banner (silver italic wordmark + orange basketball swoosh on arena background) and Novaeris banner (silver N-mark + spaced wordmark + blue arc/star on dark gradient), both 2172x724 flat rasters with baked backgrounds. Full Court = game identity, Novaeris = company.
- Decision 1: if original layered/vector assets exist, use those. Otherwise I produce **masking previews** (side-by-side on navy, white, mid-grey and checker backgrounds with edge/glow quality notes) for your approval before any transparent master is committed. Glow/lens-flare effects may need soft-alpha treatment; I will not repaint or redraw the artwork.
- Production set once approved: Full Court lockup / wordmark / mark; Novaeris lockup / mark / wordmark; dark-UI (primary), mono-white and mono-dark variants; sizes per asset spec; app icons from the Full Court mark.
- Code: `FcBrand` (static cache, `texture(id)`, text-wordmark fallback so headless tests never fail), manifest `data/ui/brand.json`.
- Placement: Full Court dominates menu, title, loading, window title; Novaeris appears in startup, credits, Creator Studio footer, export metadata (`company_name`, copyright). Never both large on one screen.
- Trademark clearance of both names is a legal-checklist item, not code.

## 12. Animation strategy and performance budgets

All through `FcMotion` (extended with `stagger`, `count_to`, `glow_pulse`, `shake`, all `reduced`-aware).
Priorities (feedback, not decoration): screen transitions (`FcScreenTransition`: 180 ms fade + 8 px directional slide; reduced = 80 ms fade); button/tab feedback and `ui_back` cue; modal scrim + scale-in; card select lift/glow and flip; pack opening (pre-existing structure + rarity-coloured burst, slower anticipation for epic/legendary, always skippable); `FcRatingDelta` count-up; XP bar fill and level-up banner (using existing `xp`/`level`); achievement/milestone banner from existing history/badge events; championship celebration (capped `CPUParticles2D` confetti + banner, gl_compatibility-safe); loading screens with brand pulse and skeletons.
**Performance budgets (enforced by headless/live checks where measurable):** screen build <= 100 ms for any tab at 400 rows (headless), transition <= 200 ms, no `_process` on idle screens (tween/signal only), <= 150 simultaneous particles (<= 60 on mobile), one fullscreen shader max and `card_sweep` only on visible cards, 60 fps target on desktop and 30 fps floor on the reference phone/emulator, textures loaded lazily and cached with a memory budget (menu art <= 24 MB decoded, per-card art <= 1 MB), animations never block input and are always skippable, Low Effects switch (ties to reduced motion) disables particles/shaders/backdrop drift.
Audio: wire `ui_back`, add `transition`, `level_up`, `achievement`, `championship` synth recipes (no unlicensed audio, D-054). **UI sound volume and mute controls already exist** in Settings (mute + master/UI/SFX/music + test button); this milestone keeps them, adds a visible quick-mute toggle in the menu/header, tests that every new cue respects mute and the UI bus volume, and that cue spam is rate-limited.

## 13. Resolution, accessibility, localization

- Matrix keeps 7 window shapes x 3 text sizes and adds 1920x1080, 2560x1440, 3440x1440 and a pseudo-locale (+40% text) pass; every new screen is registered.
- Backdrops resolution-independent; content cap 1600 stays.
- Overflow handling in all new components (ellipsis + tooltip, wrap).
- Additions: colour-blind-safe semantics (never colour alone; icon+text for W/L, up/down), High Contrast option (token overrides, >= 7:1 text), additive `FcPreferences` fields, `[input]` map (`fc_confirm`, `fc_back`, `fc_tab_next/prev`) for keyboard + gamepad, keyboard navigation in `FcTable`/`FcBracket`. Hardware validation (phone, gamepad, screen reader, Windows high contrast) stays on the outstanding list and is not claimed.
- Owner/Career desktop-first (D-030). The main menu and Dynasty retain mobile layouts.

## 14. Additional standing requirements

- Localization-ready layout (section 4). UI sound volume/mute (section 12).
- Consistent loading/empty/error/success states: every new screen must use `FcLoading`/`FcSkeleton`, `FcEmptyState`, `FcErrorState`, `FcSuccessState`; a test lists screens and asserts each state exists.
- Save-management feedback (section 6).
- **No fabricated game data or decorative statistics:** every number, chart, record or label on a screen must come from game data or be clearly static copy; previews in the gallery and any marketing mock-up use seeded generated data labelled as sample; no fake "live" stats on mode cards; a lint-style review item in each checkpoint.
- Before/after documentation: screenshots from the existing tooling into `docs/validation/ui/visual_identity/<phase>/before|after/` at 800x600, 1280x800, 1920x1080 (+412x915 for menu/Dynasty), referenced in a phase log.
- Save compatibility: no saved-data fields; new prefs additive in `preferences.cfg`; UI memory in `ui_state.cfg`. A fixture save from the current build is loaded in a regression test at every phase.

## 15. Phased roadmap (revised order) with acceptance criteria

Every phase: tests green (`run_tests`, live tests, matrix, style-lint ratchet down only, script-error logger), docs updated, no controller/save/gameplay change, committed locally (push only if you ask). Each **checkpoint = real Godot screenshots + a short summary; I stop and wait for your approval.**

**Phase A — Spec, brand assets, validation (docs/assets only).** Scope: `docs/VISUAL_IDENTITY_PLAN.md`, D-057+, `docs/ASSET_SPEC.md`, logo extraction/masking previews, palette contrast run. Files: docs, `assets/brand/**`, `data/ui/brand.json`. Acceptance: contrast report (existing values kept where candidates fail), logo previews approved by you, `test_brand_assets` passes. Manual: you review previews.

**Phase B — Design system foundations + FcTable prototype → CHECKPOINT 1 (design system and component gallery).** Scope: token additions, state tests, `FcErrorState/SuccessState/Skeleton`, FcTable prototype with benchmark, form-control replacements, gallery updated. Existing touched: `ui_tokens`, `ui_theme`, `component_gallery`, `data_table`. New: `kit/table*`, `kit/spinner|select|list_picker`, tests (`test_ui_table`, `test_ui_states`). Acceptance: all prototype gates in 5.1 pass with numbers; every component shows six states in the gallery; contrast tests pass. Screenshots: gallery at 1280x800, 1920x1080, 800x600; table with 400 rows.

**Phase C — Team identity (FcTeamCrest system).** Scope: crests, emblems, wordmarks, uniform treatments, replace `FcLetterhead` stand-in internals while keeping its API. Acceptance: consistency/distinctness test over a seeded league; contact sheet of 30 teams reviewed. Included in Checkpoint 2/3 screenshots.

**Phase D — Brand, startup, main menu, navigation → CHECKPOINT 2 (main menu).** Scope per section 6, `FcBrand`, splash, boot splash, icons, credits, `FcScreenTransition`, menu extracted from app.gd into `src/ui/menu/`. Acceptance: menu fits 800x600 to ultrawide at 3 text sizes; save load/delete/continue unchanged; Novaeris/Full Court placement rules; reduced motion static. Screenshots at 1280x800 **and** 1920x1080 (plus 412x915, 800x600). **No further mode redesign starts before approval.**

**Phase E — Shared player presentation (moved ahead) → CHECKPOINT 3 (player presentation system).** Scope per section 9 and the asset spec for category B. Files: `src/ui/player/*`, `src/ui/cards/card_face.gd`, `rarity_style.gd`, new `tools/portrait_sheet`. Acceptance: contact-sheet approved by you; golden-hash identity test; cross-mode identity test; size-consistency test; no save change. Screenshots: contact sheets, each card size, roster rows, profile.

**Phase F — Owner redesign (extract from app.gd per tab).** F1 header+Overview+Roster (**CHECKPOINT 4: Owner Overview and Roster**), then F2 Standings/Schedule/playoff bracket, F3 Finances (stacked bars)/Staff, F4 Draft/Market/Trades/Meeting, F5 History/League/News/New League/Team Choice. Acceptance per sub-phase: a data-driven checklist asserts every pre-existing column/button/action remains; `click_test` green; before/after screenshots; build budgets met.

**Phase G — Career redesign → CHECKPOINT 5 (Career Hub).** Hub, profile, develop, season, skills/badges, history, creator inputs, stale copy. Acceptance: displays only existing progression data (xp/level/points/reputation/history); all career actions still reachable; `career_click_test` green.

**Phase H — Dynasty polish + Creator Studio restyle → CHECKPOINT 6 (Dynasty Hub and Collection).** Acceptance: collection behaviour unchanged, picker modal, bracket, challenge/season visuals, Creator Studio smoke test (`studio_smoke.gd`) green, previews read-only.

**Phase I — Animation, audio, atmosphere polish.** Section 12; performance budgets verified with a measurement log.

**Phase J — Final QA → CHECKPOINT 7 (final integrated experience).** Full suites, refreshed screenshot library, performance and memory report, packaged Windows self-test, Android emulator check, `RELEASE_READINESS.md` updated, remaining hardware validation listed honestly.

(Original nine phases map to: 1=A, 2=B+C, 3=D, 4=F, 5=G, 6=H, 7=E, 8=I, 9=J.)

## 16. File-level estimates

| Phase | New files | Modified | Rough lines |
|---|---|---|---|
| A | ~14 assets/docs | none (code) | small |
| B | ~15 (table, controls, states, tests) | ui_tokens, ui_theme, gallery, data_table | ~2,500 |
| C | ~8 (`src/ui/team/*`, emblem data, tests) | letterhead, team_branding readers | ~1,500 |
| D | ~12 (`src/ui/menu/*`, brand, splash, credits, transition) | app.gd, screen_host, project.godot, export_presets | ~2,000 |
| E | ~6 + tool | player_figure, player_visual, card_face, rarity_style | ~2,000 |
| F | ~20 (`src/ui/owner/*`, sparkline/bar/bracket) | app.gd | ~4,500 |
| G | ~10 (`src/ui/career/*`, radar, xp bar) | app.gd, career_creator | ~2,500 |
| H | ~6 | dynasty_* (6), studio_app | ~1,500 |
| I | ~4 | ui_motion, pack_reveal, audio.json, audio.gd | ~1,000 |
| J | tests/docs | baselines | ~500 |
~95 new files and ~18k lines touched, spread across ten reviewable phases.

## 17. Risks and dependencies

1. Logo source quality (blocks D): original layered/vector assets, else masking previews for approval.
2. FcTable is the riskiest component: prototype gate with go/no-go and fallback (themed `Tree` + icon columns).
3. app.gd extraction: public contracts preserved via delegating stubs; one tab at a time; a test guards the contract list.
4. Eager building of all 13 Owner tabs per refresh will get slower with richer tabs: make tabs lazy (build on first select, refresh on change) when F lands; `test_tab_pages` covers it.
5. Player art quality is subjective: mitigated by checkpoint 3 contact sheets and the golden-hash test.
6. Art licensing/provenance: procedural-first, nothing unapproved ships.
7. Low-end Android GPU/shader risk plus new effects: Low Effects switch and budgets.
8. Test churn: baselines re-baselined explicitly per phase; ratchets only decrease.
9. Mechanic creep (XP/achievements): display existing data only.
10. Founder review load: phases small, checkpoints, before/after screenshots, behaviour checklists.
11. Hardware validation (phone, gamepad, screen reader, high contrast) remains outstanding.
12. `gl_compatibility` has no HDR/bloom: glow faked with gradients/additive layers.

## 18. Testing and global acceptance

Commands per CLAUDE.md: `godot_console --headless --path . --import --quit` (after new class_name files), `--script res://tests/run_tests.gd`, `tools/run_live_tests.ps1`, screenshot tooling for checkpoints.
New tests: `test_brand_assets`, `test_ui_table` (+ benchmark), `test_ui_states`, `test_ui_team_identity`, `test_player_identity_golden`, `test_ui_menu`, `test_ui_credits`, `test_ui_transitions`, per-tab "nothing lost" checklists, localization pseudo-locale pass, high-contrast and colour-blind semantics, performance guard, public-contract guard for `FcApp` methods, fixture-save regression.
Milestone acceptance: no inventoried screen uses default-styled Tree/ItemList/OptionButton/SpinBox/AcceptDialog; `FcUiTables` removed or empty; app.gd reduced to navigation/wiring with the architecture criteria in 5.6 met; branding placement rules met; all export icon slots filled; current-build saves and Dynasty profiles load unchanged; content publisher/validator and simulation calibration tests unchanged (no sim files touched); all seven checkpoints approved by you.

## 19. Confirmed decisions (recorded from your review)

1. Logos: original layered/vector if available, else masking previews for approval.
2. Palette: contrast tests decide; existing values retained where alternatives fail.
3. Art: procedural-first; approved custom artwork for featured content.
4. app.gd: incremental extraction approved.
5. Player presentation ahead of Owner and Career.
6. Career: display existing progression only (verified: xp, level, development/skill points, reputation, history exist).
7. Owner desktop-first; menu and Dynasty keep mobile.
8. Creator Studio: restyle and previews only.

## 20. Verification of this deliverable

Documentation only. On approval the first actions are: save this as `docs/VISUAL_IDENTITY_PLAN.md`, record D-057+ in `docs/DECISIONS.md`, then start Phase A. Nothing in game code, saves, controller APIs or gameplay has been changed.

---

## Progress (recorded as the milestone ran)

| Phase | Status | Checkpoint note |
|---|---|---|
| A Spec, brand assets, palette | done, pushed | (D-057, `docs/ASSET_SPEC.md`, `assets/ART_PROVENANCE.md`) |
| B Design system and FcTable prototype | done, pushed; prototype gate passed (go) | `docs/validation/ui/visual_identity/CHECKPOINT_1.md` |
| C Team identity | done, pushed | `CHECKPOINT_C_TEAM_IDENTITY.md` |
| D Brand, startup, main menu | done, pushed | `CHECKPOINT_2_MAIN_MENU.md` |
| E Shared player presentation | done, pushed | `CHECKPOINT_3_PLAYER_PRESENTATION.md` |
| F Owner redesign | done (F1 Overview and Roster; F2 to F5 all other tabs), pushed | `CHECKPOINT_4_OWNER_OVERVIEW_ROSTER.md`, `CHECKPOINT_4B_OWNER_TABS.md` |
| G Career redesign | done, pushed | `CHECKPOINT_5_CAREER_HUB.md` |
| H Dynasty polish and Creator Studio restyle | done, pushed | `CHECKPOINT_6_DYNASTY_STUDIO.md` |
| I Animation, audio, atmosphere | done, pushed | `CHECKPOINT_I_ANIMATION_AUDIO.md` |
| J Final QA | done: suites, packaged build and self-test, click tools, documentation | `docs/RELEASE_READINESS.md` (last section), `docs/PROGRESS_LOG.md` |

Deviations from this plan, with reasons, are in D-058 (`docs/DECISIONS.md`) and in the "Not done" paragraph of each checkpoint note: no high-contrast or colour-blind mode, no screen slide transition, no Owner playoff bracket drawing, no new form-control wrappers, no raster art. The seven founder checkpoints were run without hard stops, as instructed: each has screenshots and a written summary instead of a pause.
