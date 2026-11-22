extends FcTestCase
## The player dossier (profile redesign): a hero with the portrait, ratings and vitals, and an Overview of panels (ratings radar, development
## timeline, personality, contract and team, latest season, honours). It shows only what the mode really has (a Dynasty card has no contract,
## personality or age), reads the game and never changes it, and keeps the existing tab API.

const PREFS := "user://test_preferences_dossier.cfg"
const DYNASTY := "user://test_dynasty_dossier"

var app: FcApp


func after_each() -> void:
	FcMotion.reduced = false
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()
		app = null
	DirAccess.remove_absolute(PREFS)
	DirAccess.remove_absolute("user://test_ui_state_dossier.cfg")
	FcSafeFile.remove_tree(DYNASTY)
	FcSafeFile.remove_tree("user://test_saves_dossier")
	FcDynastyFixture.wipe()


func _app() -> void:
	DirAccess.remove_absolute(PREFS)
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_dossier")
	Engine.get_main_loop().root.add_child(app)
	app.setup()


func _owner() -> void:
	_app()
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "name": "Dossier League"}))
	app.on_start_game(app._pending_state.world.teams.ids()[2])
	app.on_advance(20)


func _find(node: Node, type: Variant) -> Array:
	var out: Array = []
	if is_instance_of(node, type):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find(c, type))
	return out


func _owner_vm() -> Dictionary:
	_owner()
	var world: FcWorld = app.controller.state.world
	var pid: int = world.teams.get_by_id(app.controller.state.user_team_id).roster.player_ids[0]
	return FcPlayerPresentation.from_player(world, pid, app.controller.state.current_season, app.controller.league_id)


func test_an_owner_player_has_personality_and_contract_in_the_view_model() -> void:
	var vm := _owner_vm()
	var personality: Array = vm["personality"]
	assert_true(personality.size() >= 5, "the personality traits the game defines")
	for t in personality:
		assert_true(int(t["value"]) >= 0 and int(t["value"]) <= 100 and str(t["name"]) != "")
	var contract: Dictionary = vm["contract"]
	assert_true(not contract.is_empty(), "a rostered player has a contract")
	assert_true(int(contract["salary"]) > 0 and int(contract["through"]) >= app.controller.state.current_season and int(contract["years_left"]) >= 1)
	assert_true(int(contract["total"]) >= int(contract["salary"]))


func test_the_contract_matches_the_game_data() -> void:
	var vm := _owner_vm()
	var world: FcWorld = app.controller.state.world
	var pid: int = world.teams.get_by_id(app.controller.state.user_team_id).roster.player_ids[0]
	var c := world.active_contract_of(pid)
	assert_eq(int(vm["contract"]["salary"]), c.salary_for(app.controller.state.current_season))
	assert_eq(int(vm["contract"]["through"]), c.end_season())
	assert_eq(int(vm["contract"]["total"]), c.total_value())


func test_building_a_dossier_changes_nothing_in_the_game() -> void:
	_owner()
	var world: FcWorld = app.controller.state.world
	var pid: int = world.teams.get_by_id(app.controller.state.user_team_id).roster.player_ids[0]
	var before := JSON.stringify(world.players.get_by_id(pid).to_dict()) + JSON.stringify(world.active_contract_of(pid).to_dict())
	var vm := FcPlayerPresentation.from_player(world, pid, app.controller.state.current_season, app.controller.league_id)
	var profile := FcPlayerProfile.new().setup(vm)
	profile.free()
	assert_eq(JSON.stringify(world.players.get_by_id(pid).to_dict()) + JSON.stringify(world.active_contract_of(pid).to_dict()), before, "read only")


func test_the_owner_overview_shows_every_panel_it_has_data_for() -> void:
	var profile := FcPlayerProfile.new().setup(_owner_vm())
	var titles: Array = []
	for panel in _find(profile._body, FcPanel):
		for label in _find((panel as FcPanel).body, Label):
			titles.append((label as Label).text)
			break
	for wanted in ["Ratings", "Development", "Personality", "Contract and team"]:
		assert_true(wanted in titles, "%s panel (got %s)" % [wanted, str(titles)])
	assert_eq(_find(profile._body, FcDevelopmentTrack).size(), 1, "the development timeline")
	assert_eq(_find(profile._body, FcRadar).size(), 1, "the ratings radar")
	assert_true(_find(profile, FcKpiStrip).size() >= 1, "the vitals strip")
	profile.free()


func test_a_dynasty_card_shows_no_contract_personality_or_age() -> void:
	_app()
	FcSafeFile.remove_tree(DYNASTY)
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new(DYNASTY))
	app.dynasty.catalog = FcDynastyFixture.catalog()
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
	assert_true(app.dynasty_ui.on_create("Dossier Kings", "DOK"))
	var vm := FcPlayerPresentation.from_card(app.dynasty.card_detail(FcDynastyFixture.card_id(0)), app.dynasty)
	assert_true(not vm.has("contract") or (vm.get("contract", {}) as Dictionary).is_empty())
	assert_true((vm.get("personality", []) as Array).is_empty())
	var profile := FcPlayerProfile.new().setup(vm)
	var titles: Array = []
	for panel in _find(profile._body, FcPanel):
		for label in _find((panel as FcPanel).body, Label):
			titles.append((label as Label).text)
			break
	assert_true(not ("Contract and team" in titles) and not ("Personality" in titles), "nothing is invented for a card (%s)" % str(titles))
	assert_true("Ratings" in titles and "Development" in titles)
	assert_eq(_find(profile._body, FcDevelopmentTrack).size(), 0, "a card has no career arc")
	profile.free()


func test_the_career_dossier_has_level_progress_and_the_career_arc() -> void:
	_app()
	var spec := FcPlayerBuild.default_spec("two_way_wing", 3, app._defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	assert_true(app.on_create_career(spec, 4))
	var vm := FcPlayerPresentation.from_career(app.career)
	assert_true(int(vm["progression"]["peak_age"]) > 0, "the career arc has its peak age")
	var profile := FcPlayerProfile.new().setup(vm)
	assert_eq(_find(profile._body, FcDevelopmentTrack).size(), 1)
	assert_true(not (vm["personality"] as Array).is_empty(), "a Career player has a personality too")
	profile.free()


func test_the_development_track_describes_itself_in_words() -> void:
	var track := FcDevelopmentTrack.new().setup(22, 27, 70, 85)
	assert_true("still growing" in track.summary() and "27" in track.summary())
	assert_true("in his prime" in FcDevelopmentTrack.new().setup(27, 27, 80, 85).summary())
	assert_true("past his prime" in FcDevelopmentTrack.new().setup(35, 27, 70, 85).summary())
	assert_eq(track.tooltip_text, track.summary(), "the picture is also text")


func test_the_hero_keeps_its_layout_contract_and_shows_both_ratings() -> void:
	var vm := _owner_vm()
	assert_true(FcPlayerProfile.new().setup(vm, true).get_child(0) is VBoxContainer, "stacked on a phone")
	var wide := FcPlayerProfile.new().setup(vm, false)
	assert_true(wide.get_child(0) is HBoxContainer, "side by side on desktop")
	assert_eq(_find(wide, FcRatingBadge).size() >= 2, true, "overall and potential")
	assert_eq(_find(wide, FcShowcaseStage).size(), 1)
	wide.free()
