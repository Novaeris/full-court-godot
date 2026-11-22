extends FcTestCase
## Team rivalries (Phase 3): worked out from the playoff series the world keeps. A hand-built history gives exact scores, levels and a
## year-by-year development; a real played league checks the invariants.

var w: FcWorld
var lid: int
var a: int
var b: int
var c: int
var x: int
var y: int


func before_each() -> void:
	var env := FcHistoryFixture.league()
	w = env["world"]
	lid = env["league_id"]
	var league: FcLeague = w.leagues.get_by_id(lid)
	var divisions := league.all_divisions()
	a = divisions[0].team_ids[0]
	b = divisions[0].team_ids[1]
	c = divisions[1].team_ids[0]   # a team in the other division
	x = divisions[0].team_ids[2]
	y = divisions[0].team_ids[3]


func _three_meetings() -> void:
	FcHistoryFixture.series_season(w, lid, 2000, [[a, b, 4, 3, 1], [x, y, 4, 0, 2]])   # a wins a game-seven first-round series
	FcHistoryFixture.series_season(w, lid, 2001, [[b, a, 4, 1, 1]])                    # b wins the final
	FcHistoryFixture.series_season(w, lid, 2002, [[a, b, 3, 4, 1], [x, y, 4, 2, 2]])   # b wins another game-seven series


func test_the_score_counts_meetings_close_series_finals_and_the_division() -> void:
	_three_meetings()
	var r := FcRivalries.new(w, lid)
	var s := r.summary_of(a, b)
	var low: int = mini(a, b)
	assert_eq(s["meetings"], 3)
	assert_eq(s["close"], 2, "two series went to the deciding game")
	assert_eq(s["finals"], 1)
	assert_true(s["same_division"])
	assert_eq(s["score"], 3 * FcRivalries.MEETING_POINTS + 2 * FcRivalries.CLOSE_POINTS + FcRivalries.FINAL_POINTS + FcRivalries.DIVISION_POINTS)
	assert_eq(s["score"], 58)
	assert_eq(s["level"], "Bitter")
	assert_eq(s["last_year"], 2002)
	assert_eq(int(s["wins_a"]) + int(s["wins_b"]), 3, "every series has a winner")
	var wins_of_a := int(s["wins_a"]) if low == a else int(s["wins_b"])
	assert_eq(wins_of_a, 1, "a won 2000 only; b won 2001 and 2002")
	assert_eq(r.summary_of(b, a), r.summary_of(a, b), "the pair has one rivalry, whichever way it is asked")


func test_the_rivalry_develops_year_by_year() -> void:
	_three_meetings()
	var dev := FcRivalries.new(w, lid).development(a, b)
	assert_eq(dev.size(), 3)
	assert_eq([dev[0]["year"], dev[1]["year"], dev[2]["year"]], [2000, 2001, 2002])
	assert_eq([dev[0]["score"], dev[1]["score"], dev[2]["score"]], [22, 42, 58])
	assert_eq([dev[0]["level"], dev[1]["level"], dev[2]["level"]], ["Budding", "Heated", "Bitter"])
	assert_eq(FcRivalries.new(w, lid).development(a, c), [] as Array[Dictionary], "no meetings, no development")


func test_a_pair_in_different_divisions_and_a_pair_that_never_met() -> void:
	FcHistoryFixture.series_season(w, lid, 2000, [[a, c, 4, 1, 1]])
	var r := FcRivalries.new(w, lid)
	var one := r.summary_of(a, c)
	assert_eq(one["score"], FcRivalries.MEETING_POINTS + FcRivalries.FINAL_POINTS, "one meeting in the final, no division bonus")
	assert_true(not one["same_division"])
	assert_eq(one["level"], "Budding")
	var none := r.summary_of(x, c)
	assert_eq([none["meetings"], none["score"], none["level"]], [0, 0, ""])
	assert_true(str(none["headline"]).contains("never met"))
	assert_true(r.summary_of(x, y)["same_division"], "teammates in a division are flagged even before they meet")
	assert_eq(r.summary_of(x, y)["score"], 0, "but a shared division alone is not a rivalry")


