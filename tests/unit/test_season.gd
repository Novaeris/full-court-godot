extends FcTestCase
## Season engine: calendar, regular season, standings, playoffs, champion, awards, saving.

static var _cache: Dictionary = {}


func _build_world(seed_value: int = 77) -> FcWorld:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.roster_min = 13
	cfg.free_agent_count = 0
	cfg.assistant_coaches = 0
	cfg.scouts = 0
	return FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg).generate(seed_value)


## One fully played season shared by the read-only tests (about 3 seconds to build).
func _played() -> Dictionary:
	if _cache.is_empty():
		var world := _build_world()
		var engine := FcSeasonEngine.for_league(world, 1)
		var rng := FcRng.new(5)
		var season := engine.start_season(1, 2026, FcDate.new(2026, 10, 20), rng)
		engine.play_full_season(season, rng)
		_cache = {"world": world, "season": season, "engine": engine}
	return _cache


func _playoff_game_count(season: FcSeason) -> int:
	var n := 0
	for g in season.games:
		if g.series > 0:
			n += 1
	return n


func test_start_season_builds_the_calendar() -> void:
	var world := _build_world()
	var engine := FcSeasonEngine.for_league(world, 1)
	var season := engine.start_season(1, 2026, FcDate.new(2026, 10, 20), FcRng.new(1))
	var rules := world.rules_of_league(1)
	assert_eq(season.status, FcSeason.Status.PENDING)
	assert_eq(season.games.size(), FcMatchupPlanner.plan(world.leagues.get_by_id(1), rules.season).total_games())
	assert_eq(season.games_played_count(), 0)
	assert_eq(season.date_of_day(12).to_iso(), "2026-11-01")
	assert_true(world.seasons.has_id(season.id))
	assert_eq(world.season_of(1, 2026).id, season.id)
	assert_true(world.season_of(1, 2030) == null)
	assert_eq(world.validate(2026), [] as Array[String])


func test_playing_days_advances_the_season() -> void:
	var world := _build_world()
	var engine := FcSeasonEngine.for_league(world, 1)
	var rng := FcRng.new(2)
	var season := engine.start_season(1, 2026, FcDate.new(2026, 10, 20), rng)
	var first_day_games := season.games_on_day(0).size()
	assert_eq(engine.play_day(season, rng), first_day_games)
	assert_eq(season.status, FcSeason.Status.REGULAR)
	assert_eq(season.next_day, 1)
	engine.play_days(season, 10, rng)
	assert_eq(season.next_day, 11)
	assert_true(season.games_played_count() > first_day_games)
	for g in season.games:
		if g.day < 11:
			assert_true(g.played, "every game before day 11 is played")
		else:
			assert_true(not g.played)
	assert_eq(engine.play_playoff_day(season, rng), 0, "no playoffs during the regular season")


func test_regular_season_is_complete_and_consistent() -> void:
	var played := _played()
	var season: FcSeason = played["season"]
	var world: FcWorld = played["world"]
	var rules := world.rules_of_league(1)
	var league: FcLeague = world.leagues.get_by_id(1)
	var standings: FcStandings = played["engine"].standings_of(season)
	var wins := 0
	var losses := 0
	for t in league.all_team_ids():
		assert_eq(standings.games_played(t), rules.season.games_for_team(league, t), "team %d played its schedule" % t)
		wins += standings.records[t]["w"]
		losses += standings.records[t]["l"]
	assert_eq(wins, losses, "every win is someone's loss")
	assert_eq(wins, season.games.size() - _playoff_game_count(season))
	assert_eq(season.status, FcSeason.Status.COMPLETE)
	assert_eq(season.final_standings.size(), 8)
	assert_eq(season.final_standings[0][0], standings.league_ranking()[0])


