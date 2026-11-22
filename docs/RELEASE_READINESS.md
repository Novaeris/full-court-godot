# Release readiness report

Updated 2026-11-21 at the end of the Release Validation and Dynasty Content Readiness milestone (earlier version: UI polish Phase 13, 2026-11-20).
Environment for everything below: Windows 11, Godot 4.7.2.stable.official, `godot_console`, NVIDIA RTX 4060, JDK 21, Android SDK build-tools 34, emulator API 34.
The goal is a trustworthy release candidate and an exact list of what still blocks release; **the game is not declared finished.**
*Reading note (Phase 1, 2026-11-21): the test counts and timings in this report are dated records from the milestones named in each section, not current totals. Current totals are in [TESTING.md](TESTING.md) and current feature status in [FEATURE_MATRIX.md](FEATURE_MATRIX.md).*

## 1. Automated checks passed

| Check | Command | Result |
|---|---|---|
| Unit suite | `godot_console --headless --path . --script res://tests/run_tests.gd` | exit 0, **1133 passed, 0 failed**, 709 s |
| Live UI suite | `... --script res://tests/run_live_tests.gd` | exit 0, **75 passed, 0 failed**, 118 s |
| Release screen matrix (inside the live suite) | `... run_live_tests.gd -- --filter=screen_matrix` | 7 tests pass: see "What the matrix proves" |
| Simulation calibration | `... --script res://tools/simulate_games.gd -- games=1000 seed=2026 strict=1` | exit 0, 0 of 16 checks outside the realistic range, 12 s |
| Owner economy | `... tools/economy_check.gd` (defaults: 50 seasons) | exit 0, RESULT ok, 878 s |
| Owner stress | `... tools/owner_stress.gd` | exit 0, RESULT ok, 659 s |
| Career playthrough | `... tools/career_playthrough.gd` | exit 0, 0 problems, 54 s |
| Owner click test | `... tools/click_test.gd` | exit 0, 67 real clicks, 0 problems |
| Career click test | `... tools/career_click_test.gd` | exit 0, 22 clicks, 0 problems |
| Dynasty health | `... tools/dynasty_check.gd` | exit 0 (50 games with saves, a tournament, save and reload) |
| Dynasty Founding Series end to end | `... tools/dynasty_initial_check.gd` | exit 0, RESULT ok, 0 failures (`docs/DYNASTY_FOUNDING_REPORT.md`) |
| Creator Studio smoke | `godot_console --headless --path creator_studio --script res://tools/studio_smoke.gd` | PASS |
| GitHub Actions | `gh run list` | CI **success** on the screen-matrix commit `90b0204` (14 m 13 s). The commit that carries this report is checked after it is pushed (see the progress log). |
| Pack outcomes, economy and simulation unchanged | Gameplay, economy, pack and save code were not edited; the diff touches presentation code, content data, tests, tools and docs only. | The 400-roll / 30-game digest of Phase 13 was not re-run because nothing it covers changed. |

### What the matrix proves (`tests/live/test_live_screen_matrix.gd`, helper `tests/support/ui_viewport_audit.gd`)
Each screen is laid out inside a REAL `SubViewport` of the window size, then the audit looks for controls outside the window, sideways overflow, taps below 44 px
(touch layouts), dialogs larger than the window and buttons the keyboard cannot reach.
- **Dynasty (every tab plus the entry screen), desktop and mobile layouts, 7 sizes (360x800, 412x915, 800x600, 1024x768, 1280x800, 1920x1080, 2560x1080) x 3 text sizes:** 0 problems.
- **All 13 Owner tabs, Career home, all 5 Career creator steps, main menu, settings, new league, About, from 800x600 up, 3 text sizes:** 0 problems. On the two phone sizes these desktop-designed screens are NOT required to fit (D-030, D6): 93 combinations overflow there, printed for information.
- A confirmation dialog stays inside every window; on ultrawide (1920, 2560 and 3440 wide) every control sits inside the centred 1600 px column and the dialog is centred and compact.
- Three levels are kept apart: `test_release_readiness.gd` proves "builds" and the quick minimum-size "fits"; the matrix proves "fits a real viewport" and "usable" (touch size, scrolling, dialogs, focus style). "Looks and feels right" is a person's judgement.
- Large-text phone fit covers all 11 mobile Dynasty screens at all 3 text sizes; the minimum-size probe covers all 13 Owner tabs at small, normal and large text. No ratchet baseline was loosened; `screen_matrix_baseline.json` starts empty and may only shrink.

## 2. Locally verified (run here, not on hardware)

