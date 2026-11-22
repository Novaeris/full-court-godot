extends FcTestCase
## Player achievements (Owner and Career): derived from existing statistics, honours and injuries; data-driven, three tiers each, never stored.

const PREFS := "user://test_preferences_achievements.cfg"

var app: FcApp


func after_each() -> void:
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()
		app = null
	DirAccess.remove_absolute(PREFS)
	DirAccess.remove_absolute("user://test_ui_state_achievements.cfg")
	FcSafeFile.remove_tree("user://test_saves_achievements")
	FcSafeFile.remove_tree("user://test_dynasty_achievements")
	FcDynastyFixture.wipe()


## One season row: [year, team, gp, seconds, points, fgm, fga, tpm, tpa, ftm, fta, oreb, dreb, ast, stl, blk, tov, pf]
func _row(year: int, gp: int, points: int, rebounds: int = 0, assists: int = 0, threes: int = 0) -> Array:
	return [year, 1, gp, gp * 1800, points, 0, 0, threes, 0, 0, 0, rebounds / 2, rebounds - rebounds / 2, assists, 10, 5, 0, 0]


func _find(node: Node, type: Variant) -> Array:
	var out: Array = []
	if is_instance_of(node, type):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find(c, type))
	return out


func _result(results: Array, id: String) -> Dictionary:
	for r in results:
		if r["id"] == id:
			return r
	return {}


func test_the_data_file_is_well_formed() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(FcAchievements.PATH))
	assert_true(data is Dictionary and (data["achievements"] as Array).size() >= 15)
	var ids := {}
	var metrics := FcAchievements.metrics_for([], {}, [], 0)
	for def in data["achievements"]:
		assert_true(not ids.has(def["id"]), "unique id %s" % def["id"])
		ids[def["id"]] = true
		assert_true(metrics.has(def["metric"]), "%s reads a metric that exists (%s)" % [def["id"], def["metric"]])
		var t: Array = def["thresholds"]
		assert_eq(t.size(), 3, "three tiers")
		assert_true(t[0] < t[1] and t[1] < t[2], "ascending thresholds for %s" % def["id"])
		assert_true(str(def["name"]) != "" and str(def["description"]) != "")


func test_tiers_are_reached_at_their_thresholds() -> void:
	var m := FcAchievements.metrics_for([_row(2024, 70, 1000)], {}, [], 0)
	var scorer := _result(FcAchievements.evaluate(m), "scorer")
	assert_eq(scorer["tier"], 1, "1,000 points is bronze")
	assert_eq(scorer["tier_name"], "Bronze")
	assert_eq(scorer["next"], 5000)
	var none := _result(FcAchievements.evaluate(FcAchievements.metrics_for([_row(2024, 70, 999)], {}, [], 0)), "scorer")
	assert_eq(none["tier"], 0, "999 is not enough")
	var gold := _result(FcAchievements.evaluate(FcAchievements.metrics_for([_row(2024, 70, 16000)], {}, [], 0)), "scorer")
	assert_eq(gold["tier"], 3)
	assert_eq(gold["next"], 0)
	assert_eq(gold["progress"], 1.0)


func test_season_averages_need_a_real_season() -> void:
	var tiny := FcAchievements.metrics_for([_row(2024, 5, 150)], {}, [], 0)
	assert_eq(tiny["best_season_ppg"], 0, "5 games prove nothing")
	var real := FcAchievements.metrics_for([_row(2024, 60, 1500, 600, 480), _row(2025, 60, 900)], {}, [], 0)
	assert_eq(real["best_season_ppg"], 25)
	assert_eq(real["best_season_rpg"], 10)
	assert_eq(real["best_season_apg"], 8)


func test_honours_and_club_years_feed_their_achievements() -> void:
	var m := FcAchievements.metrics_for([], {"titles": 2, "mvp": 1, "finals_mvp": 0, "scoring_titles": 3, "all_league_first": 6}, [], 9)
	var results := FcAchievements.evaluate(m)
	assert_eq(_result(results, "champion")["tier"], 2)
	assert_eq(_result(results, "most_valuable")["tier"], 1)
	assert_eq(_result(results, "finals_star")["tier"], 0)
	assert_eq(_result(results, "scoring_crown")["tier"], 2)
	assert_eq(_result(results, "all_league")["tier"], 3)
	assert_eq(_result(results, "one_club")["tier"], 2, "nine seasons with one club")