func test_player_statistics_match_game_results() -> void:
	var played := _played()
	var season: FcSeason = played["season"]
	var regular_points := 0
	var playoff_points := 0
	for g in season.games:
		if g.series == 0:
			regular_points += g.home_score + g.away_score
		else:
			playoff_points += g.home_score + g.away_score
	var stat_points := 0
	for pid in season.stats.lines:
		stat_points += season.stats.lines[pid]["points"]
	assert_eq(stat_points, regular_points, "player points add up to the points scored in games")
	var stat_playoff := 0
	for pid in season.playoff_stats.lines:
		stat_playoff += season.playoff_stats.lines[pid]["points"]
	assert_eq(stat_playoff, playoff_points)
	var leader := season.stats.leaders("points", 10, 3)
	assert_true(leader.size() == 3 and season.stats.per_game(leader[0], "points") >= season.stats.per_game(leader[1], "points"))


func test_playoff_bracket_follows_the_rules() -> void:
	var played := _played()
	var season: FcSeason = played["season"]
	var world: FcWorld = played["world"]
	var rules := world.rules_of_league(1).playoffs
	var po := season.playoffs
	assert_eq(po.qualifiers.size(), rules.team_count)
	assert_eq(po.rounds, rules.round_count(world.leagues.get_by_id(1)))
	for s in po.series:
		assert_true(s.is_complete(), "every series finished")
		if s.is_bye:
			assert_eq(s.games_played(), 0)
			continue
		assert_eq(maxi(s.wins_a, s.wins_b), s.wins_needed(), "the winner reached the needed wins")
		assert_true(mini(s.wins_a, s.wins_b) < s.wins_needed())
		assert_true(s.games_played() <= s.best_of)
		var expected_winner := s.team_a if s.wins_a > s.wins_b else s.team_b
		assert_eq(s.winner_id, expected_winner)
	assert_eq(season.champion_id, po.champion_id())
	assert_true(season.champion_id != season.runner_up_id and season.champion_id > 0)
	var playoff_games := 0
	for g in season.games:
		if g.series > 0:
			var series := po.get_series(g.series)
			assert_true(g.involves(series.team_a) and g.involves(series.team_b), "a playoff game is between the teams of its series")
			assert_true(g.home_score != g.away_score)
			playoff_games += 1
	assert_true(playoff_games > 0)


func test_home_court_pattern_in_a_series() -> void:
	var s := FcPlayoffSeries.new()
	s.team_a = 10
	s.team_b = 20
	s.rank_a = 1
	s.rank_b = 5
	s.best_of = 7
	var homes := []
	for i in 7:
		homes.append(s.next_home_team())
		if i % 2 == 0:
			s.wins_a += 1
		else:
			s.wins_b += 1
	assert_eq(homes, [10, 10, 20, 20, 10, 20, 10], "2-2-1-1-1 for the better record")
	var short := FcPlayoffSeries.new()
	short.team_a = 1
	short.team_b = 2
	short.rank_a = 9
	short.rank_b = 3
	short.best_of = 3
	assert_eq(short.higher_team(), 2)
	assert_eq(short.next_home_team(), 2)
	short.wins_a = 1
	assert_eq(short.next_home_team(), 1, "game two goes to the other team")
	assert_eq(short.wins_needed(), 2)
	assert_true(short.record_game(1))
	assert_eq(short.winner_id, 1)
	assert_eq(short.loser_id(), 2)


func test_bracket_order_and_byes() -> void:
	assert_eq(FcPlayoffBuilder._bracket_order(8), [1, 8, 4, 5, 2, 7, 3, 6] as Array[int])
	assert_eq(FcPlayoffBuilder._bracket_order(4), [1, 4, 2, 3] as Array[int])
	var world := _build_world()
	var rules := FcPlayoffRules.new()
	rules.qualification = "seeding"
	rules.bracket = "league"
	rules.team_count = 6
	rules.series_lengths = [3, 5, 7] as Array[int]
	var standings := FcStandings.compute(world.leagues.get_by_id(1), [] as Array[FcScheduledGame])
	var po := FcPlayoffBuilder.build(world.leagues.get_by_id(1), standings, rules)
	assert_eq(po.qualifiers.size(), 6)
	assert_eq(po.rounds, 3)
	var byes := po.series.filter(func(s): return s.is_bye)
	assert_eq(byes.size(), 2)
	for s in byes:
		assert_true(s.is_complete() and s.winner_id > 0 and s.games_played() == 0)
	assert_eq(po.series.size(), 4 + 2 + 1)
	assert_eq(po.ready_series().size(), 2, "only the two real first-round series can start")