| Item | Evidence |
|---|---|
| **Windows release export** | `./tools/export_windows.ps1`: exit 0, 111 MB `FullCourt.exe`; `./tools/inspect_export.ps1` confirms 642 packaged files with nothing from tests, tools, docs or Creator Studio and every font, icon, shader, licence text and the bundled content present (`docs/validation/export_report.md`). |
| **Exported exe run outside the editor** | `FullCourt.exe --headless -- --selftest`: SELFTEST OK, exit 0 (league played, saved, loaded back; Dynasty content loaded, profile created, game played, pack opened, profile saved and reloaded). A windowed start ran 240 frames with a clean log. Only on the development PC. |
| **Android debug APK** | `./tools/export_android.ps1`: exit 0, 30 MB, signed, package `com.novaeris.fullcourt` 0.1.0 (code 1), arm64-v8a, portrait, no permissions. |
| **APK on an Android EMULATOR (not hardware)** | Installs, starts, loads the bundled release (46 cards), creates a profile, survives a stop and restart, Android Back returns to the menu. It found two real phone defects (UI drawn at desktop size; safe-area margins in the wrong units), both fixed (`docs/validation/android_emulator/README.md`). |
| **Dynasty initial content, normal loader** | Fresh-install load through `FcContentService`, 40 players, legal lineup, starter collection of 15, packs (guarantee and pity measured over 200 rolls each), duplicate conversion, games, challenges, milestones, both tournaments, save and reload. |
| **Owner Mode presentation audit** | All 13 tabs viewed (`docs/validation/OWNER_PRESENTATION_AUDIT.md`); four defects fixed. |
| **Ultrawide** | Content column capped at 1600 px and centred; covered by the matrix. |
| Screenshots | `docs/validation/ui/final/`, `docs/validation/android_emulator/`, `docs/validation/owner_audit/`. |

## 3. Verified on physical hardware

**Nothing.** No physical phone, tablet, gamepad, speakers or screen reader was available. `docs/DEVICE_VALIDATION.md` is the checklist and is entirely OUTSTANDING.

## 4. Not tested

- iOS (no preset, no Mac, no Apple account).
- Windows on any machine other than the development PC; Mac.
- Gamepad, screen reader (NVDA, TalkBack), Windows high contrast, very large display scaling.
- Frame times and animation smoothness on any real GPU; battery, heat, memory.
- How the 17 built sounds sound (`docs/validation/MANUAL_QUALITY_AUDIT.md`).
- Android: Back from every screen and from dialogs, suspension and resume, rotation, notches and gesture bars, the keyboard covering text fields, Large text, performance.
- Owner Mode and Career Mode on a phone (not a target, D-030).
- A Dynasty profile saved by an older build with the old two-card release (the save format did not change; the release-sync path is unit-tested but was not exercised with a real old profile).

## 5. Blocked by missing tooling or hardware

| Blocker | Needed |
|---|---|
| Physical Android validation | A phone with USB debugging; then `docs/DEVICE_VALIDATION.md` |
| iOS | A Mac with Xcode, an Apple Developer account, signing, a device (`docs/PLATFORM_BUILDS.md`) |
| Android release build (AAB) | A release keystore (founder), Gradle build template, Play Console account |
| Windows code signing | A code-signing certificate |

## 6. Requires a founder decision or external review

- **Package name** (`com.novaeris.fullcourt` is a placeholder) and the **release keystore** (D-056).
- **Dynasty content:** the Founding Series (D-055) is an invented starter pool; the founder said they will supply the official players. Keep, rename or replace it.
- **Lawyer review:** generated and Founding Series names, team names with real cities, the title "Full Court", AI-assisted assets, licences, and above all paid random packs (loot-box law) before any monetization (`docs/LEGAL_CHECKLIST.md`).
- **Music** is not included (a creative choice, not invented).
- **Orientation:** Android is locked to portrait; allow landscape?
- **Shader risk on low-end Android GPUs:** the emulator's software GPU failed at 261 fragment uniform vectors. Confirm on real devices before choosing the minimum supported phone.

## Known limits to carry forward
- Player visuals are tiers 0 to 2 (monogram, card art, procedural figure); full-body poses and 3D are designed slots, not built (D5).
- Engine messages such as "Lambda capture ... was freed" appear when a live test frees a pack reveal while a tween runs; they are not script errors.
- Owner tables are plain themed `Tree` tables with row selection, not `FcDataTable` (intentional legacy, see the Owner audit).

## Visual Identity milestone (2026-11-21, D-057, D-058)
Evidence for the new UI work. The earlier sections describe the state before it; where they differ (counts, screens), this section is newer.
- **Automated:** unit suite 1235 passed and live suite 91 passed (0 failed); Creator Studio smoke PASS; Windows release re-exported (about 114 MB), packaged `--selftest` prints SELFTEST OK, `tools/inspect_export.ps1` RESULT ok with the brand manifest, team-identity data, boot splash and icon required and `assets/brand/source/` forbidden; Owner click test 0 problems; Career click test 22 clicks 0 problems.
- **Performance, measured here (headless):** 400 and 1,000 table rows build in under 5 ms with 14 row controls and a scroll step of 0.25 ms; every Owner tab builds in under 40 ms (budget 250 ms); confetti is capped at 80 pieces (40 on touch).
- **Not verified, still open:** the splash and celebration timing by eye and ear; the Windows icon and boot splash in a packaged window; physical phone, gamepad, screen reader and Windows high contrast (unchanged from before: `docs/DEVICE_VALIDATION.md`); a high-contrast and a colour-blind mode were planned but not built (colour is never the only carrier of meaning in the new components, and contrast is tested, but there is no switch); no hand-made art for featured Dynasty players or menu backdrops exists; the app icon is the Full Court lockup on navy (a dedicated square mark was not drawn because the supplied logo has no clean stand-alone mark).
- **Founder decisions still needed:** trademark clearance of "Full Court" and "Novaeris" (legal checklist), the final Android package id and keystore (D-056), and whether original layered or vector logo files exist (the transparent logos are keyed from the supplied banners, so the silver lettering has lost its dark outline).
