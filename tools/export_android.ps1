# Builds the Android DEBUG apk: builds/android/FullCourt-debug.apk (arm64-v8a, signed with Godot's debug keystore).
# Needs the one-time setup in docs/ANDROID_BUILD.md (Android SDK, JDK 17+, Godot's Android export templates, editor settings).
# Usage:  ./tools/export_android.ps1
$project = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force "$project/builds/android" | Out-Null
godot_console --headless --path $project --import --quit 2>&1 | Out-Null
godot_console --headless --path $project --export-debug "Android" "builds/android/FullCourt-debug.apk"
exit $LASTEXITCODE
