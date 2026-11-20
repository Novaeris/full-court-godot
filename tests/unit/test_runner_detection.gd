extends FcTestCase
## Proves the test runners themselves: a green result must mean the tests really finished. Each case starts a SECOND Godot process on a
## folder of deliberately broken (or healthy) tests in tests/runner_fixtures and checks the exit code the runner returns. The fixtures
## live outside tests/unit and tests/live, and the normal runners skip that folder, so the broken tests can never run as part of the
## real suite. (Deliberate script errors cannot be triggered in this process: this runner's own error catcher would count them.)
## Each child process takes a few seconds (it loads the project).

const FIXTURES := "res://tests/runner_fixtures/"


## Runs a runner script on a fixture folder in a new process: {"code": exit code, "output": text}.
func _run(runner: String, folder: String) -> Dictionary:
	var output: Array = []
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", runner, "--", "--dir=" + FIXTURES + folder]
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	return {"code": code, "output": "\n".join(output)}


func test_a_runtime_script_error_fails_the_test_and_the_run() -> void:
	var r := _run("res://tests/run_tests.gd", "failing")
	assert_eq(r["code"], 1, "a nonzero exit code")
	assert_true("test_script_error.gd::test_aborts_with_a_script_error" in r["output"], "the aborted test is named as failed")
	assert_true("RUNTIME SCRIPT ERROR" in r["output"] and "no_such_method" in r["output"], "with the error that stopped it")
	assert_true("Tests: 0 passed, 4 failed" in r["output"], "nothing in the folder is counted as passed (3 script errors and 1 ordinary failure)")


func test_errors_in_setup_and_teardown_fail_the_test() -> void:
	var r := _run("res://tests/run_tests.gd", "failing")
	assert_true("test_setup_error.gd::test_body_passes_by_itself" in r["output"] and "in before_each" in r["output"], "a setup error")
	assert_true("test_teardown_error.gd::test_body_passes_by_itself" in r["output"] and "in after_each" in r["output"], "a teardown error")


func test_an_ordinary_failed_assertion_is_still_reported_as_before() -> void:
	var r := _run("res://tests/run_tests.gd", "failing")
	assert_true("an ordinary failed assertion expected <2> but got <1>" in r["output"])


func test_a_test_file_with_no_test_methods_fails() -> void:
	var r := _run("res://tests/run_tests.gd", "empty")
	assert_eq(r["code"], 1)
	assert_true("contains no test_ methods" in r["output"])


func test_a_healthy_folder_still_passes_with_exit_code_zero() -> void:
	var r := _run("res://tests/run_tests.gd", "passing")
	assert_eq(r["code"], 0)
	assert_true("Tests: 2 passed, 0 failed" in r["output"])


func test_the_live_runner_fails_a_script_error_after_an_await() -> void:
	var r := _run("res://tests/run_live_tests.gd", "live_failing")
	assert_eq(r["code"], 1)
	assert_true("broken_after_await" in r["output"] and "Live tests: 0 passed, 1 failed" in r["output"])


func test_the_live_runner_returns_a_nonzero_code_when_the_run_stops_early() -> void:
	var r := _run("res://tests/run_live_tests.gd", "live_quits")
	assert_eq(r["code"], 2, "an interrupted run can never look like success")
	assert_true("RUN INCOMPLETE" in r["output"])


func test_the_live_runner_passes_a_healthy_awaiting_test() -> void:
	var r := _run("res://tests/run_live_tests.gd", "live_passing")
	assert_eq(r["code"], 0)
	assert_true("Live tests: 1 passed, 0 failed" in r["output"])


func test_the_normal_runs_never_pick_up_the_fixtures() -> void:
	# the fixtures hold failing tests: if the unit runner could find them, the real suite would be red. It must skip the folder.
	assert_true("runner_fixtures" in (load("res://tests/run_tests.gd") as GDScript).source_code, "the unit runner names the folder it skips")
	var unit_files := _test_files("res://tests", true)
	for f in unit_files:
		assert_true(not "runner_fixtures" in f and not "/live/" in f, "the normal collection excludes " + f)
	assert_true(unit_files.size() > 50, "and still finds the real tests")
	assert_true(FileAccess.file_exists("res://tests/runner_fixtures/README.md"), "the fixtures are documented")


## What the unit runner would collect (the same folder rules, without running anything).
func _test_files(dir_path: String, skip: bool) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		if skip and sub in ["live", "runner_fixtures"]:
			continue
		out.append_array(_test_files(dir_path.path_join(sub), skip))
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	return out
