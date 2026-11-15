extends FcTestCase
## The game simulator: box-score integrity, reproducibility, plausibility, and that
## ratings, tactics and rotations actually change results.

const SEED := 31415

var data: FcGenerationData
var defs: FcDefinitionSet
var ratings: FcPlayerRatings
var world: FcWorld


func before_each() -> void:
	data = FcGenerationData.load_default()
	defs = FcDefinitionSet.load_default()
	ratings = FcPlayerRatings.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 4
	cfg.conference_count = 1
	cfg.divisions_per_conference = 1
	cfg.free_agent_count = 0
	world = FcWorldGenerator.new(data, defs, cfg).generate(SEED)


func _team(team_id: int) -> FcGameTeam:
	return FcGameTeam.from_world(world, team_id, ratings)


## Sets every attribute of every player on a team to one level.
func _set_team_level(team_id: int, level: int) -> void:
	for pid in world.teams.get_by_id(team_id).roster.player_ids:
		var p: FcPlayer = world.players.get_by_id(pid)
		for key in defs.attributes.keys():
			p.attributes.set_clamped(key, level)


func _simulate_many(home_id: int, away_id: int, games: int, tuning: Dictionary = {}, seed_value: int = 1) -> Array[FcBoxScore]:
	var sim := FcGameSimulator.new(tuning)
	var rng := FcRng.new(seed_value)
	var out: Array[FcBoxScore] = []
	for i in games:
		out.append(sim.simulate(_team(home_id), _team(away_id), rng))
	return out


func _mean(values: Array) -> float:
	var total := 0.0
	for v in values:
		total += float(v)
	return total / maxf(1.0, values.size())


# --- ratings ----------------------------------------------------------------

func test_rating_recipes_are_valid() -> void:
	assert_eq(ratings.validate(defs.attributes), [] as Array[String])
	assert_true(ratings.composites.has("three") and ratings.composites.has("perimeter_d"))


func test_better_attributes_give_better_ratings() -> void:
	var p: FcPlayer = world.players.get_by_id(1)
	var before := ratings.compute(p)
	for key in defs.attributes.keys():
		p.attributes.set_clamped(key, p.attributes.get_value(key) + 10)
	var after := ratings.compute(p)
	for name in ["three", "mid", "finishing", "playmaking", "perimeter_d", "interior_d", "rebound", "overall", "scoring"]:
		assert_true(after[name] > before[name], name)


func test_composite_scale_matches_attribute_scale() -> void:
	var p: FcPlayer = world.players.get_by_id(1)
	for key in defs.attributes.keys():
		p.attributes.set_clamped(key, 60)
	var c := ratings.compute(p)
	for name in ["three", "finishing", "playmaking", "perimeter_d", "rebound", "overall"]:
		assert_between(c[name], 59.9, 60.1, name)


func test_broken_rating_data_is_reported() -> void:
	var bad := FcPlayerRatings.new()
	bad.composites = {"x": {"not_an_attribute": 1.0}, "y": {"speed": -1.0}}
	bad.overall_weights = {"speed": 1.0}
	var errors := bad.validate(defs.attributes)
	assert_true(errors.size() >= 2, str(errors))


# --- box score integrity ---------------------------------------------------------

func test_box_score_adds_up() -> void:
	for box in _simulate_many(1, 2, 25):
		for side in 2:
			var team_points := 0
			var plus_minus := 0
			var seconds := 0
			for p in box.players_of(side):
				team_points += p.points
				plus_minus += p.plus_minus
				seconds += p.seconds
				assert_eq(p.points, 2 * (p.fgm - p.tpm) + 3 * p.tpm + p.ftm, "%s points follow from makes" % p.name)
				assert_true(p.fgm <= p.fga and p.tpm <= p.tpa and p.tpa <= p.fga and p.ftm <= p.fta, "%s makes <= attempts" % p.name)
				assert_true(p.pf <= 6 and p.pf >= 0, "%s fouls %d" % [p.name, p.pf])
				assert_true(p.seconds >= 0 and p.seconds <= 60 * (48 + 5 * box.overtimes) + 1, "%s minutes" % p.name)
				for stat in [p.oreb, p.dreb, p.ast, p.stl, p.blk, p.tov, p.fta, p.fga]:
					assert_true(stat >= 0)
			assert_eq(team_points, box.scores[side], "team score is the sum of player points")
			var game_seconds := 60 * (48 + 5 * box.overtimes)
			assert_between(seconds, game_seconds * 5 - 8, game_seconds * 5 + 8, "five players on court at all times")
			var period_total := 0
			for v in box.period_scores[side]:
				period_total += v
			assert_eq(period_total, box.scores[side], "period scores add up")
			assert_eq(plus_minus, 5 * (box.scores[side] - box.scores[1 - side]), "plus-minus is consistent")
		assert_eq(box.period_scores[0].size(), 4 + box.overtimes)
		assert_true(box.scores[0] != box.scores[1], "no ties")


