extends SceneTree
## Headless test runner. Run with:  tools/run_tests.ps1
## Finds every tests/**/test_*.gd file, runs each "test_*" method, prints a
## summary, and exits with code 0 (all passed) or 1 (something failed).

const TEST_ROOT := "res://tests"


func _initialize() -> void:
	var files: Array[String] = []
	_collect(TEST_ROOT, files)
	files.sort()

	var passed := 0
	var failed := 0
	for path in files:
		var script: GDScript = load(path)
		if script == null:
			print("FAIL  %s (could not load)" % path)
			failed += 1
			continue
		var probe = script.new()
		for method in probe.get_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			var test = script.new()
			test.before_each()
			test.call(name)
			test.after_each()
			if test.failures.is_empty():
				passed += 1
			else:
				failed += 1
				print("FAIL  %s::%s" % [path.get_file(), name])
				for f in test.failures:
					print("        " + f)

	print("")
	print("Tests: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
