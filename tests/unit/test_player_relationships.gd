extends FcTestCase
## The dossier's Relationships panel (Owner and Career only): ties built from data the game already keeps (seasons with the club, the best teammates;
## for a Career player the coach's trust, chemistry, the rival and the reputation tags). Dynasty cards have none; nothing is invented.

const PREFS := "user://test_preferences_relationships.cfg"

var app: FcApp


func after_each() -> void:
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()
		app = null
	DirAccess.remove_absolute(PREFS)
	DirAccess.remove_absolute("user://test_ui_state_relationships.cfg")
	FcSafeFile.remove_tree("user://test_saves_relationships")
	FcSafeFile.remove_tree("user://test_dynasty_relationships")
	FcDynastyFixture.wipe()


func _boot() -> void:
	DirAccess.remove_absolute(PREFS)
	app = FcApp.new()
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	app.saves = FcSaveManager.new("user://test_saves_relationships")
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


func _owner_vm(index: int = 0) -> Dictionary:
	_boot()
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5", "name": "Ties League"}))
	app.on_start_game(app._pending_state.world.teams.ids()[2])
	app.on_advance(10)
	var world: FcWorld = app.controller.state.world
	var team: FcTeam = world.teams.get_by_id(app.controller.state.user_team_id)
	var pid: int = team.roster.player_ids[index]
	world.careers[pid] = [[2024, team.id, 70, 100000, 900, 0, 0, 0, 0, 0, 0, 100, 200, 150], [2025, team.id, 60, 100000, 800, 0, 0, 0, 0, 0, 0, 100, 200, 150]]
	return FcPlayerPresentation.from_player(world, pid, app.controller.state.current_season, app.controller.league_id)


func test_the_words_for_a_relationship() -> void:
	assert_eq(FcPlayerProfile.relationship_word(10), "Strained")
	assert_eq(FcPlayerProfile.relationship_word(40), "Cool")
	assert_eq(FcPlayerProfile.relationship_word(50), "Steady")
	assert_eq(FcPlayerProfile.relationship_word(70), "Good")
	assert_eq(FcPlayerProfile.relationship_word(95), "Strong")


func test_an_owner_player_has_tenure_and_the_best_teammates() -> void:
	var vm := _owner_vm()
	var r: Dictionary = vm["relationships"]
	assert_eq(r["kind"], "owner")
	assert_eq(r["tenure_seasons"], 2, "two seasons in a row with this team")
	assert_eq(r["teams_played"], 1)
	var mates: Array = r["teammates"]
	assert_true(mates.size() >= 1 and mates.size() <= 4)
	for i in mates.size() - 1:
		assert_true(mates[i]["overall"] >= mates[i + 1]["overall"], "best first")
	var own_name: String = vm["name"]
	for m in mates:
		assert_true(str(m["name"]) != own_name, "a player is not his own teammate")


func test_a_traded_player_starts_a_new_run_with_the_new_club() -> void:
	var vm := _owner_vm(1)
	var world: FcWorld = app.controller.state.world
	var team: FcTeam = world.teams.get_by_id(app.controller.state.user_team_id)
	var pid: int = team.roster.player_ids[1]
	world.careers[pid] = [[2023, 999, 70, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1], [2024, team.id, 70, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1], [2025, team.id, 70, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1]]
	var r: Dictionary = FcPlayerPresentation.from_player(world, pid, app.controller.state.current_season, app.controller.league_id)["relationships"]
	assert_eq(r["tenure_seasons"], 2, "the earlier team does not count")
	assert_eq(r["teams_played"], 2)
	assert_true(vm.has("relationships"))


func test_the_owner_dossier_shows_a_relationships_panel() -> void:
	var profile := FcPlayerProfile.new().setup(_owner_vm())
	assert_true("Relationships" in _titles(profile._body), str(_titles(profile._body)))
	assert_true(_find(profile._body, FcPlayerChip).size() >= 1, "the best teammates are shown as player chips")
	profile.free()


func test_a_career_player_has_trust_chemistry_and_the_rival() -> void:
	_boot()
	var spec := FcPlayerBuild.default_spec("two_way_wing", 3, app._defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	assert_true(app.on_create_career(spec, 4))
	app.career.profile().coach_trust = 72
	app.career.profile().chemistry = 33
	app.career.profile().tags = ["outspoken"] as Array[String]
	var vm := FcPlayerPresentation.from_career(app.career)
	var r: Dictionary = vm["relationships"]
	assert_eq(r["kind"], "career")
	assert_eq(r["coach_trust"], 72)
	assert_eq(r["chemistry"], 33)
	assert_eq(r["tags"], ["outspoken"])
	assert_true(r.has("rival"))
	var profile := FcPlayerProfile.new().setup(vm)
	assert_true("Relationships" in _titles(profile._body))
	var texts: Array = _find(profile._body, Label).map(func(l: Label) -> String: return l.text)
	assert_true("Good" in texts and "Cool" in texts, "72 is Good and 33 is Cool (%s)" % str(texts))
	profile.free()


func test_a_dynasty_card_has_no_relationships() -> void:
	_boot()
	FcSafeFile.remove_tree("user://test_dynasty_relationships")
	app.dynasty = FcDynastyController.new(app.content, app._defs, FcDynastyStore.new("user://test_dynasty_relationships"))
	app.dynasty.catalog = FcDynastyFixture.catalog()
	app.dynasty_ui = FcDynastyUi.new(app, app.dynasty)
	assert_true(app.dynasty_ui.on_create("Alone Kings", "ALK"))
	var vm := FcPlayerPresentation.from_card(app.dynasty.card_detail(FcDynastyFixture.card_id(0)), app.dynasty)
	assert_true(not vm.has("relationships") or (vm["relationships"] as Dictionary).is_empty())
	var profile := FcPlayerProfile.new().setup(vm)
	assert_true(not ("Relationships" in _titles(profile._body)))
	profile.free()
