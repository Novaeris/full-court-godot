extends FcTestCase
## Injury history and the dossier's Health panel (Owner and Career only): every new injury is remembered in the world (bounded, saved additively so older
## saves load as empty), the view-model carries the player's health, and the dossier shows status, durability, the club's medical level and the history,
## while a Dynasty card (never injured) shows no Health at all.

const PREFS := "user://test_preferences_injury_history.cfg"

var app: FcApp


func after_each() -> void:
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()
		app = null
	DirAccess.remove_absolute(PREFS)
	DirAccess.remove_absolute("user://test_ui_state_injury_history.cfg")
	FcSafeFile.remove_tree("user://test_saves_injury_history")
	FcSafeFile.remove_tree("user://test_dynasty_injury_history")
	FcDynastyFixture.wipe()


func _world(seed_value: int = 44) -> FcWorld:
	var data := FcGenerationData.load_default()
	var defs := FcDefinitionSet.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 5
	return FcWorldGenerator.new(data, defs, cfg).generate(seed_value)


func _find(node: Node, type: Variant) -> Array:
	var out: Array = []
	if is_instance_of(node, type):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find(c, type))
	return out


func _panel_titles(root: Node) -> Array:
	var titles: Array = []
	for panel in _find(root, FcPanel):
		for label in _find((panel as FcPanel).body, Label):
			titles.append((label as Label).text)
			break
	return titles


func test_injuries_are_remembered_in_order_and_bounded() -> void:
	var w := _world()
	assert_eq(w.injuries_of(5), [], "no history yet")
	for i in 20:
		w.record_injury(5, 2026 + i, "sprained ankle", 3 + i, i % 7 == 0)
	var rows := w.injuries_of(5)
	assert_eq(rows.size(), FcWorld.INJURY_HISTORY_LIMIT, "bounded")
	assert_eq(rows[rows.size() - 1]["year"], 2045, "newest last")
	assert_eq(rows[0]["year"], 2034, "the oldest dropped off")


func test_the_history_is_saved_and_an_older_save_loads_as_empty() -> void:
	var w := _world()
	w.record_injury(3, 2026, "torn meniscus", 30, false)
	w.record_injury(3, 2027, "torn ACL", 82, true)
	var again := FcWorld.from_dict(JSON.parse_string(JSON.stringify(w.to_dict())), FcDefinitionSet.load_default())
	assert_eq(again.injuries_of(3), w.injuries_of(3), "survives a save and load through JSON")
	var old: Dictionary = w.to_dict()
	old.erase("injury_history")
	assert_eq(FcWorld.from_dict(old, FcDefinitionSet.load_default()).injuries_of(3), [], "a save from before the history existed loads as empty")
	assert_eq(FcVersion.DATA_VERSION, 5, "the injury history itself needed no version (an additive section); the version moved on for the play-by-play")


func test_a_played_season_records_the_injuries_it_causes() -> void:
	var w := _world()
	var engine := FcSeasonEngine.for_league(w, 1)
	var rng := FcRng.new(6)
	var season := engine.start_season(1, 2026, FcDate.new(2026, 10, 20), rng)
	engine.play_full_season(season, rng)
	var total := 0
	for pid in w.injury_history:
		for row in w.injury_history[pid]:
			total += 1
			assert_eq(row["year"], 2026)
			assert_true(row["games"] >= 1 and str(row["injury"]) != "")
	assert_true(total >= 5, "a season of injuries was recorded (%d)" % total)


func _owner() -> void:
	DirAccess.remove_absolute(PREFS)
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_injury_history")
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "name": "Health League"}))
	app.on_start_game(app._pending_state.world.teams.ids()[2])
	app.on_advance(10)


