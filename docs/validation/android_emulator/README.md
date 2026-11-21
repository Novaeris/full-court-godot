# Android EMULATOR run (not physical hardware)

2026-11-21. Emulator `fc_pixel` (Pixel 6 profile, Android 14 / API 34 Google APIs x86_64, 1080 x 2400 at 420 dpi = about 412 x 915 dp, Windows Hypervisor Platform acceleration,
host NVIDIA GPU, OpenGL ES 3.1). Build: `FullCourt-debug.apk` from `./tools/export_android.ps1`. **This is NOT the physical-device validation the plan asks for; it is extra evidence only.**
Driven with `adb` (`input tap`, `input keyevent KEYCODE_BACK`, `screencap`); no human hands, no real touch screen, no real GPU, no real memory pressure.

## What it showed

| Check | Result |
|---|---|
| App installs, starts, reaches the main menu | Yes (screenshots 03, 04, 07). |
| Engine log | With the host GPU: no `ERROR`. (The first try, with the emulator's software renderer SwiftShader, printed "Fragment shader active uniforms exceed GL_MAX_FRAGMENT_UNIFORM_VECTORS (261)" and drew nothing. That is a limit of that software GPU (261 vectors); Godot's 3D scene shader, which the compatibility renderer also compiles, needs more. Real phone GPUs normally report 1024 or more, but that is **not proven for any real phone: a risk to check on hardware**, see DEVICE_VALIDATION row 1.) |
| Bundled Founding Series content loads from the APK | Yes: "Content release fcr_2036b76f032b29c4 (46 cards, 5 packs, 14 challenges)" on the Dynasty entry screen (05). |
| Dynasty profile creation, starter collection, hub | Yes: 15 cards, 2,000 credits, 5 tokens, team overall 56, bottom navigation bar (06). |
| Persistence across a stop and restart | Yes: the app was force-stopped and reinstalled with `adb install -r` (data kept); the profile "My Dynasty (DYN), 15 cards, 2,000 credits" was listed and openable (08). |
| Android Back | From the Dynasty entry screen it returned to the main menu (09). Other screens, a dialog and the main menu exit not tested. |
| Safe areas | After the fix below the status-bar inset is proportionate (07). Cutouts and gesture bars of real phones untested. |

## Defects found and fixed because of this run

1. **The UI was drawn at desktop size on a phone.** The project stretches to a 1280 px design width, so a 1080 px phone showed a 1280 px logical window: three mode cards in a row, tiny text, touch targets about 37 physical pixels. Fix: on a mobile OS the window uses `content_scale_factor = screen dpi / 160` (`FcLayoutProfile.phone_scale`, unit-tested), giving about 412 logical px.
2. **The safe-area margins were applied in physical pixels to a logical layout** (a band 2.6 times too tall at the top). Fix: `FcLayoutProfile.safe_margins` divides by the content scale (unit-tested).

Screenshots: 01, 02 (blank: the SwiftShader failure), 03 (host GPU, before the scale fix), 04 (after the scale fix), 05 to 09.