func test_assists_steals_blocks_and_rebounds_are_consistent() -> void:
	for box in _simulate_many(1, 2, 25):
		for side in 2:
			var t := box.team_totals(side)
			var o := box.team_totals(1 - side)
			assert_true(t["ast"] <= t["fgm"], "assists never exceed made field goals")
			assert_true(t["oreb"] + o["dreb"] <= o["fga"] - o["fgm"] + t["fga"] - t["fgm"] + t["fta"] + o["fta"] + t["oreb"], "rebounds need misses")
			assert_true(t["stl"] <= o["tov"], "steals are turnovers")
			assert_true(t["blk"] <= o["fga"] - o["fgm"], "blocks are missed shots")


func test_same_seed_same_game_different_seed_different_game() -> void:
	var sim := FcGameSimulator.new()
	var a := sim.simulate(_team(1), _team(2), FcRng.new(7))
	var b := sim.simulate(_team(1), _team(2), FcRng.new(7))
	var c := sim.simulate(_team(1), _team(2), FcRng.new(8))
	assert_eq(a.to_dict(), b.to_dict())
	assert_true(a.to_dict() != c.to_dict())


func test_a_team_object_can_play_many_games() -> void:
	var sim := FcGameSimulator.new()
	var rng := FcRng.new(3)
	var home := _team(1)
	var away := _team(2)
	var first := sim.simulate(home, away, rng)
	var first_points := first.scores.duplicate()
	var second := sim.simulate(home, away, rng)
	assert_eq(first.scores, first_points, "an earlier box score is not changed by later games")
	assert_true(second.players.size() == first.players.size())


func test_box_score_round_trip_and_summary() -> void:
	var box := FcGameSimulator.new().simulate(_team(1), _team(2), FcRng.new(5))
	var copy := FcBoxScore.from_dict(JSON.parse_string(JSON.stringify(box.to_dict())))
	assert_eq(copy.to_dict(), box.to_dict())
	assert_true(box.abbreviations[0] in box.summary() and box.abbreviations[1] in box.summary())
	assert_true("PTS" in box.table(0))
	var adv := box.advanced(0)
	assert_between(adv["possessions"], 70.0, 130.0, "possessions")
	assert_between(adv["pace"], 70.0, 130.0, "pace")
	assert_between(adv["efg"], 0.3, 0.75, "eFG")


# --- plausibility over many games ------------------------------------------------------

func test_league_averages_look_like_basketball() -> void:
	var points := []
	var fga := 0.0
	var fgm := 0.0
	var tpa := 0.0
	var tpm := 0.0
	var fta := 0.0
	var ftm := 0.0
	var tov := 0.0
	var pf := 0.0
	var teams_games := 0
	for pair in [[1, 2], [2, 3], [3, 4], [4, 1]]:
		for box in _simulate_many(pair[0], pair[1], 50, {}, pair[0] * 10):
			for side in 2:
				var t := box.team_totals(side)
				points.append(t["points"])
				fga += t["fga"]
				fgm += t["fgm"]
				tpa += t["tpa"]
				tpm += t["tpm"]
				fta += t["fta"]
				ftm += t["ftm"]
				tov += t["tov"]
				pf += t["pf"]
				teams_games += 1
	assert_between(_mean(points), 96.0, 118.0, "points per team")
	assert_between(fgm / fga, 0.43, 0.53, "FG%")
	assert_between(tpm / tpa, 0.32, 0.40, "3P%")
	assert_between(tpa / fga, 0.22, 0.45, "3PA share")
	assert_between(ftm / fta, 0.70, 0.86, "FT%")
	assert_between(fta / teams_games, 16.0, 30.0, "FTA")
	assert_between(tov / teams_games, 10.0, 17.0, "turnovers")
	assert_between(pf / teams_games, 16.0, 26.0, "fouls")


