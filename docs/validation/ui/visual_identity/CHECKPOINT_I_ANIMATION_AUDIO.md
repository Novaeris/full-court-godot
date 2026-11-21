# Phase I: animation, audio and atmosphere

Date 2026-11-21. Screenshot: `phase_i/menu_with_sound_toggle.png` (the menu footer now has the quick Sound switch).

## What changed (every animation goes through `FcMotion` and respects Reduce motion)
- **Championship celebration** (`FcCelebration`): when the user's team wins the title (`on_sim_playoffs`) a banner with a trophy and the team name is raised over a dimmed screen with one confetti burst (capped at 80 pieces, 40 on touch layouts, no texture) and the championship fanfare; click, any key or 4 seconds dismiss it. With reduced motion: no confetti and no raise, just the banner and the sound.
- **Achievement banner**: a gold toast with a trophy (`FcToast.Kind.ACHIEVEMENT`, `FcNotifier.achievement`). Career play fires it with a level-up sound when a game gives a level (from `levels_gained`, which the rules already report); nothing is invented.
- **Sound**: four new recipes built by the game's own synth (no audio files): `transition`, `level_up`, `achievement`, `championship`; the previously unwired `ui_back` now plays when Back or Escape leaves a screen; a quick **Sound** switch in the menu footer mutes the whole game and is remembered (the four volume sliders stay in Settings).
- **Performance budget** is now a test: every Owner tab builds in under 250 ms headless (the slowest, Trades, takes 35 ms on this machine); confetti is capped; no new `_process` on idle screens (everything is tweens).

## Verified
`test_ui_celebration` (9): the new sounds exist, render and do not clip, all 21 sounds still render, achievement toast colour and icon and history, the celebration's text and cap, confetti under normal and reduced motion, the Sound switch mutes and persists, the tab build budget.

## Not done, said plainly
- **Screen transitions stay a fade.** The planned direction-aware slide cannot be done on the screen container without fighting the layout system (a container's children are re-positioned by their parent); a wrapper node would be needed, which was judged not worth the regression risk. Sound (`ui_back`) now marks back navigation.
- Rating-change count-up and card-select lift/glow were not added to new places: `FcMotion.count_to` and the card hover lift already exist and are used where a number or a card changes today. The pack-opening sequence was left as it is (it already scales its effects with rarity and has skip).
- Whether the fanfare and confetti *feel* right was not judged by ear or eye in motion: only the code path, the budgets and the reduced-motion path are verified.
