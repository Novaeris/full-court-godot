extends FcTestCase
## Career statistics and archiving of old seasons.

func _game(seed_value: int = 15) -> FcGameController:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 10
	cfg.assistant_coaches = 1
	cfg.scouts = 0
	return FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), seed_value, FcGameState.MODE_OWNER, 0)


func test_every_player_who_played_gets_a_career_row() -> void:
	var g := _game()
	g.sim_playoffs()
	var w := g.state.world
	var season := g.season()
	assert_true(w.careers.size() > 80, "most of the league has a career row")
	var total_points := 0
	for pid in w.careers:
		var rows: Array = w.careers[pid]
		assert_eq(rows.size(), 1)
		assert_eq(rows[0][0], 2026)
		assert_eq(rows[0].size(), FcWorld.CAREER_COLUMNS.size())
		total_points += rows[0][4]
	var game_points := 0
	for game in season.games:
		if game.series == 0:
			game_points += game.home_score + game.away_score
	assert_eq(total_points, game_points, "career points equal the points scored in the season")


func test_careers_accumulate_over_seasons() -> void:
	var g := _game(16)
	g.start_next_season()
	g.start_next_season()
	g.sim_playoffs()
	var w := g.state.world
	var most := 0
	var best_id := 0
	for pid in w.careers:
		if w.careers[pid].size() > most:
			most = w.careers[pid].size()
			best_id = pid
	assert_eq(most, 3, "a player who stayed in the league has three seasons")
	var totals := w.career_totals(best_id)
	assert_eq(totals["seasons"], 3)
	assert_true(totals["gp"] > 30 and totals["points"] > 100)
	var years: Array = w.careers[best_id].map(func(r): return r[0])
	assert_eq(years, [2026, 2027, 2028])


func test_recording_a_season_twice_does_not_double_count() -> void:
	var g := _game(17)
	g.sim_playoffs()
	var w := g.state.world
	var before := w.careers.duplicate(true)
	w.record_career(g.season())
	assert_eq(w.careers, before)


func test_old_seasons_are_archived_but_history_remains() -> void:
	var g := _game(18)
	for i in 3:
		g.start_next_season()
	var w := g.state.world
	var oldest := w.season_of(1, 2026)
	var recent := w.season_of(1, 2028)
	assert_true(oldest.archived and oldest.games.is_empty() and oldest.stats.lines.is_empty(), "the oldest season is archived")
	assert_true(oldest.champion_id > 0 and oldest.awards.has("mvp") and oldest.final_standings.size() == 8, "its history remains")
	assert_true(oldest.playoffs != null and oldest.draft.size() > 0)
	assert_true(not recent.archived and not recent.games.is_empty(), "recent seasons keep their detail")
	assert_eq(w.validate(2029), [] as Array[String])
	assert_true(w.careers.size() > 80, "career statistics outlive the archived season")


func test_archiving_shrinks_the_save() -> void:
	var g := _game(19)
	g.sim_playoffs()
	var season := g.season()
	var before := JSON.stringify(season.to_dict()).length()
	var copy := FcSeason.from_dict(season.to_dict())
	copy.archive()
	var after := JSON.stringify(copy.to_dict()).length()
	assert_true(after < before * 0.2, "an archived season is under a fifth of the size (%d -> %d)" % [before, after])
	var round_trip := FcSeason.from_dict(JSON.parse_string(JSON.stringify(copy.to_dict())))
	assert_true(round_trip.archived and round_trip.champion_id == season.champion_id)


func test_active_seasons_cannot_be_archived() -> void:
	var g := _game(20)
	g.advance_days(5)
	g.season().archive()
	assert_true(not g.season().archived)
	assert_true(g.season().games.size() > 0)


func test_careers_survive_saving() -> void:
	var g := _game(21)
	g.start_next_season()
	var manager := FcSaveManager.new("user://test_saves_careers")
	assert_true(g.autosave(manager).is_ok())
	var loaded := manager.load_slot(FcSaveManager.AUTOSAVE_SLOT, FcDefinitionSet.load_default())
	assert_true(loaded.is_ok(), loaded.message)
	assert_eq(loaded.state.world.careers, g.state.world.careers)
	manager.delete_slot(FcSaveManager.AUTOSAVE_SLOT)
	DirAccess.remove_absolute("user://test_saves_careers")


func test_career_leaders() -> void:
	var g := _game(22)
	g.start_next_season()
	g.sim_playoffs()
	var w := g.state.world
	var leaders := w.career_leaders("points", 5)
	assert_eq(leaders.size(), 5)
	for i in range(1, leaders.size()):
		assert_true(w.career_totals(leaders[i - 1])["points"] >= w.career_totals(leaders[i])["points"], "sorted best first")
	assert_true(w.career_totals(leaders[0])["seasons"] >= 1)
	assert_eq(w.career_leaders("points", 3).size(), 3)
	assert_eq(FcWorld.new(FcDefinitionSet.load_default()).career_leaders("points").size(), 0)