func test_scores_vary_and_overtime_happens() -> void:
	var margins := []
	var overtimes := 0
	for box in _simulate_many(1, 2, 120, {"quarter_seconds": 240}, 9):
		margins.append(absi(box.scores[0] - box.scores[1]))
		if box.overtimes > 0:
			overtimes += 1
			assert_eq(box.period_scores[0].size(), 4 + box.overtimes)
			assert_true(box.scores[0] != box.scores[1])
	assert_true(overtimes > 0, "short games tie often enough to need overtime")
	assert_true(margins.max() > margins.min() + 5, "margins vary")


# --- ratings matter ------------------------------------------------------------------

func test_better_team_wins_far_more_often() -> void:
	_set_team_level(1, 70)
	_set_team_level(2, 45)
	var wins := 0
	var games := 80
	for box in _simulate_many(1, 2, games, {}, 11):
		if box.winner_team_id() == 1:
			wins += 1
	assert_true(wins > games * 0.85, "a 70-rated team beats a 45-rated team (%d of %d)" % [wins, games])


func test_a_small_edge_is_a_small_advantage() -> void:
	_set_team_level(1, 56)
	_set_team_level(2, 50)
	var wins := 0
	var games := 200
	for box in _simulate_many(1, 2, games, {}, 12):
		if box.winner_team_id() == 1:
			wins += 1
	assert_between(float(wins) / games, 0.55, 0.92, "a slightly better team wins more but not always")


func test_shooters_shoot_better_than_non_shooters() -> void:
	_set_team_level(1, 50)
	_set_team_level(2, 50)
	for pid in world.teams.get_by_id(1).roster.player_ids:
		world.players.get_by_id(pid).attributes.set_clamped("three_point", 85)
	var good := 0.0
	var good_attempts := 0.0
	var bad := 0.0
	var bad_attempts := 0.0
	for box in _simulate_many(1, 2, 100, {}, 13):
		var a := box.team_totals(0)
		var b := box.team_totals(1)
		good += a["tpm"]
		good_attempts += a["tpa"]
		bad += b["tpm"]
		bad_attempts += b["tpa"]
	assert_true(good / good_attempts > bad / bad_attempts + 0.03, "85 three-point shooters hit clearly more threes")


func test_defense_matters() -> void:
	_set_team_level(1, 50)
	_set_team_level(2, 50)
	for pid in world.teams.get_by_id(2).roster.player_ids:
		var p: FcPlayer = world.players.get_by_id(pid)
		for key in ["perimeter_defense", "interior_defense", "defensive_awareness", "steals", "blocks"]:
			p.attributes.set_clamped(key, 85)
	var against_good_d := 0.0
	var against_average_d := 0.0
	for box in _simulate_many(1, 2, 60, {}, 14):
		against_good_d += box.scores[0]
		against_average_d += box.scores[1]
	assert_true(against_good_d < against_average_d - 3.0 * 60, "a great defense holds the other team down")


func test_rebounders_rebound() -> void:
	_set_team_level(1, 50)
	_set_team_level(2, 50)
	for pid in world.teams.get_by_id(1).roster.player_ids:
		world.players.get_by_id(pid).attributes.set_clamped("rebounding", 90)
	var mine := 0.0
	var theirs := 0.0
	for box in _simulate_many(1, 2, 50, {}, 15):
		mine += box.team_totals(0)["oreb"] + box.team_totals(0)["dreb"]
		theirs += box.team_totals(1)["oreb"] + box.team_totals(1)["dreb"]
	assert_true(mine > theirs * 1.1, "elite rebounders collect more rebounds")


func test_equal_teams_have_a_home_court_edge() -> void:
	_set_team_level(1, 50)
	_set_team_level(2, 50)
	# Use the same team for both sides (copies) so only luck and home court differ.
	var sim := FcGameSimulator.new()
	var rng := FcRng.new(16)
	var wins := 0
	var margin := 0.0
	var games := 400
	for i in games:
		var box := sim.simulate(_team(1), _team(1), rng)
		if box.scores[0] > box.scores[1]:
			wins += 1
		margin += box.scores[0] - box.scores[1]
	assert_between(float(wins) / games, 0.51, 0.70, "home team win rate")
	assert_between(margin / games, 0.5, 5.5, "average home margin")


# --- coaches and rotations -------------------------------------------------------------

