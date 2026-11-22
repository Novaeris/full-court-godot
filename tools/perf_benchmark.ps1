# Replay performance benchmark (opens a 1920x1080 window, vsync off). Usage:
#   ./tools/perf_benchmark.ps1 mode=2d run=standard [seconds=120] [seed=N]
#   run: standard | fast | camera | leak | soak      mode: 2d | 3d (once the prototype exists)
# See docs/validation/PERFORMANCE_THRESHOLDS.md for the pre-registered limits and the procedure.
$project = Split-Path -Parent $PSScriptRoot
godot_console --path $project --script res://tools/perf_benchmark.gd -- @args
exit $LASTEXITCODE
