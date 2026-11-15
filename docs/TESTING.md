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
| FcRng (determinism, forking, state restore, distributions) | 7 |
| FcIdGenerator (sequence, independence, save round-trip) | 3 |
| Everything else | not built yet |

Last verified: 10 passed, 0 failed (Godot 4.7.2). The runner was also verified to report failures (exit code 1).

## Known issues / limits
- Runner discovers methods by name only; no setup/teardown beyond `before_each`.
- No stress-test tooling yet (planned with the simulation engine).
