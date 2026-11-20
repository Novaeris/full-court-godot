extends SceneTree
## Headless test runner. Run with:  tools/run_tests.ps1
## Finds every tests/**/test_*.gd file, runs each "test_*" method, prints a summary, and exits with code 0 (all passed) or 1 (something
## failed). Options after "--":  --filter=text  (only files whose name contains it)   --dir=res://folder  (look somewhere else; used by the
## runner's own tests in tests/unit/test_runner_detection.gd).
##
## A test counts as FAILED, not passed, when:
##   - an assertion failed (as before);
##   - a runtime SCRIPT error happened while it ran (setup, the test itself or teardown): Godot aborts the function that raised it, so
##     the assertions after that point would never run; the error is caught with a Logger (see tests/support/script_error_logger.gd);
##   - its file could not be loaded, or defines no test_ methods;
##   - the run stopped before it finished (for example a test called quit()): the exit code is then set to 2 when the process ends.
## NOT detected: push_error calls and engine warnings (they appear in normal game code paths and are reported only as a count), an
## infinite loop (the CI job's timeout ends it), and a crash of the engine itself (the process dies with a nonzero code on its own).

const TEST_ROOT := "res://tests"
## Folders the normal runs never enter: live tests have their own runner; runner_fixtures hold deliberately broken tests.
const SKIPPED_FOLDERS := ["live", "runner_fixtures"]

var _completed := false


func _initialize() -> void:
	var files: Array[String] = []
	var root := TEST_ROOT
	var wanted := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter=") and arg.length() > 9:
			wanted = arg.substr(9)
		elif arg.begins_with("--dir=") and arg.length() > 6:
			root = arg.substr(6)
	_collect(root, files, root != TEST_ROOT)
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
		# A test file with a syntax error must FAIL the run, never hang or be skipped.
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
		for name in names:
			var test = script.new()
			if logger != null:
				logger.take()   # forget anything logged before this test
			test.before_each()
			test.call(name)
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
	print("Tests: %d passed, %d failed" % [passed, failed])
	_completed = true
	quit(1 if failed > 0 else 0)


## If the process ends before the run finished (a test called quit(), say), the exit code must not look like success.
func _finalize() -> void:
	if not _completed:
		print("RUN INCOMPLETE: the test run stopped before every test finished.")
		quit(2)   # sets the process exit code (verified by tests/unit/test_runner_detection.gd)


func _collect(dir_path: String, out: Array[String], include_skipped: bool) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub in SKIPPED_FOLDERS and not include_skipped:
			continue
		_collect(dir_path.path_join(sub), out, include_skipped)
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			out.append(dir_path.path_join(file))


## True if the script derives from FcTestCase (tests/test_case.gd).
func _is_test_case(script: GDScript) -> bool:
	var base := script.get_base_script()
	while base != null:
		if base.resource_path == "res://tests/test_case.gd":
			return true
		base = base.get_base_script()
	return false
