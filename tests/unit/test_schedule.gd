extends FcTestCase


func _league(conferences: int, divisions: int, teams: int) -> FcLeague:
	return FcLeague.make_even(1, "T", conferences, divisions, teams)


func test_date_arithmetic() -> void:
	assert_eq(FcDate.new(2026, 10, 20).add_days(11).to_iso(), "2026-10-31")
	assert_eq(FcDate.new(2026, 10, 20).add_days(12).to_iso(), "2026-11-01")
	assert_eq(FcDate.new(2027, 2, 28).add_days(1).to_iso(), "2027-03-01")
	assert_eq(FcDate.new(2028, 2, 28).add_days(1).to_iso(), "2028-02-29", "leap year")
	assert_eq(FcDate.new(2026, 12, 31).add_days(1).to_iso(), "2027-01-01")
	assert_eq(FcDate.new(2026, 3, 1).add_days(-1).to_iso(), "2026-02-28")
	assert_eq(FcDate.new(1970, 1, 1).to_day_number(), 0)
	assert_eq(FcDate.new(2000, 3, 1).to_day_number(), 11017)
	assert_eq(FcDate.new(2026, 10, 20).days_until_date(FcDate.new(2027, 4, 15)), 177)
	assert_eq(FcDate.new(2027, 4, 15).days_until_date(FcDate.new(2026, 10, 20)), -177)


func test_date_round_trip_over_many_days() -> void:
	var start := FcDate.new(1999, 12, 25)
	var previous := start
	for i in range(1, 6000):
		var d := start.add_days(i)
		assert_true(d.is_valid(), d.to_iso())
		assert_true(previous.is_before(d), "dates increase")
		assert_eq(FcDate.from_day_number(d.to_day_number()).to_iso(), d.to_iso())
		assert_eq(start.days_until_date(d), i)
		previous = d


func test_schedule_places_every_game_once() -> void:
	var l := _league(2, 2, 16)
	var rules := FcSeasonRules.suggest(l)
	var games := FcScheduleBuilder.build(l, rules, FcRng.new(1))
	var plan := FcMatchupPlanner.plan(l, rules)
	assert_eq(games.size(), plan.total_games())
	var per_team := {}
	var home := {}
	for g in games:
		per_team[g.home_id] = int(per_team.get(g.home_id, 0)) + 1
		per_team[g.away_id] = int(per_team.get(g.away_id, 0)) + 1
		home[g.home_id] = int(home.get(g.home_id, 0)) + 1
		assert_true(g.home_id != g.away_id)
	for t in l.all_team_ids():
		assert_eq(per_team[t], rules.games_for_team(l, t), "team %d plays its full schedule" % t)
		assert_eq(home[t], plan.home_games_of(t), "team %d home games match the plan" % t)


func test_pair_counts_match_the_rules() -> void:
	var l := _league(2, 2, 12)
	var rules := FcSeasonRules.new()
	rules.games_per_division_opponent = 3
	rules.games_per_conference_opponent = 2
	rules.games_per_other_conference_opponent = 1
	var games := FcScheduleBuilder.build(l, rules, FcRng.new(2))
	var counts := {}
	for g in games:
		var key := "%d-%d" % [mini(g.home_id, g.away_id), maxi(g.home_id, g.away_id)]
		counts[key] = int(counts.get(key, 0)) + 1
	for a in l.all_team_ids():
		for b in l.all_team_ids():
			if a < b:
				var expected := rules.games_per_division_opponent if l.division_of_team(a) == l.division_of_team(b) \
					else (rules.games_per_conference_opponent if l.conference_of_team(a) == l.conference_of_team(b) else rules.games_per_other_conference_opponent)
				assert_eq(int(counts.get("%d-%d" % [a, b], 0)), expected, "teams %d and %d" % [a, b])


