# Look and feel: what is built and what is still needed from the founder

**Update 2026-11-21:** the Visual Identity milestone (D-057, `docs/VISUAL_IDENTITY_PLAN.md`) adds the Full Court and Novaeris brand and new palette values.

**Update 2026-11-20:** the founder approved the "Hardwood Night" direction (Barlow Condensed and Inter, Lucide icons, three mode personalities) and a full UI/UX milestone: see `docs/UI_POLISH_PLAN.md` and decisions D-047 to D-050. Fonts, icons and the design tokens now exist (`assets/`, `src/ui/ui_tokens.gd`). The sections below describe the earlier default and are kept for history; "What the default is NOT" is now partly out of date (no logo, illustrations, sound, team colours in the UI or animations beyond the kit's motion helpers yet).

Status 2026-11-17. The founder has not yet sent references, so Claude chose a default and made it easy to change.

## What exists now (desktop, M4 first pass)
- One central style: `src/ui/ui_theme.gd` (`FcUiTheme`). Dark navy surfaces, a basketball-orange accent for the open tab, focus rings and selected table rows, a warm gold for headings, green and red reserved for good and bad numbers, rounded corners, calm spacing.
- Three text sizes (Small 13, Normal 15, Large 18) in the main menu; the choice is remembered.
- A first-time tutorial and a Help button (`docs/ARCHITECTURE.md`, "First-time tutorial").
- Screenshots: `./tools/screenshot.ps1 screen=Finances out=shot.png` shows any screen (opens a window briefly).

## What the default is NOT
- No logo, no icon, no custom fonts, no illustrations, no sound, no team colours or badges, no animations. Those are art and audio assets, and the founder plans to make them with AI tools (see `docs/LEGAL_CHECKLIST.md`, section 4, before using any).

## Needed from the founder (one answer each is enough)
1. **Two or three reference images or games** whose look you like (screenshots are best). For a management game, think of the density of the screens (spreadsheet-like or card-like) and the mood (serious and premium, or bright and sporty).
2. **Mood in three words** (for example "premium, modern, calm").
3. **Colours:** keep navy and orange, or give a main colour. Team colours per franchise are a separate, later feature (generated from the city).
4. **Font:** keep Godot's default (readable, free) or name a font whose license allows games (an open-license font such as Inter, Roboto or Montserrat all work).
5. **Logo/icon:** the game's name artwork for the window, the exe icon and the store.

## How a change will be made
Edit the constants at the top of `src/ui/ui_theme.gd` (colours, radius, sizes) and the `FcUiTheme.build` function for styles; every screen follows. A font file goes in `assets/fonts/` and is set as the theme's default font. Run `./tools/click_test.ps1` and the screenshot tool afterwards.
