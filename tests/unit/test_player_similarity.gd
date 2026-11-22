extends FcTestCase
## "Plays like": the pure similarity score and nearest-players list, and the dossier panel built from it for Owner, Career and Dynasty.

const PREFS := "user://test_preferences_similarity.cfg"

var app: FcApp


func after_each() -> void:
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()
		app = null
	DirAccess.remove_absolute(PREFS)
	DirAccess.remove_absolute("user://test_ui_state_similarity.cfg")
	FcSafeFile.remove_tree("user://test_saves_similarity")
	FcSafeFile.remove_tree("user://test_dynasty_similarity")
	FcDynastyFixture.wipe()


func _boot() -> void:
	DirAccess.remove_absolute(PREFS)
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_similarity")
	Engine.get_main_loop().root.add_child(app)
	app.setup()


func _find(node: Node, type: Variant) -> Array:
	var out: Array = []
	if is_instance_of(node, type):
		out.append(node)
	for c in node.get_children():
		out.append_array(_find(c, type))
	return out


func _titles(root: Node) -> Array:
	var titles: Array = []
	for panel in _find(root, FcPanel):
		for label in _find((panel as FcPanel).body, Label):
			titles.append((label as Label).text)
			break
	return titles


func test_identical_players_score_100_and_the_score_falls_with_the_gap() -> void:
	var keys := ["a", "b", "c"]
	var base := {"a": 70, "b": 60, "c": 50}
	assert_eq(FcPlayerSimilarity.similarity(base, base.duplicate(), keys), 100)
	var near := FcPlayerSimilarity.similarity(base, {"a": 72, "b": 58, "c": 52}, keys)
	var far := FcPlayerSimilarity.similarity(base, {"a": 90, "b": 30, "c": 80}, keys)
	assert_true(near > far and near >= 90 and far < 50, "near %d far %d" % [near, far])
	assert_eq(FcPlayerSimilarity.similarity(base, {"a": 70, "b": 60, "c": 50}, []), 0, "no keys, no score")
	assert_eq(FcPlayerSimilarity.similarity({"a": 100, "b": 100, "c": 100}, {"a": 0, "b": 0, "c": 0}, keys), 0, "never below zero")


func test_the_nearest_list_is_sorted_stable_and_bounded() -> void:
	var keys := ["a", "b"]
	var target := {"a": 50, "b": 50}
	var candidates: Array = []
	for i in 12:
		candidates.append({"id": i, "values": {"a": 50 + i, "b": 50 - i}})
	candidates.append({"id": 99, "values": {"a": 50, "b": 50}})
	candidates.append({"id": 98, "values": {"a": 50, "b": 50}})
	var hits := FcPlayerSimilarity.nearest(target, candidates, keys, 5)
	assert_eq(hits.size(), 5)
	assert_eq([hits[0]["id"], hits[1]["id"], hits[2]["id"]], [0, 98, 99], "ties are broken by id, so the list never changes")
	for i in hits.size() - 1:
		assert_true(hits[i]["similarity"] >= hits[i + 1]["similarity"], "best first")
	assert_eq(hits, FcPlayerSimilarity.nearest(target, candidates, keys, 5), "deterministic")


func test_an_owner_player_plays_like_five_other_active_players() -> void:
	_boot()
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "name": "Similar League"}))
	app.on_start_game(app._pending_state.world.teams.ids()[2])
	app.on_advance(10)
	var world: FcWorld = app.controller.state.world
	var pid: int = world.teams.get_by_id(app.controller.state.user_team_id).roster.player_ids[0]
	var vm := FcPlayerPresentation.from_player(world, pid, app.controller.state.current_season, app.controller.league_id)
	var similar: Array = vm["similar"]
	assert_eq(similar.size(), 5)
	for i in similar.size():
		assert_true(str(similar[i]["name"]) != str(vm["name"]), "never himself")
		assert_true(int(similar[i]["similarity"]) >= 0 and int(similar[i]["similarity"]) <= 100)
		if i > 0:
			assert_true(int(similar[i - 1]["similarity"]) >= int(similar[i]["similarity"]))
	assert_eq(FcPlayerPresentation.from_player(world, pid, app.controller.state.current_season, app.controller.league_id)["similar"], similar, "the same list every time")
	var profile := FcPlayerProfile.new().setup(vm)
	assert_true("Plays like" in _titles(profile._body), str(_titles(profile._body)))
	assert_true(_find(profile._body, FcPlayerChip).size() >= 5)
	profile.free()


func test_computing_similar_players_changes_nothing() -> void:
	_boot()
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "name": "Similar League"}))
	app.on_start_game(app._pending_state.world.teams.ids()[2])
	var world: FcWorld = app.controller.state.world
	var pid: int = world.teams.get_by_id(app.controller.state.user_team_id).roster.player_ids[0]
	var before := JSON.stringify(world.to_dict())
	FcPlayerPresentation.from_player(world, pid, app.controller.state.current_season, app.controller.league_id)
	assert_eq(JSON.stringify(world.to_dict()), before, "read only")


func test_a_dynasty_card_plays_like_other_players_cards() -> void:
	_boot()
	FcSafeFile.remove_tree("user://test_dynasty_similarity")
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new("user://test_dynasty_similarity"))
	app.dynasty.catalog = FcDynastyFixture.catalog()
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
	assert_true(app.dynasty_ui.on_create("Alike Kings", "ALK"))
	var row := app.dynasty.card_detail(FcDynastyFixture.card_id(0))
	var vm := FcPlayerPresentation.from_card(row, app.dynasty)
	var similar: Array = vm["similar"]
	assert_true(similar.size() >= 1 and similar.size() <= 5, "other players' cards (%d)" % similar.size())
	var names := {}
	for s in similar:
		assert_true(str(s["name"]) != str(row["name"]), "not the same player")
		assert_true(not names.has(s["name"]), "one card per player")
		names[s["name"]] = true
	var profile := FcPlayerProfile.new().setup(vm)
	assert_true("Plays like" in _titles(profile._body))
	profile.free()
