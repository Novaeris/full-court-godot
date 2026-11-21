# Export report (Windows release, Android debug)

Run on 2026-11-21 from commit `90b0204` plus the export-preparation changes of the same milestone (see `git log`). Environment: Windows 11, Godot 4.7.2.stable.official
(`godot_console`), Godot export templates 4.7.2.stable, JDK 21.0.2, Android SDK build-tools 34.0.0 and NDK 26.3 / 27.0.

## Windows release

| Item | Value |
|---|---|
| Command | `godot_console --headless --path . --export-release "Windows Desktop" builds/windows/FullCourt.exe` (or `./tools/export_windows.ps1`) |
| Exit / time | 0 / about 15 s |
| Output | `builds/windows/FullCourt.exe`, 111,241,792 bytes, SHA-256 `7cae9c43...c385d9` (changes with every commit; the full hash is in the build log, not stored) |
| Version | `FcVersion.GAME_VERSION` 0.1.0; preset product and file version 0.1.0; save `DATA_VERSION` 2, Dynasty `DYNASTY_DATA_VERSION` 1 |
| Preset | "Windows Desktop", x86_64, embedded PCK, all resources, include filter `data/**/*.json` plus the font and icon licence texts, exclude filter `tests/*, tools/*, docs/*, creator_studio/*` |
| Package check | `./tools/inspect_export.ps1 builds/windows/FullCourt.exe`: 642 files, RESULT ok. Contains scenes (1), src (422), data (139 JSON including the bundled Founding Series), assets (fonts, 33 icons, the card shader, the three licence texts), project binary. Contains NO tests, tools, docs, Creator Studio, builds or .git. |
| Run outside the editor | `builds\windows\FullCourt.exe --headless -- --selftest` printed `SELFTEST OK`, exit 0, 3.8 s. It creates and plays a league through two seasons, saves it, **loads the save back**, loads the bundled Dynasty release, creates a Dynasty profile (starter collection, legal lineup), plays a game, opens a pack, saves, closes and reopens the profile, all from the packaged files. |
| Windowed start | `FullCourt.exe --quit-after 240` (real window, OpenGL 3.3 compatibility on an NVIDIA RTX 4060): exit 0; the engine log held only the two engine banner lines, no error, warning or missing-resource message. |
| Not done | Code signing (no certificate; SmartScreen will warn on an unsigned exe), an installer, an icon `.ico` (the exe uses the project icon), a fresh machine without Godot installed (the exe is self-contained but was only run on the development PC). |

## Android debug

| Item | Value |
|---|---|
| Command | `godot_console --headless --path . --export-debug "Android" builds/android/FullCourt-debug.apk` (or `./tools/export_android.ps1`) |
| Exit / time | 0 / about 12 s; "Signing debug APK... Signed", "Verifying APK... DONE" |
| Output | `builds/android/FullCourt-debug.apk`, 30,273,743 bytes (arm64-v8a only) |
| Manifest (`aapt dump badging`) | package `com.novaeris.fullcourt`, versionCode 1, versionName 0.1.0, minSdk 24, targetSdk 36, label "Full Court", portrait, small to xlarge screens, native code `arm64-v8a`, **no permissions requested** |
| Contents | same game files as the Windows package (src 422, data 139, assets 42, scenes 1), no tests, tools, docs or Creator Studio |
| Run on a device | **Not done: no physical phone.** See docs/DEVICE_VALIDATION.md and the emulator note in docs/RELEASE_READINESS.md. |

## Setup performed on this PC (one time)

- Android export templates (`android_debug.apk`, `android_release.apk`, `android_source.zip`) copied from the official 4.7.2 `export_templates.tpz` into `%APPDATA%\Godot\export_templates\4.7.2.stable\`.
- Godot editor settings already held the JDK path, the Android SDK path and the debug keystore.
