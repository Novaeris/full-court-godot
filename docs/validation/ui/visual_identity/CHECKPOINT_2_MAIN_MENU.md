# Checkpoint 2: main menu, brand and startup (Visual Identity Phase D)

Date 2026-11-21. Screenshots in `phase_d/`: `menu_saves_1280x800.png`, `menu_saves_1920x1080.png`, `menu_1920x1080.png` (no saves), `menu_saves_800x600.png`, `menu_saves_412x915.png` (phone layout), `credits_1280x800.png`. The saves in the pictures are scratch saves made by `tools/screenshot.gd screen=menu_saves` (never the player's own).

## What changed
- **Brand (`FcBrand`, `data/ui/brand.json`):** the Full Court lockup heads the menu and Credits; Novaeris appears at startup, in Credits ("Made by Novaeris") and as a small mark in the menu footer. A missing logo file falls back to a text wordmark (tested), so a broken install still shows a name. A logo is drawn from the smallest prepared size that is wide enough (never upscaled).
- **Startup (`FcSplash`):** Novaeris, then Full Court, on the brand navy over the already-built menu; any key, click or touch skips it; reduced motion shows each logo without fades; only plays when FcApp is the running game (not in tools, tests, headless or `--selftest`), and can be switched off in Settings ("Show the startup logos", additive preference). `project.godot` now has a navy Full Court/Novaeris boot splash (no default Godot splash) and the Windows icon; the Windows and Android export presets have their icons, company name and copyright filled in.
- **Atmosphere:** a new `arena` backdrop (`FcArenaArt`): spotlight cones, roof lights, a reflective court floor with perspective court lines, orange glow. Drawn from shapes, resolution independent.
- **Mode cards (`FcModeCard`, `FcModeArt`):** three different compositions, not recolours: Owner is a skyline under a court blueprint (wide card), Career is a player in a spotlight with a broadcast lower-third stripe, Dynasty is three face-down rarity-framed cards in a fan with a glint. The art never shows numbers, names or records, so nothing in it can be mistaken for game data. The whole card is a click target, its edge lights in the mode colour on hover and focus, and the button inside keeps the keyboard path.
- **Continue and saves (`FcSaveCard`, Continue card):** the latest readable save is a Continue card with a large Continue button; every save is a card (mode tile and icon, name, team and season, saved time, status chip, Load and Delete); selecting a card chooses the save Load and Delete act on; a damaged save is listed (so it can be deleted) with Load disabled. The old table is gone from the menu.
- **Credits (`FcCredits`)** replaced About: logos, version, Novaeris, what the game is built with and each licence line, the engine licence text, the content report, and the support buttons. `show_about()` still works.
- **Architecture:** the menu and Credits are built in `src/ui/menu/` (`FcMainMenu`, `FcCredits`), FcApp keeps `show_main_menu`/`show_credits`/`show_about` as thin methods that supply actions and data. FcApp lost about 70 lines.

## Existing tests changed (all in D-057)
The menu no longer has a text title (a logo), a saves table or an "About, licenses and logs" button: `test_main_menu_builds`, the phone-menu test and the highlighted-save regression test now check the logo, the cards and "Credits" (the regression is kept: choosing a card chooses its save), and the About test became a Credits test. Style lint exempts `src/ui/art/` (drawn pictures).

## Verified
`test_ui_menu` (15) and `test_live_menu` (6): logo loading and fallback, three different cards and accents, each card opens its mode, saves become cards, Continue only for a readable save, damaged saves listed and not loadable, splash finishes once and respects reduced motion, the menu fits 1920x1080, 1280x800, 800x600 and 412x915, cards share one height and Owner is widest on a wide window and stack on a phone.

## Reviewed in the screenshots, fixed
- Phone width overflowed because of an unclipped footer in development builds and an unclipped timestamp: clipped, the footer stacks on a phone, the gallery button is shortened.
- Mode cards were different heights (blurb length): the blurb reserves three lines. The Career figure collided with the lower-third stripe: figure raised, stripe lowered. A hard-edged glow circle on the floor was removed.
- Not verified: how the splash animation feels in motion (fades are timed in code, headless only checks the sequence), real touch behaviour on a phone, and the Windows boot splash and icon in a packaged build (checked at Checkpoint 7).
