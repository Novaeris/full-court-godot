# Platform builds: Windows, Android and iOS

Written 2026-11-21 (Release Validation milestone, Phase 2). It says how each build is made, what was proven, and what is still blocked.
**An export preset is not platform support.** Android is only "supported" once the debug build has run on a physical phone
(`docs/DEVICE_VALIDATION.md`); until then it is "builds, not device-tested".

## Windows (release build)

| Step | Command |
|---|---|
| One-time | Godot 4.7.2 export templates for Windows in `%APPDATA%\Godot\export_templates\4.7.2.stable` (Editor > Manage Export Templates, or the official `Godot_v4.7.2-stable_export_templates.tpz`). |
| Build | `./tools/export_windows.ps1` writes `builds/windows/FullCourt.exe` (one file, data packed inside; `-Debug` for a console build). |
| Check the package | `./tools/inspect_export.ps1 builds/windows/FullCourt.exe` lists what is inside and fails if tests, tools, docs, Creator Studio or the builds folder were packed, or if a required file (fonts, icons, shaders, content, definitions) is missing. |
| Launch outside the editor | `builds\windows\FullCourt.exe --headless -- --selftest` creates, plays, validates and saves a league and exits 0. |
| CI | `.github/workflows/release.yml` (tag `v*` or by hand) builds, self-tests and uploads the zip. |

Preset: `export_presets.cfg` preset 0 "Windows Desktop", x86_64, embedded PCK, all resources except `tests/*, tools/*, docs/*, creator_studio/*`, plus every
`data/**/*.json` (definitions, balance, the bundled content release). Version 0.1.0 (`FcVersion.GAME_VERSION`, preset file and product version).

## Android (debug build for hardware validation)

Preset 1 "Android" in `export_presets.cfg`: arm64-v8a only, no Gradle build (uses Godot's prebuilt template APK), package `com.novaeris.fullcourt`,
version name 0.1.0, version code 1, portrait orientation (`display/window/handheld/orientation=1`), ETC2/ASTC texture import on, debug-signed.

### One-time setup (what was done on the development PC)

1. **JDK 17 or newer** (the PC has JDK 21.0.2 at `C:\Program Files\Java\jdk-21.0.2`).
2. **Android SDK** with command-line tools, platform-tools, **build-tools 34.0.0**, **platforms android-34** and **NDK r26.3** (the PC has them at
   `%LOCALAPPDATA%\Android\Sdk`; `sdkmanager --install "build-tools;34.0.0" "platforms;android-34" "platform-tools" "ndk;26.3.11579264"`).
3. **Godot editor settings** (`%APPDATA%\Godot\editor_settings-4.7.tres`): `export/android/android_sdk_path`, `export/android/java_sdk_path`,
   `export/android/debug_keystore` (Godot creates `%APPDATA%\Godot\keystores\debug.keystore` with user `androiddebugkey`, password `android`).
4. **Android export templates** for 4.7.2: copy `android_debug.apk`, `android_release.apk` and `android_source.zip` from the official
   `Godot_v4.7.2-stable_export_templates.tpz` (`templates/` folder) into `%APPDATA%\Godot\export_templates\4.7.2.stable\`.

### Build and install

```
./tools/export_android.ps1                                  # builds/android/FullCourt-debug.apk
adb install -r builds/android/FullCourt-debug.apk            # a phone with USB debugging on
adb logcat -s godot                                         # engine log while testing
```

### Release (store) builds are NOT set up

A store build needs a **release keystore** that only the founder should create and keep safe (losing it means the app can never be updated),
a Google Play developer account, and an AAB (Gradle build). None of that is started. Decisions that must be made first: the final package
name (it can never change after publishing; `com.novaeris.fullcourt` is a placeholder), the version-code scheme, and the content-rating and privacy
answers (no data is collected, no network is used, no monetization code exists).

## iOS (not started, not claimed)

iOS is a later milestone. It needs, and none of it exists yet: a Mac with Xcode (Godot exports an Xcode project that must be built on a Mac),
an Apple Developer Program membership, an App ID and bundle identifier, signing certificates and provisioning profiles, a physical iPhone for testing
(TestFlight for wider testing), launch screens and the full icon set, and App Store review answers. The mobile layouts, touch targets and safe-area
code are shared with Android, but nothing has been built or run on iOS.

## Status table (2026-11-21)

| Target | Preset | Build produced | Run outside the editor | Run on physical hardware |
|---|---|---|---|---|
| Windows x86_64 | yes | yes, 111 MB, package checked | yes on the development PC (self-test exit 0, windowed start clean) | not applicable |
| Android arm64 | yes | yes, debug APK 30 MB, signed | **on an emulator only** (starts, content loads, profile persists, Back works): `docs/validation/android_emulator/` | **not tested** |
| iOS | no | no | no | **not tested** |

Details and commands: `docs/validation/export_report.md`.

### Emulator (optional, for developers without a phone)
`sdkmanager "emulator" "system-images;android-34;google_apis;x86_64"`, `avdmanager create avd -n fc_pixel -k "system-images;android-34;google_apis;x86_64" -d pixel_6`,
start it **with the host GPU** (`emulator -avd fc_pixel -gpu host`; the software renderer SwiftShader cannot link Godot's shaders and shows a blank screen), then
`adb install -r builds/android/FullCourt-debug.apk`. An emulator is not a substitute for `docs/DEVICE_VALIDATION.md`.

## Phone display rules (found on the emulator)
On a mobile OS `FcApp.setup` sets `content_scale_mode` to disabled and `content_scale_factor = dpi / 160` (`FcLayoutProfile.phone_scale`), so a 1080 px, 420 dpi phone lays out at about 412 logical px,
and safe-area insets are converted to logical pixels (`FcLayoutProfile.safe_margins(..., scale)`).
