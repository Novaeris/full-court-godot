extends FcTestCase
## Game history (Phase 2B): the play-by-play of a watched game is kept with its box score in Owner and Career saves, reaches the
## screens through Career and Dynasty results, survives saving, is dropped with the box when a season is archived, and older saves
## (data version 2) migrate to a version with empty logs.

var defs: FcDefinitionSet


func before_each() -> void:
	defs = FcDefinitionSet.load_default()


func _owner(seed_value: int = 12) -> FcGameController:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 15
	cfg.assistant_coaches = 1
	cfg.scouts = 0
	return FcGameController.new_game(FcWorldGenerator.new(data, defs, cfg), seed_value, FcGameState.MODE_OWNER, 1)


# --- Owner: stored with the box score ---------------------------------------------------------------------------------

func test_a_watched_game_keeps_its_play_by_play_and_it_matches_the_box() -> void:
	var g := _owner()
	g.advance_days(30)
	var boxes: Array = g.season().recent_boxes
	assert_true(boxes.size() > 3, "several games were kept")
	for entry in boxes:
		var log := FcGameEventLog.from_dict(entry["events"])
		assert_true(log.size() > 100, "the game was written down")
		var box := FcBoxScore.from_dict(entry["box"])
		var timeline := FcPlayByPlay.entries(log, box)
		var last: Dictionary = timeline[timeline.size() - 1]
		assert_eq([last["home"], last["away"]], [box.scores[0], box.scores[1]], "the events add up to the stored final score")


func test_games_nobody_watches_are_not_recorded() -> void:
	var g := _owner()
	g.engine.watched_teams = [] as Array[int]
	g.advance_days(20)
	assert_eq(g.season().recent_boxes.size(), 0, "no watched team, no stored games")
	assert_true(g.season().games_played_count() > 0, "games were played, just not recorded")


func test_the_play_by_play_is_saved_and_loaded_as_whole_numbers() -> void:
	var g := _owner()
	g.advance_days(15)
	var season := g.season()
	var copy := FcSeason.from_dict(JSON.parse_string(JSON.stringify(season.to_dict())))
	assert_eq(copy.to_dict(), season.to_dict(), "the season, play-by-play included, survives a JSON round trip unchanged")
	assert_true((copy.recent_boxes[0]["events"]["rows"] as Array).size() > 100)
	assert_true(copy.recent_boxes[0]["events"]["rows"][0][0] is int, "rows come back as integers, not floats")


func test_a_full_save_and_load_keeps_the_replays() -> void:
	var g := _owner()
	g.advance_days(15)
	var dir := "user://test_saves_history"
	FcSafeFile.remove_tree(dir)
	var manager := FcSaveManager.new(dir)
	assert_true(manager.save("slot_1", g.state, "History").is_ok())
	var loaded := manager.load_slot("slot_1", defs)
	assert_true(loaded.is_ok(), loaded.message)
	var season: FcSeason = loaded.state.world.seasons.get_by_id(g.season().id)
	assert_eq(season.recent_boxes.size(), g.season().recent_boxes.size())
	assert_eq(season.recent_boxes[0]["events"], g.season().recent_boxes[0]["events"], "the log came back identical")
	FcSafeFile.remove_tree(dir)


func test_archiving_a_season_drops_the_stored_games_and_their_play_by_play() -> void:
	var g := _owner()
	var season := g.season()
	season.archive()
	assert_eq(season.archived, false, "a season still being played is never archived")
	g.advance_days(15)
	assert_true(season.recent_boxes.size() > 0, "the unfinished season keeps its games")
	g.sim_playoffs()
	assert_true(season.recent_boxes.size() > 0)
	season.archive()
	assert_true(season.archived)
	assert_eq(season.recent_boxes.size(), 0, "a finished, archived season keeps no box scores or replays, so saves stay small")


func test_one_stored_replay_is_small_enough() -> void:
	var g := _owner()
	g.advance_days(5)
	var text := JSON.stringify(g.season().recent_boxes[0]["events"])
	assert_true(text.length() < 70000, "a replay is %d characters; twenty of them must stay a modest part of a save" % text.length())


