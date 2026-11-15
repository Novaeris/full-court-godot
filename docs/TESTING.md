# Testing

## Strategy
1. **Automated unit tests** for every system, run headlessly, fixed seeds.
2. **Simulation stress tests** (planned): thousands of games / multi-season runs checking plausibility (scores, percentages, finances, roster/contract validity).
3. **Manual playtesting** by the founder for feel, usability and fun. Claude provides step-by-step instructions with each UI feature.

## Running tests
From the project folder in PowerShell:

```powershell
./tools/run_tests.ps1
```

Or directly:

```powershell
godot_console --headless --path . --import --quit
godot_console --headless --path . --script res://tests/run_tests.gd
```

Run the `--import` line whenever a new `class_name` file is added (it refreshes Godot's class list). Exit code 0 = all passed, 1 = failures. Output ends with `Tests: N passed, M failed`.

## Writing a test
Create `tests/unit/test_<thing>.gd`:

```gdscript
extends FcTestCase

func test_something() -> void:
	assert_eq(1 + 1, 2)
```

Methods must start with `test_`. Available: `assert_true`, `assert_eq`, `assert_between`, and `before_each()` for setup. Use fixed seeds (`FcRng.new(123)`).

## Coverage
| Area | Tests |
|---|---|
| FcRng (determinism, forking, state restore, huge-seed JSON regression, distributions) | 8 |
| FcGameState (validation, round trip incl. RNG position) | 4 |
| Staff (definitions, roles, validation, retirement, round trip, contracts, world rules for unique roles / two jobs / dangling refs, old snapshots without staff) | 18 |
| Save system (round trip, slot-name safety, backups, checksum/truncation/garbage detection, interrupted-save and crash recovery, version rejection, migrations, listing, delete, autosave, integrity warnings, staff persistence) | 19 |
| FcIdGenerator (sequence, independence, save round-trip) | 3 |
| FcDate (validity, leap years, ISO round trip, age math) | 4 |
| Attribute system (shipped JSON valid, catalog errors, set validation, clamping, save compatibility, adding attributes) | 7 |
| FcPlayer (validation, positions, retirement, round trip, exact float round trip, sparse/corrupt data) | 11 |
| FcLeague / conferences / divisions / world integrity with leagues / old snapshots | 8 |
| League customization (real city data, areas, exact cities, nicknames, sizes 4-64, equal divisions for every valid size, geographic conferences and divisions, nationality mix, validation messages, save round trip) | 22 |
| League rules (valid sizes and layouts, season arithmetic and suggestions for every size, matchup planner fairness, playoff formats and validation, soft/hard/no-cap signing and trade rules, contract rules, rules in generated leagues, payroll vs hard limit, team naming, nationality share, sensitive places) | 39 |
| Generation (data validity, names, player realism by position/level/age, tendencies, staff specialization, full league validity, reproducibility, uniqueness, contracts/payroll, free agents, custom configs, save round trip) | 27 |
| FcTeam, FcRoster, FcCity, FcArena | 8 |
| FcContract (cap hit, guarantees, options, validation, round trip) | 7 |
| FcRepository / FcMemoryRepository | 2 |
| FcWorld (integrity checks, round trip, JSON text round trip, duplicate ids) | 11 |
| Everything else (simulation, generation, save files, league ops) | not built yet |

Shared sample builders for tests live in `tests/support/test_data.gd` (`FcTestData`).

Last verified: 198 passed, 0 failed (Godot 4.7.2).

Tests that touch disk use `user://test_saves` and clean up in `after_each()`. Inspection tools: `./tools/inspect_data.ps1`, `./tools/inspect_saves.ps1`, `./tools/generate_league.ps1 [option=value ...]` (e.g. `areas=europe teams=16 conferences=2 divisions=2`). The runner was also verified to report failures (exit code 1).

## Known issues / limits
- Runner discovers methods by name only. A test file with a syntax error is reported as a FAIL (an earlier version hung forever instead; fixed).
- GDScript gotcha: `var x := <untyped value>` is a parse error in this project (warnings are errors). Annotate the type: `var x: String = ...`.
- No stress-test tooling yet (planned with the simulation engine).