func test_the_owner_view_model_and_dossier_show_health() -> void:
	_owner()
	var world: FcWorld = app.controller.state.world
	var pid: int = world.teams.get_by_id(app.controller.state.user_team_id).roster.player_ids[0]
	var p: FcPlayer = world.players.get_by_id(pid)
	p.games_out = 0
	p.injury = ""
	world.injury_history.erase(pid)
	world.record_injury(pid, 2025, "sprained ankle", 4, false)
	world.record_injury(pid, 2026, "torn ACL", 82, true)
	var vm := FcPlayerPresentation.from_player(world, pid, app.controller.state.current_season, app.controller.league_id)
	var h: Dictionary = vm["health"]
	assert_eq(h["games_out"], 0)
	assert_eq(h["games_missed"], 86)
	assert_eq(h["severe_count"], 1)
	assert_eq(h["history"][0]["injury"], "torn ACL", "newest first")
	assert_true(h["durability"] >= 0 and h["durability"] <= 100)
	assert_true(h["medical_level"] >= 0, "the club's medical level")
	var profile := FcPlayerProfile.new().setup(vm)
	assert_true("Health" in _panel_titles(profile._body), "the Health panel is on the Overview")
	var trees := _find(profile._body, Tree)
	var cells: Array = []
	for tree in trees:
		var item: TreeItem = (tree as Tree).get_root().get_first_child() if (tree as Tree).get_root() != null else null
		while item != null:
			cells.append(item.get_text(1))
			item = item.get_next()
	assert_true("Torn ACL" in cells and "Sprained ankle" in cells, "the injury history table lists both injuries, newest first (%s)" % str(cells))
	assert_eq(cells[0], "Torn ACL")
	profile.free()


func test_an_injured_player_shows_a_status_chip_and_the_games_out() -> void:
	_owner()
	var world: FcWorld = app.controller.state.world
	var pid: int = world.teams.get_by_id(app.controller.state.user_team_id).roster.player_ids[1]
	var p: FcPlayer = world.players.get_by_id(pid)
	p.games_out = 14
	p.injury = "sprained ankle"
	var vm := FcPlayerPresentation.from_player(world, pid, app.controller.state.current_season, app.controller.league_id)
	assert_eq(vm["health"]["games_out"], 14)
	var profile := FcPlayerProfile.new().setup(vm)
	var found := false
	for chip in _find(profile, FcStatusChip):
		for label in _find(chip, Label):
			if "Out 14 games" in (label as Label).text:
				found = true
	assert_true(found, "the hero says he is out and why")
	profile.free()


func test_a_healthy_player_with_no_history_says_so() -> void:
	_owner()
	var world: FcWorld = app.controller.state.world
	var pid: int = world.teams.get_by_id(app.controller.state.user_team_id).roster.player_ids[2]
	world.injury_history.erase(pid)
	var p: FcPlayer = world.players.get_by_id(pid)
	p.games_out = 0
	p.injury = ""
	var profile := FcPlayerProfile.new().setup(FcPlayerPresentation.from_player(world, pid, app.controller.state.current_season, app.controller.league_id))
	var texts: Array = _find(profile._body, Label).map(func(l: Label) -> String: return l.text)
	assert_true("No injuries on record." in texts and "Healthy" in texts)
	profile.free()


func test_a_dynasty_card_has_no_health_panel() -> void:
	DirAccess.remove_absolute(PREFS)
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_injury_history")
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	FcSafeFile.remove_tree("user://test_dynasty_injury_history")
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new("user://test_dynasty_injury_history"))
	app.dynasty.catalog = FcDynastyFixture.catalog()
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
	assert_true(app.dynasty_ui.on_create("Healthy Kings", "HLK"))
	var vm := FcPlayerPresentation.from_card(app.dynasty.card_detail(FcDynastyFixture.card_id(0)), app.dynasty)
	assert_true(not vm.has("health") or (vm["health"] as Dictionary).is_empty(), "cards are never injured")
	var profile := FcPlayerProfile.new().setup(vm)
	assert_true(not ("Health" in _panel_titles(profile._body)))
	profile.free()