# --- migration ---------------------------------------------------------------------------------------------------------------

func test_version_two_saves_migrate_to_empty_logs_and_keep_everything_else() -> void:
	var migrator := FcSaveMigrator.new()
	var payload := {"current_season": 2026, "world": {"seasons": [{"id": 1, "recent_boxes": [
		{"day": 3, "series": 0, "box": {"scores": [90, 88]}}, {"day": 5, "series": 0, "box": {"scores": [70, 71]}, "events": {"rows": [[1, 0, 0, 0, 0, 1]]}}]}]}}
	var result := migrator.migrate(payload, 2, 3)
	assert_true(result["ok"], result["message"])
	var boxes: Array = result["payload"]["world"]["seasons"][0]["recent_boxes"]
	assert_eq(boxes[0]["events"], {"rows": []}, "an older game gets an empty log")
	assert_eq(boxes[1]["events"], {"rows": [[1, 0, 0, 0, 0, 1]]}, "a game that already has one is untouched")
	assert_eq(boxes[0]["box"], {"scores": [90, 88]}, "the box score is untouched")
	assert_eq(result["payload"]["current_season"], 2026)
	assert_true(not payload["world"]["seasons"][0]["recent_boxes"][0].has("events"), "the original payload was not edited in place")
	var odd := migrator.migrate({"world": "not a dictionary"}, 2, 3)
	assert_true(odd["ok"], "a payload with no seasons migrates without complaint")


func test_a_version_one_save_walks_both_steps() -> void:
	var out := FcSaveMigrator.new().migrate({"world": {"seasons": [{"recent_boxes": [{"day": 1, "series": 0, "box": {}}]}]}}, 1, FcVersion.DATA_VERSION)
	assert_true(out["ok"])
	assert_true(out["payload"].has("career_profiles"), "the version 1 to 2 step ran")
	assert_eq(out["payload"]["world"]["seasons"][0]["recent_boxes"][0]["events"], {"rows": []}, "and the 2 to 3 step")


# --- Career and Dynasty results carry the play-by-play ----------------------------------------------------------------------

func test_career_games_carry_their_play_by_play() -> void:
	var spec := FcPlayerBuild.default_spec("two_way_wing", 3, defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	var strong := ["perimeter_defense", "three_point", "layups", "speed", "agility", "stamina", "rebounding", "passing", "ball_handling"]
	for key in spec["attributes"]:
		spec["attributes"][key] = 70 if strong.has(key) else 25
	var c: FcCareerController = FcCareerController.new_career(spec, 51)["controller"]
	assert_true(c.join_team(c.state.world.teams.ids()[2])["ok"])
	var pending := c.pending_event()
	if not pending.is_empty():
		c.answer_event(pending["choices"][0]["key"])
	var r := c.advance_days(14)
	assert_true(r["ok"])
	var played: Array = r["games"]
	assert_true(played.size() > 0, "his team played")
	for game in played:
		var log := FcGameEventLog.from_dict(game["events"])
		assert_true(log.size() > 100, "the game came with its play-by-play")
		var timeline := FcPlayByPlay.entries(log, FcBoxScore.from_dict(game["box"]))
		assert_eq(timeline[timeline.size() - 1]["home"], int(game["box"]["scores"][0]))


func test_a_dynasty_game_result_carries_its_play_by_play() -> void:
	var env := FcDynastyEnv.make(31)
	var r := env.session.commit(func() -> FcDynastyResult: return FcDynastyPlay.quick_game(env.session.profile, env.catalog, "even"))
	assert_true(r.ok, r.message)
	var log := FcGameEventLog.from_dict(r.data["events"])
	assert_true(log.size() > 100)
	var box := FcBoxScore.from_dict(r.data["box"])
	var timeline := FcPlayByPlay.entries(log, box)
	assert_eq([timeline[timeline.size() - 1]["home"], timeline[timeline.size() - 1]["away"]], [box.scores[0], box.scores[1]])
	assert_true(not str(env.session.profile.to_dict()).contains("\"events\""), "a Dynasty profile save never holds the replay (the pass-through is display only)")
	FcSafeFile.remove_tree(FcDynastyEnv.DIR)