func test_coach_pace_changes_the_game_speed() -> void:
	var fast_total := 0.0
	var slow_total := 0.0
	for style in [["fast", 100.0], ["slow", 0.0]]:
		for tid in [1, 2]:
			var coach := world.staff_in_role(tid, FcStaffRole.Id.HEAD_COACH)
			coach.philosophy.set_clamped("pace_preference", int(style[1]))
		var possessions := 0.0
		for box in _simulate_many(1, 2, 40, {}, 17):
			possessions += box.advanced(0)["possessions"]
		if style[0] == "fast":
			fast_total = possessions
		else:
			slow_total = possessions
	assert_true(fast_total > slow_total + 40 * 3.0, "fast-paced coaches play more possessions")


func test_coach_three_point_emphasis_changes_shot_selection() -> void:
	var high := 0.0
	var low := 0.0
	for emphasis in [100, 0]:
		for tid in [1, 2]:
			world.staff_in_role(tid, FcStaffRole.Id.HEAD_COACH).philosophy.set_clamped("three_point_emphasis", emphasis)
		var rate := 0.0
		for box in _simulate_many(1, 2, 40, {}, 18):
			var t := box.team_totals(0)
			rate += float(t["tpa"]) / t["fga"]
		if emphasis == 100:
			high = rate
		else:
			low = rate
	assert_true(high > low + 40 * 0.03, "three-point-minded coaches take more threes")


func test_rotation_uses_starters_heavily_and_the_bench_some() -> void:
	var starter_minutes := []
	var bench_minutes := []
	var used := []
	for box in _simulate_many(1, 2, 30, {}, 19):
		var list := box.players_of(0)
		var starters := list.filter(func(p): return p.started)
		var bench := list.filter(func(p): return not p.started)
		assert_eq(starters.size(), 5)
		for s in starters:
			starter_minutes.append(s.minutes())
		for b in bench:
			bench_minutes.append(b.minutes())
		used.append(list.filter(func(p): return p.seconds > 0).size())
	assert_between(_mean(starter_minutes), 25.0, 40.0, "average starter minutes")
	assert_true(_mean(bench_minutes) < _mean(starter_minutes), "bench plays less")
	assert_between(_mean(used), 8.0, 14.0, "players used per game")


func test_lineups_have_guards_and_big_men() -> void:
	var sim := FcGameSimulator.new()
	var box := sim.simulate(_team(1), _team(2), FcRng.new(20))
	for side in 2:
		var starters := box.players_of(side).filter(func(p): return p.started)
		var guards := starters.filter(func(p): return p.position == FcPosition.Id.PG or p.position == FcPosition.Id.SG).size()
		var bigs := starters.filter(func(p): return p.position == FcPosition.Id.PF or p.position == FcPosition.Id.C).size()
		assert_true(guards >= 1 and bigs >= 1, "starting five has a guard and a big man")


func test_fatigue_forces_substitutions() -> void:
	var played_five := 0
	# With no energy recovery on the bench and heavy drain, the starters cannot play 48 minutes.
	for box in _simulate_many(1, 2, 20, {"energy_drain_per_second": 0.12}, 21):
		for p in box.players_of(0):
			assert_true(p.seconds < 44 * 60, "%s cannot play the whole game when exhausted" % p.name)
			if p.started and p.seconds > 0:
				played_five += 1
	assert_true(played_five > 0)


func test_blowouts_rest_the_starters() -> void:
	# Natural (generated) teams: uniform-rating teams have no real starters to rest.
	var blowout_minutes := []
	var close_minutes := []
	for box in _simulate_many(1, 2, 300, {}, 22) + _simulate_many(2, 1, 300, {}, 23):
		var side := box.winner_side()
		var starters := box.players_of(side).filter(func(p): return p.started)
		var minutes := _mean(starters.map(func(p): return p.minutes()))
		var margin := absi(box.scores[0] - box.scores[1])
		if margin >= 25:
			blowout_minutes.append(minutes)
		elif margin <= 10:
			close_minutes.append(minutes)
	assert_true(blowout_minutes.size() >= 4 and close_minutes.size() >= 20, "enough of each kind of game (%d blowouts, %d close)" % [blowout_minutes.size(), close_minutes.size()])
	assert_true(_mean(blowout_minutes) < _mean(close_minutes) - 1.0, "starters of a team winning big play fewer minutes (%.1f vs %.1f)" % [_mean(blowout_minutes), _mean(close_minutes)])