func test_awards_are_assigned() -> void:
	var played := _played()
	var season: FcSeason = played["season"]
	for key in ["mvp", "scoring_champion", "rebounding_champion", "assists_leader", "steals_leader", "blocks_leader", "finals_mvp"]:
		assert_true(season.awards.has(key), key)
		assert_true(season.stats.lines.has(season.awards[key]) or season.playoff_stats.lines.has(season.awards[key]), key)
	assert_eq(season.awards["all_league_first"].size(), 5)
	assert_eq(season.awards["all_league_second"].size(), 5)
	assert_true(season.awards["all_league_first"].has(season.awards["mvp"]))
	assert_eq(season.playoff_stats.lines[season.awards["finals_mvp"]]["team"], season.champion_id)


func test_same_seed_same_champion_and_results() -> void:
	var world_a := _build_world()
	var world_b := _build_world()
	var ea := FcSeasonEngine.for_league(world_a, 1)
	var eb := FcSeasonEngine.for_league(world_b, 1)
	var sa := ea.start_season(1, 2026, FcDate.new(2026, 10, 20), FcRng.new(9))
	var sb := eb.start_season(1, 2026, FcDate.new(2026, 10, 20), FcRng.new(9))
	ea.play_full_season(sa, FcRng.new(10))
	eb.play_full_season(sb, FcRng.new(10))
	assert_eq(sa.to_dict(), sb.to_dict())


func test_season_survives_save_and_load() -> void:
	var played := _played()
	var world: FcWorld = played["world"]
	var defs := FcDefinitionSet.load_default()
	var state := FcGameState.new(world, FcRng.new(1))
	state.user_team_id = world.teams.ids()[0]
	state.current_season = 2026
	assert_eq(state.validate(), [] as Array[String])
	var manager := FcSaveManager.new("user://test_saves_season")
	var saved := manager.save("season", state)
	assert_true(saved.is_ok(), saved.message)
	var loaded := manager.load_slot("season", defs)
	assert_true(loaded.is_ok(), loaded.message)
	assert_eq(loaded.warnings, [] as Array[String])
	var original: FcSeason = played["season"]
	var copy := loaded.state.world.season_of(1, 2026)
	assert_eq(copy.to_dict(), original.to_dict())
	manager.delete_slot("season")
	DirAccess.remove_absolute("user://test_saves_season")


func test_season_validation_catches_problems() -> void:
	var world := _build_world()
	var engine := FcSeasonEngine.for_league(world, 1)
	var season := engine.start_season(1, 2026, FcDate.new(2026, 10, 20), FcRng.new(3))
	var league: FcLeague = world.leagues.get_by_id(1)
	season.games[0].played = true
	assert_true(not season.validate(league).is_empty(), "a pending season cannot have results")
	season.games[0].played = false
	season.games[0].home_id = 999
	assert_true(not season.validate(league).is_empty(), "teams must be in the league")
	season.games[0].home_id = season.games[0].away_id
	assert_true(not season.validate(league).is_empty(), "a team cannot play itself")


func test_season_round_trip_when_partly_played() -> void:
	var world := _build_world()
	var engine := FcSeasonEngine.for_league(world, 1)
	var rng := FcRng.new(4)
	var season := engine.start_season(1, 2026, FcDate.new(2026, 10, 20), rng)
	engine.play_days(season, 15, rng)
	var copy := FcSeason.from_dict(JSON.parse_string(JSON.stringify(season.to_dict())))
	assert_eq(copy.to_dict(), season.to_dict())
	assert_eq(copy.next_day, 15)
	assert_eq(copy.status, FcSeason.Status.REGULAR)
