extends SceneTree
## Runs the live tests (tests/live/test_*.gd). Run with:  tools/run_live_tests.ps1
## Why a second runner: tests/run_tests.gd runs everything inside _initialize, before the first frame, when nodes are not yet
## "inside the tree": tweens, timers, focus and Range signals do not work there. This runner starts after the first frame, so
## nodes added under root are really in the tree, and a test method may `await` frames or seconds (see FcLiveTestCase).
## It finds each "test_*" method of every tests/live/test_*.gd file, awaits it, prints a summary and exits 0 (all passed) or 1.

const TEST_ROOT := "res://tests/live"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var files: Array[String] = []
	_collect(TEST_ROOT, files)
	files.sort()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter=") and arg.length() > 9:
			var wanted := arg.substr(9)
			files = files.filter(func(f: String) -> bool: return f.contains(wanted))
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
		names.sort()
		for name in names:
			var test = script.new()
			test.before_each()
			await test.call(name)
			test.after_each()
			if test.failures.is_empty():
				passed += 1
			else:
				failed += 1
				print("FAIL  %s::%s" % [path.get_file(), name])
				for f in test.failures:
					print("        " + f)
	print("")
	print("Live tests: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