func test_nobody_plays_twice_in_a_day_and_games_are_sorted() -> void:
	var l := _league(2, 2, 16)
	var games := FcScheduleBuilder.build(l, FcSeasonRules.suggest(l), FcRng.new(3))
	var seen := {}
	var previous_day := 0
	for g in games:
		assert_true(g.day >= previous_day, "sorted by day")
		previous_day = g.day
		for t in [g.home_id, g.away_id]:
			var key := "%d:%d" % [t, g.day]
			assert_true(not seen.has(key), "team %d twice on day %d" % [t, g.day])
			seen[key] = true
		assert_true(g.day >= 0)


func test_season_length_rest_and_streaks() -> void:
	var l := _league(2, 2, 16)
	var rules := FcSeasonRules.suggest(l)
	var games := FcScheduleBuilder.build(l, rules, FcRng.new(4))
	var per_team := rules.games_per_team(l)
	var days := FcScheduleBuilder.length_in_days(games)
	assert_between(days, per_team * 1.7, per_team * 2.6, "about two days per game (%d games over %d days)" % [per_team, days])
	var played_days := {}
	for t in l.all_team_ids():
		played_days[t] = []
	for g in games:
		played_days[g.home_id].append(g.day)
		played_days[g.away_id].append(g.day)
	var back_to_backs := 0
	var total := 0
	for t in played_days:
		for i in range(1, played_days[t].size()):
			total += 1
			if played_days[t][i] - played_days[t][i - 1] == 1:
				back_to_backs += 1
	assert_true(float(back_to_backs) / total < 0.30, "few back-to-backs (%d of %d)" % [back_to_backs, total])
	# longest home or away stand
	var longest := 0
	for t in l.all_team_ids():
		var run := 0
		var last_home := false
		for g in games:
			if not g.involves(t):
				continue
			var is_home := g.home_id == t
			run = run + 1 if (run > 0 and is_home == last_home) else 1
			last_home = is_home
			longest = maxi(longest, run)
	assert_true(longest <= 7, "longest home/away stand %d" % longest)


func test_schedule_is_reproducible() -> void:
	var l := _league(2, 2, 12)
	var rules := FcSeasonRules.suggest(l)
	var a := FcScheduleBuilder.build(l, rules, FcRng.new(7))
	var b := FcScheduleBuilder.build(l, rules, FcRng.new(7))
	var c := FcScheduleBuilder.build(l, rules, FcRng.new(8))
	assert_eq(a.size(), b.size())
	var same := true
	var differs_from_c := false
	for i in a.size():
		if a[i].to_dict() != b[i].to_dict():
			same = false
		if i < c.size() and a[i].to_dict() != c[i].to_dict():
			differs_from_c = true
	assert_true(same, "same seed gives the same calendar")
	assert_true(differs_from_c, "different seed gives a different calendar")


func test_full_size_league_schedules_quickly() -> void:
	var l := _league(2, 3, 30)
	var rules := FcSeasonRules.suggest(l)
	var t0 := Time.get_ticks_msec()
	var games := FcScheduleBuilder.build(l, rules, FcRng.new(9))
	assert_eq(games.size(), 1200)
	assert_true(Time.get_ticks_msec() - t0 < 20000, "building an 80-game, 30-team calendar takes seconds, not minutes")
	assert_between(FcScheduleBuilder.length_in_days(games), 140.0, 220.0, "about five to six months")


func test_scheduled_game_round_trip() -> void:
	var g := FcScheduledGame.new(12, 3, 4)
	assert_true(not g.played and g.winner_id() == 0)
	g.played = true
	g.home_score = 101
	g.away_score = 99
	g.overtimes = 1
	g.series = 5
	var copy := FcScheduledGame.from_dict(JSON.parse_string(JSON.stringify(g.to_dict())))
	assert_eq(copy.to_dict(), g.to_dict())
	assert_eq(copy.winner_id(), 3)
	assert_eq(copy.loser_id(), 4)
	assert_true(copy.involves(4) and not copy.involves(5))
	var unplayed := FcScheduledGame.from_dict(FcScheduledGame.new(1, 2, 3).to_dict())
	assert_true(not unplayed.played)
