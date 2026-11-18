extends SceneTree
## Plays a Career Mode player through many seasons and checks the game stays valid: creates a player, joins a team, plays every
## season, spends development points on his archetype's strengths, unlocks and equips badges as soon as allowed, saves and reloads
## every few seasons, and prints one line per season.
##
## Run:  godot_console --headless --path . --script res://tools/career_playthrough.gd -- [seasons=20] [teams=12] [seed=7] [archetype=two_way_wing]
## Exit code 1 if the state becomes invalid, a reload changes the career, or progression breaks a rule.

var _problems: Array[String] = []


func _initialize() -> void:
	var seasons := 20
	var teams := 12
	var seed_value := 7
	var archetype := "two_way_wing"
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"seasons": seasons = int(kv[1])
			"teams": teams = int(kv[1])
			"seed": seed_value = int(kv[1])
			"archetype": archetype = kv[1]
	var defs := FcDefinitionSet.load_default()
	var position: int = int(FcArchetypes.get_archetype(archetype)["positions"][0])
	var spec := FcPlayerBuild.default_spec(archetype, position, defs)
	spec["first_name"] = "Test"
	spec["last_name"] = "Career"
	var made := FcCareerController.new_career(spec, seed_value, teams)
	if made.has("errors"):
		_fail("could not create the career: %s" % str(made["errors"]))
		_finish()
		return
	var c: FcCareerController = made["controller"]
	var join := c.join_team(c.draft_team())
	print("=== %s career, seed %d, %d teams: %s ===" % [archetype, seed_value, teams, join["reason"]])
	print("%-7s %-5s %4s %4s %5s %5s %5s %4s %6s %6s %s" % ["Season", "Team", "GP", "Ovr", "PPG", "RPG", "APG", "Lvl", "XP", "Badges", "Record"])
	var manager := FcSaveManager.new("user://career_playthrough_%d" % OS.get_process_id())
	var t0 := Time.get_ticks_msec()
	for i in seasons:
		if c.is_retired():
			print("Retired after %d seasons (stage %d)." % [c.profile().history.size(), c.profile().stage])
			break
		var pending := c.pending_event()
		if not pending.is_empty():   # decisions: take the first choice (the playthrough only checks the rules hold)
			c.answer_event(pending["choices"][0]["key"])
		var result := c.finish_season()
		if not result["ok"]:
			_fail("season %d could not be played" % (i + 1))
			break
		_spend(c, archetype)
		var row: Dictionary = c.profile().history[c.profile().history.size() - 1]
		var card := c.card()
		print("%-7d %-5s %4d %4d %5.1f %5.1f %5.1f %4d %6d %6d %d-%d" % [row["year"], c.state.world.teams.get_by_id(int(row["team_id"])).identity.abbreviation, row["games"], card["overall"],
			row["points"], row["rebounds"], row["assists"], c.profile().level, c.profile().xp, c.profile().badges_owned.size(), row["wins"], row["losses"]])
		var errors := c.state.validate()
		if not errors.is_empty():
			_fail("invalid after season %d: %s" % [i + 1, errors[0]])
			break
		for e in c.profile().validate():
			_fail("profile invalid after season %d: %s" % [i + 1, e])
		_check_ceilings(c, i + 1)
		if (i + 1) % 5 == 0:
			var saved := c.save(manager)
			var back := FcCareerController.resume(manager.load_slot("career_1", defs).state)
			if not saved.is_ok() or back == null or back.profile().checksum() != c.profile().checksum():
				_fail("save and reload changed the career after season %d" % (i + 1))
	print("Finished %d seasons in %.0f s. Level %d, %d badges, overall %d." % [c.profile().history.size(), (Time.get_ticks_msec() - t0) / 1000.0, c.profile().level, c.profile().badges_owned.size(), c.card()["overall"]])
	var dir := DirAccess.open("user://career_playthrough_%d" % OS.get_process_id())
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
		DirAccess.remove_absolute("user://career_playthrough_%d" % OS.get_process_id())
	_finish()


## The archetype's strongest attributes first; badges as soon as they can be unlocked.
func _spend(c: FcCareerController, archetype: String) -> void:
	var bonus: Dictionary = FcArchetypes.get_archetype(archetype).get("bonus", {})
	var keys: Array = bonus.keys()
	keys.sort_custom(func(a, b): return bonus[a] > bonus[b])
	var progress := true
	while progress and c.profile().development_points > 0:
		progress = false
		for key in keys:
			if c.raise_attribute(key)["ok"]:
				progress = true
				break
	for badge in c.badge_list():
		if badge["problem"] == "" and not badge["owned"]:
			c.unlock_badge(badge["key"])
			c.equip_badge(badge["key"], true)


func _check_ceilings(c: FcCareerController, season: int) -> void:
	var spec := FcPlayerBuild.spec_of(c.player(), c.profile().build_potential)
	for key in c.state.world.definitions.attributes.keys():
		if c.player().attributes.get_value(key) > FcPlayerBuild.attribute_ceiling(key, spec):
			_fail("%s is above its ceiling after season %d" % [key, season])


func _fail(text: String) -> void:
	_problems.append(text)
	print("  FAIL " + text)


func _finish() -> void:
	print("--- %d problem(s)" % _problems.size())
	quit(1 if not _problems.is_empty() else 0)
