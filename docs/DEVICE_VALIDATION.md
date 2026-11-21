# Dynasty on a real Android phone: validation checklist and record

**Status: OUTSTANDING. No physical Android device was available when this was written (2026-11-21): `adb devices` listed nothing and no emulator is
installed. Nothing in this file has been run on hardware. Touch has only been emulated in a phone-sized viewport (`tests/live/test_live_dynasty_mobile.gd`).**

Do not change a row to "pass" unless a physical device was used. Fill in the device block, then each row (pass / fail / note), at Normal and at Large text.

## How to run it

1. Build and install: `./tools/export_android.ps1`, then `adb install -r builds/android/FullCourt-debug.apk` (setup in `docs/PLATFORM_BUILDS.md`).
2. Watch the engine log in another window: `adb logcat -s godot`. Note every `ERROR` or `SCRIPT ERROR`.
3. Use the game with a finger, not `adb input`. Test once with Settings > Text size = Normal and once with Large.
4. For frame rate: Settings of the phone > Developer options > "Profile GPU rendering" (bars on screen), or `adb shell dumpsys gfxinfo com.novaeris.fullcourt framestats`.

## Device block (fill in)

| Field | Value |
|---|---|
| Device model | |
| Android version | |
| Screen resolution and density (`adb shell wm size`, `wm density`) | |
| Cutout / notch / gesture navigation? | |
| RAM | |
| Build tested (commit, `FullCourt-debug.apk` date) | |
| Tester and date | |

## Checklist

| # | Area | What to do | Result | Notes |
|---|---|---|---|---|
| 1 | First launch, onboarding | Fresh install. Does the app open without a crash and draw (no blank screen: the emulator's software GPU could not link Godot shaders, see docs/validation/android_emulator/README.md)? Is the first-run hint readable? | | |
| 2 | Dynasty profile creation | Main menu > Dynasty > enter a team name and abbreviation with the on-screen keyboard. Is the field not hidden by the keyboard? | | |
| 3 | Starter collection | After creation: 15 cards, lineup is set (Lineup says valid). | | |
| 4 | Navigation and More | Bottom bar: Hub, Collection, Packs, Play, More. Every other tab is under More. | | |
| 5 | Collection browsing | Scroll the grid, filter, sort, switch grid and carousel. Smooth? | | |
| 6 | Card inspection and comparison | Tap a card: inspector. Compare two cards. Pinch or buttons work? | | |
| 7 | Pack purchase and opening | Buy a Rookie Pack. Can the buy button be tapped without a mistap? | | |
| 8 | Pack reveal and skip | Watch the reveal (frame rate!). Skip it. Reduced motion on: no animation. | | |
| 9 | Lineup editing | Assign, clear (the X buttons), change minutes. Position eligibility refuses a wrong position with a message. | | |
| 10 | Gameplay and post-game | Play a game. Result screen readable, box score scrolls. | | |
| 11 | Challenges | Complete and claim. | | |
| 12 | Tournament bracket | Enter Founders Cup, play it out. Bracket readable at 412 px? | | |
| 13 | Season progression | Season screen, milestones claim. | | |
| 14 | Market | Buy a card; insufficient funds message. | | |
| 15 | Settings and audio | Mute, volume sliders (finger dragging), text size, reduce motion. Sounds play through the speaker, not too harsh. | | |
| 16 | Android Back button / gesture | From a tab: goes back one step; from the Dynasty hub: asks or leaves; from the main menu: leaves the app. Never traps, never loses data. | | |
| 17 | Suspension and resume | Press Home during a pack opening, wait a minute, return. Then rotate the phone (the app is portrait-locked). | | |
| 18 | Save persistence | Force-stop (Settings > Apps > Force stop), relaunch: profile, credits, collection, lineup all intact. | | |
| 19 | Safe areas | Content not under the notch, status bar or gesture bar (the bottom bar must stay tappable). | | |
| 20 | Large text | Repeat rows 4, 7, 9, 12 with Large text: nothing cut off. | | |

## Observations to record

| Topic | Observation |
|---|---|
| Frame rate (collection scroll, pack reveal, post-game) | |
| Input responsiveness (tap to visible reaction) | |
| Layout problems | |
| Safe-area issues | |
| Memory or crash problems (`adb logcat`, Developer options) | |
| Animation performance | |
| Battery / heat after 15 minutes | |

## What has been done WITHOUT a device (not a substitute)

- Touch events emulated in a 412 x 915 viewport: whole Dynasty loop (`test_live_dynasty_mobile.gd`).
- Real-viewport screen matrix at 360 x 800 and 412 x 915, three text sizes, touch-size and sideways-overflow checks (`test_live_screen_matrix.gd`).
- Android Back and safe-area code paths unit-tested.
- A debug APK build: see `docs/PLATFORM_BUILDS.md` for whether it was produced.