# --- eras ---------------------------------------------------------------------------

func test_eras_exist_and_change_the_style_of_play() -> void:
	var keys := FcGameSimulator.era_keys()
	for k in ["early_2010s", "mid_2010s", "late_2010s"]:
		assert_true(keys.has(k), k)
	assert_eq(FcGameSimulator.load_eras()["default"], "mid_2010s")
	var rates := {}
	var pace := {}
	for era in ["early_2010s", "late_2010s"]:
		var sim := FcGameSimulator.for_era(era)
		var rng := FcRng.new(41)
		var tpa := 0.0
		var fga := 0.0
		var possessions := 0.0
		for i in 40:
			var box := sim.simulate(_team(1), _team(2), rng)
			var t := box.team_totals(0)
			tpa += t["tpa"]
			fga += t["fga"]
			possessions += box.advanced(0)["possessions"]
		rates[era] = tpa / fga
		pace[era] = possessions / 40.0
	assert_true(rates["late_2010s"] > rates["early_2010s"] + 0.12, "the late 2010s shoot many more threes")
	assert_true(pace["late_2010s"] > pace["early_2010s"] + 5.0, "and play faster")


func test_era_targets_are_well_formed() -> void:
	for key in FcGameSimulator.era_keys():
		var era: Dictionary = FcGameSimulator.load_eras()["eras"][key]
		assert_true(era.has("label") and era.has("tuning") and era.has("targets"), key)
		for stat in ["points", "pace", "fg_pct", "tp_pct", "tp_rate", "ft_pct", "fta", "reb", "ast", "tov"]:
			var range_pair: Array = era["targets"][stat]
			assert_true(range_pair.size() == 2 and range_pair[0] < range_pair[1], "%s %s" % [key, stat])


func test_league_rules_hold_the_era() -> void:
	var l := FcLeague.make_even(1, "T", 2, 2, 16)
	var r := FcLeagueRules.new(1)
	r.league_id = 1
	r.cap = FcCapRules.from_preset("soft_cap_with_hard_limit", 140000000, FcCapRules.load_presets())
	r.season = FcSeasonRules.suggest(l)
	r.playoffs = FcPlayoffRules.suggest(l)
	assert_eq(r.sim_era, "mid_2010s")
	assert_eq(r.validate(l), [] as Array[String])
	r.sim_era = "1985"
	assert_true(not r.validate(l).is_empty(), "unknown eras are rejected")
	assert_eq(FcLeagueRules.from_dict(JSON.parse_string(JSON.stringify(r.to_dict()))).sim_era, "1985")


# --- tuning and building -----------------------------------------------------------------

func test_tuning_overrides_work() -> void:
	var normal := _simulate_many(1, 2, 20, {}, 23)
	var wild := _simulate_many(1, 2, 20, {"three_base": 0.5, "three_slope": 0.0}, 23)
	assert_true(_mean(wild.map(func(b): return b.team_totals(0)["tpm"])) > _mean(normal.map(func(b): return b.team_totals(0)["tpm"])) + 2.0, "a 50% three-point base is easy to see")
	assert_true(not FcGameSimulator.load_tuning().is_empty())


func test_game_team_built_from_world() -> void:
	var team := _team(1)
	var db: FcTeam = world.teams.get_by_id(1)
	assert_eq(team.players.size(), db.roster.size())
	assert_eq(team.team_id, 1)
	assert_true(team.abbreviation == db.identity.abbreviation and team.name.ends_with(db.identity.nickname))
	for i in range(1, team.players.size()):
		assert_true(team.players[i - 1].overall >= team.players[i].overall, "sorted best first")
	var coach := world.staff_in_role(1, FcStaffRole.Id.HEAD_COACH)
	assert_eq(team.tactics["pace"], float(coach.philosophy.get_value("pace_preference")))


func test_simulating_does_not_change_the_world() -> void:
	var before := world.to_dict()
	_simulate_many(1, 2, 5)
	assert_eq(world.to_dict(), before)


func test_every_team_can_play_every_other() -> void:
	var sim := FcGameSimulator.new()
	var rng := FcRng.new(24)
	for a in world.teams.ids():
		for b in world.teams.ids():
			if a != b:
				var box := sim.simulate(_team(a), _team(b), rng)
				assert_true(box.scores[0] > 50 and box.scores[1] > 50)
