extends SceneTree
## Whole-project validation: GDScript compile errors, broken scenes and resources, missing or unimported assets, invalid JSON, invalid player models and
## animation clips that do not fit the player rig. Exit code 0 = clean, 1 = problems (listed). Used locally and by CI (.github/workflows/ci.yml).
##   godot_console --headless --path . --import --quit        (once, so imports exist)
##   godot_console --headless --path . --script res://tools/validate_project.gd
## The checks themselves live in tests/support/project_validator.gd and are unit-tested on fixtures that contain each kind of breakage.


func _initialize() -> void:
	var started := Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():   # root=/some/folder checks only that folder (the unit tests use it on fixtures)
		if arg.begins_with("root="):
			var folder_problems := FcProjectValidator.run_folder(arg.trim_prefix("root="))
			for p in folder_problems:
				print("PROBLEM  ", p)
			print("%d problem(s) in %s" % [folder_problems.size(), arg.trim_prefix("root=")])
			quit(1 if not folder_problems.is_empty() else 0)
			return
	var result := FcProjectValidator.run_project()
	var problems: Array = result["problems"]
	print("validated: ", result["counts"])
	for p in problems:
		print("PROBLEM  ", p)
	print("%d problem(s) in %.1f s" % [problems.size(), float(Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if not problems.is_empty() else 0)
