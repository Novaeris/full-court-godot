extends FcTestCase
## Eight teams: conference 1 = division 1 = teams 1-4, conference 2 = division 2 = teams 5-8.


func _league() -> FcLeague:
	return FcLeague.make_even(1, "T", 2, 1, 8)


func _game(home: int, away: int, home_score: int, away_score: int, series: int = 0) -> FcScheduledGame:
	var g := FcScheduledGame.new(0, home, away)
	g.played = true
	g.home_score = home_score
	g.away_score = away_score
	g.series = series
	return g


func _standings(games: Array) -> FcStandings:
	var typed: Array[FcScheduledGame] = []
	for g in games:
		typed.append(g)
	return FcStandings.compute(_league(), typed)


func test_records_and_basic_ranking() -> void:
	var s := _standings([
		_game(1, 2, 100, 90), _game(1, 3, 100, 95), _game(2, 1, 80, 85),
		_game(5, 1, 99, 100), _game(3, 5, 70, 60),
	])
	assert_eq(s.records[1]["w"], 4)
	assert_eq(s.records[1]["l"], 0)
	assert_eq(s.records[1]["home_w"], 2)
	assert_eq(s.records[1]["away_w"], 2)
	assert_eq(s.win_pct(1), 1.0)
	assert_eq(s.games_played(2), 2)
	assert_eq(s.records[2]["l"], 2)
	assert_eq(s.records[1]["div_w"], 3, "three division wins")
	assert_eq(s.records[1]["conf_w"], 3)
	assert_eq(s.point_differential(1), (100 - 90) + (100 - 95) + (85 - 80) + (100 - 99))
	assert_eq(s.streak_text(1), "W4")
	assert_eq(s.streak_text(2), "L2")
	assert_eq(s.last_ten(1), [4, 0] as Array[int])
	assert_eq(s.league_ranking()[0], 1)
	assert_eq(s.games_behind(1, 2), 3.0)
	assert_eq(s.win_pct(8), 0.0)
	assert_eq(s.streak_text(8), "-")


func test_playoff_games_do_not_count() -> void:
	var s := _standings([_game(1, 2, 100, 90), _game(1, 2, 100, 90, 3)])
	assert_eq(s.games_played(1), 1)


func test_unplayed_games_do_not_count() -> void:
	var g := FcScheduledGame.new(0, 1, 2)
	var s := _standings([g])
	assert_eq(s.games_played(1), 0)


func test_head_to_head_breaks_a_two_way_tie() -> void:
	# 1 and 2 both finish 2-1; 2 beat 1.
	var s := _standings([
		_game(1, 2, 90, 100),
		_game(1, 3, 100, 90), _game(1, 4, 100, 90),
		_game(2, 3, 100, 90), _game(4, 2, 100, 90),
	])
	assert_eq(s.records[1]["w"], 2)
	assert_eq(s.records[2]["w"], 2)
	var order := s.ranked([1, 2])
	assert_eq(order[0], 2, "the head-to-head winner is ranked first")


func test_conference_record_breaks_a_tie_without_a_meeting() -> void:
	# Teams 1 and 5 are both 1-1 and never met. 1 beat a conference rival (2); 5 beat a team from the other conference (2).
	var s := _standings([_game(1, 2, 100, 90), _game(6, 1, 100, 90), _game(5, 2, 100, 90), _game(6, 5, 100, 90)])
	assert_eq([s.records[1]["w"], s.records[1]["l"]], [1, 1])
	assert_eq([s.records[5]["w"], s.records[5]["l"]], [1, 1])
	assert_eq(s.records[1]["conf_w"], 1, "1's win was against its own conference")
	assert_eq(s.records[5]["conf_l"], 1, "5's loss was against its own conference")
	assert_eq(s.ranked([5, 1]), [1, 5] as Array[int])


func test_division_record_decides_between_division_mates() -> void:
	# 1 and 2 are both 1-1 with no head-to-head. 1's win came in the division, 2's win outside it.
	var s := _standings([_game(1, 3, 100, 90), _game(5, 1, 100, 90), _game(2, 6, 100, 90), _game(3, 2, 100, 90)])
	assert_eq(s.ranked([2, 1]), [1, 2] as Array[int])


func test_pure_point_differential_tiebreak() -> void:
	var s := _standings([_game(1, 5, 120, 100), _game(2, 6, 101, 100)])
	# 1 and 2 are 1-0; no common opponent; conference records equal (0-0 -> 0.5) so differential decides.
	assert_eq(s.ranked([2, 1]), [1, 2] as Array[int])
	# 5 and 6 are 0-1: 6 lost by one, 5 by twenty
	assert_eq(s.ranked([5, 6]), [6, 5] as Array[int])


func test_last_tiebreak_is_stable_team_id() -> void:
	var s := _standings([])
	assert_eq(s.ranked([4, 2, 8, 1]), [1, 2, 4, 8] as Array[int], "all equal: lowest id first, always")
	assert_eq(s.ranked([8, 1, 4, 2]), [1, 2, 4, 8] as Array[int])


func test_multi_team_tie_uses_head_to_head_among_the_tied() -> void:
	# 1 beats 2, 2 beats 3, 3 beats 1; everyone else identical, so differential decides.
	var s := _standings([_game(1, 2, 100, 99), _game(2, 3, 100, 90), _game(3, 1, 100, 90)])
	var order := s.ranked([1, 2, 3])
	assert_eq(order.size(), 3)
	assert_true(order.has(1) and order.has(2) and order.has(3))
	# differentials: 1 = +1 -10 = -9; 2 = -1 +10 = +9; 3 = -10 + 10 = 0
	assert_eq(order, [2, 3, 1] as Array[int])


func test_division_leaders_and_rankings() -> void:
	var s := _standings([_game(1, 2, 100, 90), _game(2, 3, 100, 90), _game(5, 6, 100, 90), _game(6, 7, 100, 90), _game(5, 7, 100, 90)])
	var leaders := s.division_leaders()
	assert_eq(leaders.size(), 2)
	var l := _league()
	assert_eq(leaders[l.conferences[0].divisions[0].id], 1)
	assert_eq(leaders[l.conferences[1].divisions[0].id], 5)
	assert_eq(s.conference_ranking(l.conferences[1])[0], 5)
	assert_eq(s.league_ranking().size(), 8)
	assert_eq(s.division_ranking(l.conferences[0].divisions[0])[0], 1)


func test_ranking_is_a_permutation_for_random_results() -> void:
	var rng := FcRng.new(3)
	var games: Array = []
	for i in 200:
		var a := rng.range_int(1, 8)
		var b := rng.range_int(1, 8)
		if a != b:
			games.append(_game(a, b, rng.range_int(80, 120), rng.range_int(80, 120)))
	var s := _standings(games)
	var order := s.league_ranking()
	assert_eq(order.size(), 8)
	for i in range(1, order.size()):
		assert_true(s.win_pct(order[i - 1]) >= s.win_pct(order[i]) - 0.0000001, "never out of order by record")
	var again := s.league_ranking()
	assert_eq(again, order, "stable")