func test_the_headline_names_both_teams_and_the_leader() -> void:
	_three_meetings()
	var h := str(FcRivalries.new(w, lid).summary_of(a, b)["headline"])
	assert_true(h.contains(w.team_display_name(a)) and h.contains(w.team_display_name(b)), h)
	assert_true(h.contains("3 times") and h.contains("lead 2-1") and h.contains(w.team_display_name(b)), "b leads 2-1: %s" % h)


func test_rivalries_are_listed_strongest_first_per_team_and_league_wide() -> void:
	_three_meetings()
	FcHistoryFixture.series_season(w, lid, 2003, [[a, c, 4, 0, 1]])
	var r := FcRivalries.new(w, lid)
	var of_a := r.of_team(a, 5)
	assert_eq(of_a.size(), 2)
	assert_true(of_a[0]["score"] >= of_a[1]["score"], "strongest first")
	assert_eq([of_a[0]["a"], of_a[0]["b"]].has(b), true, "the 58-point rivalry with b is first")
	for entry in of_a:
		assert_true(entry["a"] == a or entry["b"] == a)
	var top := r.top(1)
	assert_eq(top.size(), 1)
	assert_eq(top[0]["score"], 58)
	assert_eq(r.of_team(a, 1).size(), 1, "the count limits the list")
	var all := r.all()
	for i in range(1, all.size()):
		assert_true(all[i - 1]["score"] >= all[i]["score"])


func test_levels_follow_the_thresholds() -> void:
	assert_eq(FcRivalries.level_of(0), "")
	assert_eq(FcRivalries.level_of(FcRivalries.BUDDING - 1), "")
	assert_eq(FcRivalries.level_of(FcRivalries.BUDDING), "Budding")
	assert_eq(FcRivalries.level_of(FcRivalries.HEATED - 1), "Budding")
	assert_eq(FcRivalries.level_of(FcRivalries.HEATED), "Heated")
	assert_eq(FcRivalries.level_of(FcRivalries.BITTER), "Bitter")


func test_byes_and_unfinished_series_are_not_meetings() -> void:
	var s := FcHistoryFixture.series_season(w, lid, 2000, [[a, b, 4, 2, 1]])
	var bye := FcPlayoffSeries.new()
	bye.number = 9
	bye.team_a = a
	bye.team_b = 0
	bye.is_bye = true
	bye.winner_id = a
	s.playoffs.series.append(bye)
	var open := FcPlayoffSeries.new()
	open.number = 10
	open.team_a = a
	open.team_b = c
	s.playoffs.series.append(open)   # no winner yet
	var r := FcRivalries.new(w, lid)
	assert_eq(r.summary_of(a, b)["meetings"], 1)
	assert_eq(r.summary_of(a, c)["meetings"], 0, "a series with no winner is not a meeting")


func test_a_real_played_league_obeys_the_invariants() -> void:
	var cfg := FcGenerationConfig.load_default(FcGenerationData.load_default())
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 15
	cfg.assistant_coaches = 1
	cfg.scouts = 0
	var g := FcGameController.new_game(FcWorldGenerator.new(FcGenerationData.load_default(), FcDefinitionSet.load_default(), cfg), 12, FcGameState.MODE_OWNER, 1)
	for i in 4:
		g.sim_playoffs()
		g.start_next_season()
	var real := g.state.world
	var expected := 0
	for s in real.seasons.all():
		if s.status == FcSeason.Status.COMPLETE and s.playoffs != null:
			for series in s.playoffs.series:
				if not series.is_bye and series.winner_id > 0 and series.team_a > 0 and series.team_b > 0:
					expected += 1
	var r := FcRivalries.new(real, g.league_id)
	var meetings := 0
	for entry in r.all():
		meetings += int(entry["meetings"])
		assert_true(entry["a"] < entry["b"])
		assert_eq(int(entry["wins_a"]) + int(entry["wins_b"]), int(entry["meetings"]))
		var dev := r.development(int(entry["a"]), int(entry["b"]))
		assert_eq(dev[dev.size() - 1]["score"], entry["score"], "the development ends at today's score")
		for i in range(1, dev.size()):
			assert_true(dev[i]["score"] >= dev[i - 1]["score"], "a rivalry never loses points")
	assert_eq(meetings, expected, "every finished series is counted once")
