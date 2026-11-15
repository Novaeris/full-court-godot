extends FcTestCase
## News feed and stored box scores.


func _game(seed_value: int = 12) -> FcGameController:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 15
	cfg.assistant_coaches = 1
	cfg.scouts = 0
	return FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), seed_value, FcGameState.MODE_OWNER, 1)


func test_news_items_can_be_added_and_are_capped() -> void:
	var w := FcTestData.world()
	w.add_news(FcDate.new(2026, 11, 1), "injury", "Someone got hurt", 1)
	assert_eq(w.news.size(), 1)
	assert_eq(w.news[0]["date"], "2026-11-01")
	for i in 400:
		w.add_news(FcDate.new(2026, 11, 1), "milestone", "item %d" % i)
	assert_eq(w.news.size(), FcWorld.NEWS_LIMIT)
	assert_eq(w.news[w.news.size() - 1]["text"], "item 399", "the newest items are kept")


func test_a_season_produces_champion_and_award_news() -> void:
	var g := _game()
	g.sim_playoffs()
	var kinds := {}
	for item in g.state.world.news:
		kinds[item["kind"]] = true
	assert_true(kinds.has("champion"), "the champion is announced")
	assert_true(kinds.has("award"), "awards are announced")
	var champion_name := g.state.world.team_display_name(g.season().champion_id)
	assert_true(g.state.world.news.any(func(n): return champion_name in n["text"] and n["kind"] == "champion"))


func test_offseason_news_about_draft_and_signings() -> void:
	var g := _game()
	g.start_next_season()
	var kinds := {}
	for item in g.state.world.news:
		kinds[item["kind"]] = true
	assert_true(kinds.has("draft"), "the first pick is news")
	assert_true(g.state.world.news.size() <= FcWorld.NEWS_LIMIT)


func test_injury_news_covers_the_owners_team_and_stars() -> void:
	var g := _game(31)
	g.engine.watched_teams = [g.state.user_team_id] as Array[int]
	g.sim_regular_season()
	var injuries := g.state.world.news.filter(func(n): return n["kind"] == "injury")
	assert_true(injuries.size() > 0, "injuries were reported")
	for n in injuries:
		assert_true("will miss" in n["text"])


func test_recent_box_scores_are_kept_for_the_owners_team() -> void:
	var g := _game()
	g.advance_days(40)
	var season := g.season()
	assert_true(season.recent_boxes.size() > 0 and season.recent_boxes.size() <= FcSeason.RECENT_BOX_LIMIT)
	var mine := g.state.user_team_id
	for entry in season.recent_boxes:
		var box := FcBoxScore.from_dict(entry["box"])
		assert_true(box.team_ids.has(mine), "only the owner's games are stored")
		assert_true(box.players.size() > 10 and box.scores[0] != box.scores[1])
	var copy := FcSeason.from_dict(JSON.parse_string(JSON.stringify(season.to_dict())))
	assert_eq(copy.recent_boxes.size(), season.recent_boxes.size())
	assert_eq(copy.to_dict(), season.to_dict())


func test_news_and_boxes_survive_saving() -> void:
	var g := _game()
	g.advance_days(30)
	var manager := FcSaveManager.new("user://test_saves_news")
	assert_true(g.autosave(manager).is_ok())
	var loaded := manager.load_slot(FcSaveManager.AUTOSAVE_SLOT, FcDefinitionSet.load_default())
	assert_true(loaded.is_ok(), loaded.message)
	assert_eq(loaded.state.world.news, g.state.world.news)
	var resumed := FcGameController.resume(loaded.state)
	assert_eq(resumed.season().recent_boxes.size(), g.season().recent_boxes.size())
	manager.delete_slot(FcSaveManager.AUTOSAVE_SLOT)
	DirAccess.remove_absolute("user://test_saves_news")


func test_ui_shows_news_and_box_scores() -> void:
	var app := FcApp.new()
	app.saves = FcSaveManager.new("user://test_saves_ui_news")
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	assert_true(app.on_create_league({"teams": 8, "conferences": 2, "divisions": 1, "free_agents": 10, "seed": "9"}))
	app.on_start_game(app._pending_state.world.teams.ids()[0])
	app.on_advance(30)
	var news_tab := app.build_tab("News")
	var trees: Array = []
	var stack: Array = [news_tab]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Tree:
			trees.append(n)
		stack.append_array(n.get_children())
	assert_eq(trees.size(), 1)
	news_tab.free()
	var season := app.controller.season()
	var entry: Dictionary = season.recent_boxes[season.recent_boxes.size() - 1]
	var text := app.box_score_text(int(entry["day"]), int(entry["series"]))
	assert_true("PTS" in text and "MIN" in text and "(final" in text, "the box score text has the table")
	assert_eq(app.box_score_text(9999, 0), "", "unknown games give nothing")
	Engine.get_main_loop().root.remove_child(app)
	app.free()
	DirAccess.remove_absolute("user://test_saves_ui_news")
