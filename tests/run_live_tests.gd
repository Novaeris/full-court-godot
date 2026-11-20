extends SceneTree
## Runs the live tests (tests/live/test_*.gd). Run with:  tools/run_live_tests.ps1
## Why a second runner: tests/run_tests.gd runs everything inside _initialize, before the first frame, when nodes are not yet
## "inside the tree": tweens, timers, focus and Range signals do not work there. This runner starts after the first frame, so
## nodes added under root are really in the tree, and a test method may `await` frames or seconds (see FcLiveTestCase).
## It finds each "test_*" method of every tests/live/test_*.gd file, awaits it, prints a summary and exits 0 (all passed) or 1.
## Options after "--": --filter=text, --dir=res://folder (used by tests/unit/test_runner_detection.gd).
## Failure rules are the same as in tests/run_tests.gd: a failed assertion, a runtime SCRIPT error anywhere while the test ran (including
## while it was awaiting frames), a file that does not load or has no test_ methods, or a run that stops early (exit code 2).
## A test that never finishes awaiting (an await on a signal that never comes) is not detected here: the CI job's timeout ends it.

const TEST_ROOT := "res://tests/live"

var _completed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var files: Array[String] = []
	var root := TEST_ROOT
	var wanted := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter=") and arg.length() > 9:
			wanted = arg.substr(9)
		elif arg.begins_with("--dir=") and arg.length() > 6:
			root = arg.substr(6)
	_collect(root, files)
	files.sort()
	if wanted != "":
		files = files.filter(func(f: String) -> bool: return f.contains(wanted))
	var logger := FcScriptErrorLogger.install()
	if logger == null:
		print("WARNING: this Godot version has no Logger class, so runtime script errors cannot be detected; only failed assertions count.")
	var passed := 0
	var failed := 0
	for path in files:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("FAIL  %s (could not load: syntax error?)" % path)
			failed += 1
			continue
		var probe = script.new()
		var names: Array[String] = []
		for method in probe.get_method_list():
			if str(method["name"]).begins_with("test_"):
				names.append(str(method["name"]))
		if names.is_empty():
			# a helper that merely has a test_ file name is fine; a test case (extends FcTestCase) with no tests is a mistake
			if _is_test_case(script):
				print("FAIL  %s (contains no test_ methods)" % path)
				failed += 1
			continue
		names.sort()
		for name in names:
			var test = script.new()
			if logger != null:
				logger.take()
			test.before_each()
			await test.call(name)
			test.after_each()
			var script_errors: Array[String] = logger.take() if logger != null else []
			if test.failures.is_empty() and script_errors.is_empty():
				passed += 1
			else:
				failed += 1
				print("FAIL  %s::%s" % [path.get_file(), name])
				for f in test.failures:
					print("        " + f)
				for e in script_errors:
					print("        RUNTIME SCRIPT ERROR (the test did not finish): " + e)
	print("")
	if logger != null and logger.other_errors > 0:
		print("Engine errors logged (not failures): %d" % logger.other_errors)
	print("Live tests: %d passed, %d failed" % [passed, failed])
	_completed = true
	quit(1 if failed > 0 else 0)


func _finalize() -> void:
	if not _completed:
		print("RUN INCOMPLETE: the live test run stopped before every test finished.")
		quit(2)   # sets the process exit code (verified by tests/unit/test_runner_detection.gd)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path.path_join(f))


## True if the script derives from FcTestCase (tests/test_case.gd).
func _is_test_case(script: GDScript) -> bool:
	var base := script.get_base_script()
	while base != null:
		if base.resource_path == "res://tests/test_case.gd":
			return true
		base = base.get_base_script()
	return false