func test_a_comeback_needs_a_serious_injury_and_a_real_season_after_it() -> void:
	var injuries := [{"year": 2025, "injury": "torn ACL", "games": 82, "severe": true}]
	assert_eq(FcAchievements.metrics_for([_row(2024, 70, 800)], {}, injuries, 0)["comebacks"], 0, "no season after it yet")
	assert_eq(FcAchievements.metrics_for([_row(2024, 70, 800), _row(2026, 20, 200)], {}, injuries, 0)["comebacks"], 0, "a handful of games is not a comeback")
	assert_eq(FcAchievements.metrics_for([_row(2024, 70, 800), _row(2026, 45, 500)], {}, injuries, 0)["comebacks"], 1)
	var minor := [{"year": 2025, "injury": "bruise", "games": 3, "severe": false}]
	assert_eq(FcAchievements.metrics_for([_row(2024, 70, 800), _row(2026, 70, 800)], {}, minor, 0)["comebacks"], 0, "only serious injuries count")


func test_earned_and_next_up_are_sorted_and_stable() -> void:
	var m := FcAchievements.metrics_for([_row(2023, 70, 1200, 400, 300), _row(2024, 70, 1400, 450, 350)], {"titles": 1}, [], 2)
	var results := FcAchievements.evaluate(m)
	assert_eq(results, FcAchievements.evaluate(m), "deterministic")
	var earned := FcAchievements.earned(results)
	assert_true(earned.size() >= 2)
	for i in earned.size() - 1:
		assert_true(earned[i]["tier"] >= earned[i + 1]["tier"], "best tier first")
	var next := FcAchievements.next_up(results, 3)
	assert_true(next.size() <= 3)
	for n in next:
		assert_true(n["tier"] < 3 and n["value"] > 0)
	for i in next.size() - 1:
		assert_true(next[i]["progress"] >= next[i + 1]["progress"], "nearest first")


func _owner_vm() -> Dictionary:
	DirAccess.remove_absolute(PREFS)
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_achievements")
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "name": "Achievement League"}))
	app.on_start_game(app._pending_state.world.teams.ids()[2])
	app.on_advance(10)
	var world: FcWorld = app.controller.state.world
	var team: FcTeam = world.teams.get_by_id(app.controller.state.user_team_id)
	var pid: int = team.roster.player_ids[0]
	world.careers[pid] = [_row(2023, 70, 1500, 500, 300), _row(2024, 72, 1700, 520, 330)]
	for r in world.careers[pid]:
		r[1] = team.id
	return FcPlayerPresentation.from_player(world, pid, app.controller.state.current_season, app.controller.league_id)


func test_an_owner_player_has_achievements_matching_his_statistics() -> void:
	var vm := _owner_vm()
	var results: Array = vm["achievements"]
	assert_eq(results.size(), 18)
	assert_eq(_result(results, "scorer")["value"], 3200, "the career points are the sum of his seasons")
	assert_eq(_result(results, "scorer")["tier"], 1)
	assert_eq(_result(results, "veteran")["value"], 2)
	assert_eq(_result(results, "one_club")["value"], 2, "two seasons in a row with this club")
	var world: FcWorld = app.controller.state.world
	var pid: int = world.teams.get_by_id(app.controller.state.user_team_id).roster.player_ids[0]
	assert_eq(_result(results, "scorer")["value"], world.career_totals(pid)["points"], "the same number the career totals give")


func test_the_dossier_shows_an_achievements_panel_and_tab_for_owner_players() -> void:
	var vm := _owner_vm()
	var profile := FcPlayerProfile.new().setup(vm)
	assert_true("achievements" in profile.tab_ids())
	var titles: Array = []
	for panel in _find(profile._body, FcPanel):
		for label in _find((panel as FcPanel).body, Label):
			titles.append((label as Label).text)
			break
	assert_true("Achievements" in titles, str(titles))
	profile.show_tab("achievements")
	assert_true(_find(profile._body, FcProgress).size() >= 18, "a bar for every achievement")
	profile.free()


func test_building_achievements_changes_nothing_in_the_game() -> void:
	_owner_vm()
	var world: FcWorld = app.controller.state.world
	var before := JSON.stringify(world.to_dict())
	var pid: int = world.teams.get_by_id(app.controller.state.user_team_id).roster.player_ids[0]
	FcPlayerPresentation.from_player(world, pid, app.controller.state.current_season, app.controller.league_id)
	assert_eq(JSON.stringify(world.to_dict()), before, "derived, read only, never saved")


func test_a_dynasty_card_has_no_achievements() -> void:
	DirAccess.remove_absolute(PREFS)
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_achievements")
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	FcSafeFile.remove_tree("user://test_dynasty_achievements")
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new("user://test_dynasty_achievements"))
	app.dynasty.catalog = FcDynastyFixture.catalog()
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
	assert_true(app.dynasty_ui.on_create("Static Kings", "STK"))
	var vm := FcPlayerPresentation.from_card(app.dynasty.card_detail(FcDynastyFixture.card_id(0)), app.dynasty)
	assert_true(not vm.has("achievements"))
	assert_true(not ("achievements" in FcPlayerProfile.new().setup(vm).tab_ids()))
