# Drives the real Career Mode screens with simulated mouse clicks (create, draft, decide, play, develop, train, finish season, save).
# Drives the real Career Mode screens with simulated mouse clicks (create, draft, decide, play, develop, train, finish season, save).
$project = Split-Path -Parent $PSScriptRoot
godot_console --headless --path $project --script res://tools/career_click_test.gd
