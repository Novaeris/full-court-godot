extends SceneTree
## Prints the staff chemistry of every team in a new league, to check the scale is sensible (typical teams near 55-65).
## Run:  godot_console --headless --path . --script res://tools/chemistry_check.gd -- [teams=30] [seed=2026]


func _initialize() -> void:
	var gen := FcWorldGenerator.create_default()
	var seed_value := 2026
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() == 2:
			match kv[0]:
				"teams": gen.config.team_count = int(kv[1])
				"seed": seed_value = int(kv[1])
	var world := gen.generate(seed_value)
	var scores: Array = []
	for t in world.teams.all():
		scores.append(FcStaffChemistry.new(world).evaluate(t.id, 2026)["score"])
	scores.sort()
	var total := 0
	for v in scores:
		total += v
	print("staff chemistry of %d teams: min %d, median %d, mean %.1f, max %d" % [scores.size(), scores[0], scores[scores.size() / 2], float(total) / scores.size(), scores[scores.size() - 1]])
	quit(0)
