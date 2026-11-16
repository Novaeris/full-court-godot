extends FcTestCase
## The owner's reputation and changing teams.

func _game(seed_value: int = 120, teams: int = 12) -> FcGameController:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = teams
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1 if teams <= 8 else 3
	cfg.roster_size = 13
	cfg.free_agent_count = 10
	cfg.assistant_coaches = 1
	cfg.scouts = 1
	return FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), seed_value, FcGameState.MODE_OWNER, 0)


func test_reputation_starts_in_the_middle_and_is_recorded_each_season() -> void:
	var g := _game()
	assert_eq(g.owner_reputation(), FcGameState.START_REPUTATION)
	assert_true(g.owner_history().is_empty())
	g.sim_playoffs()
	var shown := g.owner_reputation()   # the finished season already counts
	assert_eq(g.owner_history().size(), 1)
	g.begin_offseason()
	assert_eq(g.owner_reputation(), shown, "begin_offseason does not count the season twice")
	assert_eq(g.owner_history().size(), 1)
	var row: Array = g.owner_history()[0]
	assert_eq([row[0], row[1]], [2026, g.state.user_team_id])
	var expected := clampi(roundi(0.7 * FcGameState.START_REPUTATION + 0.3 * row[2]) + 5 * row[4], 0, 100)
	assert_eq(g.owner_reputation(), expected)
	g.draft_auto_rest()
	g.start_next_season()
	g.sim_playoffs()
	g.begin_offseason()
	assert_eq(g.owner_history().size(), 2, "one row per season, never twice")


func test_job_offers_only_at_season_end_and_are_stable() -> void:
	var g := _game()
	assert_true(g.job_offers().is_empty(), "no offers mid-season")
	g.sim_playoffs()
	var a := g.job_offers()
	assert_true(a.size() >= 1 and a.size() <= 3)
	assert_eq(a, g.job_offers(), "the same offers every time you look")
	for o in a:
		assert_true(o["team"] != g.state.user_team_id)
	for i in range(1, a.size()):
		assert_true(a[i - 1]["valuation"] >= a[i]["valuation"], "most valuable first")


func test_a_better_reputation_opens_better_franchises() -> void:
	var g := _game(121, 20)
	g.sim_playoffs()
	g.state.owner_career["reputation"] = 5
	var low := g.job_offers()
	g.state.owner_career["reputation"] = 100
	var high_pool := {}
	for seed_year in 1:
		for o in g.job_offers():
			high_pool[o["team"]] = true
	var prestige := g._prestige()
	for o in low:
		assert_true(prestige[o["team"]] <= 0.05 + 0.25 + 0.0001, "a low reputation only gets the less valuable franchises")
	assert_true(not high_pool.is_empty())


func test_transferring_changes_the_team_once_a_season() -> void:
	var g := _game(122)
	g.sim_playoffs()
	var old_team := g.state.user_team_id
	var offer: Dictionary = g.job_offers()[0]
	assert_true(not g.transfer_to(old_team)["ok"], "you cannot 'move' to your own team")
	var r := g.transfer_to(offer["team"])
	assert_true(r["ok"], r["reason"])
	assert_eq(g.state.user_team_id, offer["team"])
	assert_true(g.engine.human_teams.has(offer["team"]) and not g.engine.human_teams.has(old_team), "the engine now treats the new team as yours")
	assert_true(not g.transfer_to(g.job_offers()[0]["team"] if not g.job_offers().is_empty() else old_team)["ok"], "once a season")
	assert_eq(g.owner_history().size(), 1, "the finished season is recorded for the old team")
	assert_eq(g.owner_history()[0][1], old_team)
	assert_eq(g.state.validate(), [] as Array[String])
	g.begin_offseason()
	g.draft_auto_rest()
	g.start_next_season()
	assert_eq(g.state.current_season, 2027)
	assert_eq(g.state.validate(), [] as Array[String])
	assert_true(g.business().cash >= 0, "the new team's books are yours now")


func test_pending_agreements_are_dropped_when_changing_teams() -> void:
	var g := _game(123)
	g.sim_playoffs()
	var entry: Dictionary = g.expiring_players()[0]
	assert_true(g.extend_contract(entry["player"].id)["ok"])
	assert_true(not g.state.agreed_extensions.is_empty())
	assert_true(g.transfer_to(g.job_offers()[0]["team"])["ok"])
	assert_true(g.state.agreed_extensions.is_empty() and g.state.agreed_terms.is_empty())


func test_owner_career_is_saved_and_old_saves_start_fresh() -> void:
	var state := FcGameState.new(FcWorld.new(FcDefinitionSet.load_default()), FcRng.new(1))
	state.owner_career = {"reputation": 71, "history": [[2026, 3, 64, 52, 1]], "transfer_year": 2026}
	var back := FcGameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), FcDefinitionSet.load_default())
	assert_eq(back.owner_career, {"reputation": 71, "history": [[2026, 3, 64, 52, 1]], "transfer_year": 2026})
	var old := state.to_dict()
	old.erase("owner_career")
	assert_eq(FcGameState.from_dict(old, FcDefinitionSet.load_default()).owner_career["reputation"], FcGameState.START_REPUTATION)


func test_history_tab_shows_the_ownership_career() -> void:
	var app := FcApp.new()
	app.saves = FcSaveManager.new("user://test_saves_career_ui")
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "5"}))
	app.on_start_game(app._pending_state.world.teams.ids()[2])
	app.on_sim_regular()
	app.on_sim_playoffs()
	app.controller.owner_reputation()   # the finished season counts
	var tab := app.build_tab("History")
	var text := ""
	var stack: Array = [tab]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			text += (n as Label).text + "\n"
		stack.append_array(n.get_children())
	assert_true("ownership career" in text, "the career section appears after the first season")
	tab.free()
	Engine.get_main_loop().root.remove_child(app)
	app.free()
	DirAccess.remove_absolute("user://test_saves_career_ui")
