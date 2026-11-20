# Runner fixtures

Deliberately broken (and one deliberately fine) tests used ONLY by `tests/unit/test_runner_detection.gd`, which starts a second Godot
process on each folder with `--dir=` and checks the exit code. The normal runners never enter this folder (`runner_fixtures` is
skipped by `tests/run_tests.gd`), so the failing tests cannot turn the real suite red. Do not rename these files into `tests/unit`.
