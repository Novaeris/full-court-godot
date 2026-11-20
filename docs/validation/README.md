# Validation record: 2026-11-19 stabilization run

Each `*.txt` file holds the full output of one run, with its command, commit (the base commit; the working tree held the stabilization edits), exit code and duration. All exit codes are 0.

| File | Result |
|---|---|
| `full_test_suite.txt` | 710 passed, 0 failed (571 s). The leaked-resource lines at the end are Godot shutdown noise, not test failures. |
| `simulate_games_strict.txt` | `games=1000 strict=1`: all league averages in range (13 s) |
| `owner_stress.txt` | `seasons=30`: RESULT ok (691 s) |
| `economy_check.txt` | `seasons=15 teams=12 every=5`: RESULT ok (44 s) |
| `career_playthrough.txt` | 20 seasons, seed 7: 0 problems (55 s) |
| `career_click_test.txt` | 18 clicks, 0 problems (6 s) |
| `click_test.txt` | 67 clicks, 0 problems (10 s) |
| `baseline_career_balance_3seeds.txt` | seeds=3: 0 problems, spread 5.0 (2104 s) |
| `baseline_career_balance_5seeds.txt` | seeds=5: 0 problems, spread 5.0, lowest 73.2, highest 78.2 (3232 s) |

The balance spread limit stays 10: the measured spread (5.0) mostly reflects different potentials (75 to 80), so it was not tightened. Progression rules were not changed.
Not run here: the weekly long checks and release workflow (CI only), `ui_playthrough`, `owner_playthrough`.
