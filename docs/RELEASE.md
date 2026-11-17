# Building and releasing (M5)

Status 2026-11-17: **Windows export works** (a single `FullCourt.exe`, data packed inside). Mac, installer, signing, crash logs and mobile are not done.

## Build the Windows game
1. One-time: install Godot's **export templates** for the exact engine version (`godot_console --version` shows it, currently 4.7.2.stable). Either in the editor (Editor > Manage Export Templates > Download), or download `Godot_v4.7.2-stable_export_templates.tpz` from the official `godotengine/godot-builds` releases and unpack the `templates` folder into `%APPDATA%\Godot\export_templates\4.7.2.stable\`. Only the Windows files are needed for this build.
2. From the project folder in PowerShell: `./tools/export_windows.ps1` (add `-Debug` for a debug build).
3. The game is `builds/windows/FullCourt.exe` (the `builds/` folder is git-ignored). It runs on its own: no install needed. Saves and settings go to `%APPDATA%\Godot\app_userdata\Full Court\` (the project name).

## What the export includes
`export_presets.cfg` packs all game scripts and scenes and the `data/*.json` and `data/*/*.json` files (the game reads them as plain files, so they must be listed in `include_filter`). It leaves out `tests/`, `tools/`, `docs/`, the README and the LICENSE. If a new folder of data files is added under `data/`, check that the filter still matches it (`data/*/*.json` covers one level; deeper folders need another pattern).

## Check a build
- **Self-test (automatic):** `builds\windows\FullCourt.exe --headless -- --selftest` creates a small league from the packaged data, plays a season and an offseason, validates and saves it, prints `SELFTEST OK` and exits with code 0 (1 and a message if anything fails, for example a data file missing from the export). Run on 2026-11-17 for both the release and debug builds: OK.
- **By hand:** start the exe, create a new game, play a day, save. For rule changes use the source tools (`./tools/click_test.ps1`, `./tools/ui_playthrough.ps1`).
- The Godot export templates were installed on 2026-11-17 (Windows files only) in `%APPDATA%\Godot\export_templates.7.2.stable\`. The release exe is about 105 MB.

## Not done yet (in rough order)
1. A game icon and window title artwork (needs art from the founder; `application/icon` in the preset).
2. A Credits/Licenses screen with Godot's MIT notice (see `docs/LEGAL_CHECKLIST.md`).
3. An installer (or a zip) and code signing (an unsigned exe triggers Windows SmartScreen warnings for new publishers).
4. Mac export (needs a Mac or a build service for notarization), then Android and iOS for Dynasty Mode only (decision D-030).
5. Crash logs the player can send (privacy review first).
6. Automated builds (a CI job that runs the tests and the export on every release tag).
