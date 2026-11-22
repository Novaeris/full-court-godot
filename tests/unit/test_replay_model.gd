extends FcTestCase
## The replay's pure parts (Phase 2C): where shots and players are drawn (FcCourtLayout) and what the picture is at every event
## (FcReplayModel): possession, ends, lineups, points and fouls so far, filters, stepping and pacing.

var world: FcWorld
var ratings: FcPlayerRatings


func before_each() -> void:
	var data := FcGenerationData.load_default()
	var defs := FcDefinitionSet.load_default()
	ratings = FcPlayerRatings.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 4
	cfg.conference_count = 1
	cfg.divisions_per_conference = 1
	cfg.free_agent_count = 0
	world = FcWorldGenerator.new(data, defs, cfg).generate(31415)


func _game(seed_value: int = 12) -> Dictionary:
	var ids := world.teams.ids()
	var sim := FcGameSimulator.new()
	sim.recorder = FcGameEventLog.new()
	var box := sim.simulate(FcGameTeam.from_world(world, ids[0], ratings), FcGameTeam.from_world(world, ids[1], ratings), FcRng.new(seed_value))
	return {"box": box, "log": sim.recorder, "model": FcReplayModel.build(sim.recorder, box)}


# --- court layout -----------------------------------------------------------------------------------------------------------

func test_shots_are_drawn_where_their_kind_says() -> void:
	for right in [true, false]:
		var hoop := FcCourtLayout.basket(right)
		for key in range(0, 300, 7):
			var three := FcCourtLayout.shot_spot(FcGameEventLog.SHOT_THREE, key, right)
			var mid := FcCourtLayout.shot_spot(FcGameEventLog.SHOT_MID, key, right)
			var rim := FcCourtLayout.shot_spot(FcGameEventLog.SHOT_RIM, key, right)
			assert_true(three.distance_to(hoop) >= FcCourtLayout.CORNER_THREE_DISTANCE, "a three is taken from behind the line (%.1f ft)" % three.distance_to(hoop))
			assert_true(mid.distance_to(hoop) >= 9.0 and mid.distance_to(hoop) <= 20.0, "a mid-range shot is between the paint and the line")
			assert_true(rim.distance_to(hoop) <= 5.5, "a rim finish is next to the basket")
			for spot in [three, mid, rim]:
				assert_true(FcCourtLayout.inside_court(spot), "every spot is on the court")


func test_the_picture_is_repeatable_and_varied() -> void:
	var a := FcCourtLayout.shot_spot(FcGameEventLog.SHOT_THREE, 42, true)
	assert_eq(FcCourtLayout.shot_spot(FcGameEventLog.SHOT_THREE, 42, true), a, "the same event always draws the same spot")
	var distinct := {}
	for key in 50:
		distinct[FcCourtLayout.shot_spot(FcGameEventLog.SHOT_MID, key, true)] = true
	assert_true(distinct.size() > 30, "different events are drawn from different spots")


func test_the_ends_switch_after_halftime() -> void:
	assert_true(FcCourtLayout.attacks_right(0, 1) and FcCourtLayout.attacks_right(0, 2), "home attacks the right basket in the first half")
	assert_true(not FcCourtLayout.attacks_right(0, 3) and not FcCourtLayout.attacks_right(0, 4), "and the left in the second")
	assert_true(not FcCourtLayout.attacks_right(1, 1) and FcCourtLayout.attacks_right(1, 3))


func test_the_formation_has_five_and_five_with_defenders_goal_side() -> void:
	for right in [true, false]:
		var f := FcCourtLayout.formation(right)
		var hoop := FcCourtLayout.basket(right)
		assert_eq((f["offense"] as Array).size(), 5)
		assert_eq((f["defense"] as Array).size(), 5)
		for i in 5:
			assert_true(FcCourtLayout.inside_court(f["offense"][i]) and FcCourtLayout.inside_court(f["defense"][i]))
			assert_true((f["defense"][i] as Vector2).distance_to(hoop) < (f["offense"][i] as Vector2).distance_to(hoop), "defender %d is between his man and the basket" % i)


func test_players_take_slots_by_position_and_the_order_never_changes() -> void:
	var positions := {10: 5, 11: 1, 12: 3, 13: 2, 14: 4}
	assert_eq(FcCourtLayout.order_by_position([10, 11, 12, 13, 14], positions), [11, 13, 12, 14, 10], "PG, SG, SF, PF, C")
	assert_eq(FcCourtLayout.order_by_position([14, 13, 12, 11, 10], positions), [11, 13, 12, 14, 10], "the input order does not matter")
	assert_eq(FcCourtLayout.order_by_position([3, 1, 2], {1: 3, 2: 3, 3: 3}), [1, 2, 3], "ties break by id")


# --- replay model ------------------------------------------------------------------------------------------------------------

func test_the_last_state_has_every_players_points_and_fouls() -> void:
	for s in [12, 13, 14]:
		var g := _game(s)
		var model: FcReplayModel = g["model"]
		var box: FcBoxScore = g["box"]
		var final := model.state_at(model.final_index())
		assert_eq(final["home"], box.scores[0])
		assert_eq(final["away"], box.scores[1])
		for p in box.players:
			assert_eq(int(final["points"].get(p.player_id, 0)), p.points, "seed %d %s points so far at the end" % [s, p.name])
			assert_eq(int(final["fouls"].get(p.player_id, 0)), p.pf, "seed %d %s fouls so far at the end" % [s, p.name])
		assert_eq(model.status_at(model.final_index()), "FINAL" if box.overtimes == 0 else "FINAL/OT")


func test_points_and_scores_only_ever_grow() -> void:
	var model: FcReplayModel = _game()["model"]
	var last_home := 0
	var last_away := 0
	var last_total := 0
	for i in model.size():
		var st := model.state_at(i)
		assert_true(st["home"] >= last_home and st["away"] >= last_away, "the score never goes down")
		last_home = st["home"]
		last_away = st["away"]
		var total := 0
		for pid in st["points"]:
			total += int(st["points"][pid])
		assert_eq(total, st["home"] + st["away"], "event %d: players' points add up to the score" % i)
		assert_true(total >= last_total)
		last_total = total


func test_possession_and_ends_follow_the_events() -> void:
	var model: FcReplayModel = _game()["model"]
	for i in model.size():
		var st := model.state_at(i)
		assert_true(st["offense_side"] == 0 or st["offense_side"] == 1, "event %d has an offense" % i)
		var e: Dictionary = st["entry"]
		match e["type"]:
			FcGameEventLog.EV_SHOT_MADE, FcGameEventLog.EV_SHOT_MISSED, FcGameEventLog.EV_TURNOVER, FcGameEventLog.EV_FREE_THROW:
				assert_eq(st["offense_side"], e["side"], "the shooter's team has the ball at event %d" % i)
			FcGameEventLog.EV_FOUL:
				assert_eq(st["offense_side"], 1 - int(e["side"]), "the fouled team has the ball")
		assert_eq(st["attacks_right"], FcCourtLayout.attacks_right(st["offense_side"], st["period"]))


func test_five_on_court_once_the_game_starts_and_fouls_reset_each_period() -> void:
	var model: FcReplayModel = _game()["model"]
	for i in range(model.start_index(), model.size(), 11):
		var st := model.state_at(i)
		assert_eq((st["on_court"][0] as Array).size(), 5)
		assert_eq((st["on_court"][1] as Array).size(), 5)
	var q2 := model.period_start_index(2)
	assert_true(q2 > 0)
	assert_eq(model.state_at(q2)["team_fouls"], [0, 0], "team fouls start again each period")
	assert_true(model.periods().size() >= 4 and model.periods()[0] == 1)


func test_filters_are_nested_and_stepping_walks_through_them() -> void:
	var model: FcReplayModel = _game()["model"]
	var all := model.indices_for(FcReplayModel.FILTER_ALL)
	var key := model.indices_for(FcReplayModel.FILTER_KEY)
	var scoring := model.indices_for(FcReplayModel.FILTER_SCORING)
	assert_true(all.size() > key.size() and key.size() > scoring.size() and scoring.size() > 10, "all %d, key %d, scoring %d" % [all.size(), key.size(), scoring.size()])
	for i in scoring:
		assert_true(key.has(i) and all.has(i), "every scoring event is a key event is an event")
	var i := scoring[0]
	var walked := [i]
	while true:
		var nxt := model.step(i, 1, FcReplayModel.FILTER_SCORING)
		if nxt == i:
			break
		walked.append(nxt)
		i = nxt
	assert_eq(walked, scoring, "stepping forward visits exactly the scoring events")
	assert_eq(model.step(scoring[0], -1, FcReplayModel.FILTER_SCORING), scoring[0], "there is nothing before the first")
	assert_eq(model.step(scoring[3], -1, FcReplayModel.FILTER_SCORING), scoring[2], "stepping back works")


func test_dwell_times_are_positive_and_shots_linger() -> void:
	var model: FcReplayModel = _game()["model"]
	var made := 0.0
	var sub := 0.0
	for i in model.size():
		assert_true(model.dwell(i) > 0.0)
		match model.entries[i]["type"]:
			FcGameEventLog.EV_SHOT_MADE:
				made = model.dwell(i)
			FcGameEventLog.EV_SUBSTITUTION:
				sub = model.dwell(i)
	assert_true(made > sub, "a made shot is shown longer than a substitution")


func test_an_empty_or_missing_log_is_handled() -> void:
	var box := FcBoxScore.new()
	var none := FcReplayModel.build(null, box)
	assert_true(none.is_empty())
	assert_eq(none.state_at(3), {})
	assert_eq(none.status_at(0), "")
	assert_eq(none.start_index(), 0)
	var blank := FcReplayModel.build(FcGameEventLog.new(), box)
	assert_true(blank.is_empty())
	assert_eq(blank.indices_for(FcReplayModel.FILTER_ALL), [] as Array[int])


# --- the adapters (how each mode reaches the replay) ------------------------------------------------------------------------

func test_a_stored_game_without_events_has_no_replay() -> void:
	var g := _game()
	var box_dict: Dictionary = (g["box"] as FcBoxScore).to_dict()
	assert_true(FcReplay.build(box_dict, {}).is_empty(), "no events: no replay")
	assert_true(FcReplay.build(box_dict, {"rows": []}).is_empty(), "an empty log: no replay (older saves)")
	assert_true(FcReplay.build({}, (g["log"] as FcGameEventLog).to_dict()).is_empty(), "no box: no replay")
	var built := FcReplay.build(box_dict, (g["log"] as FcGameEventLog).to_dict())
	assert_true(not built.is_empty() and not (built["model"] as FcReplayModel).is_empty())
	assert_eq((built["model"] as FcReplayModel).state_at(built["model"].final_index())["home"], (g["box"] as FcBoxScore).scores[0])
	assert_true(FcReplay.has_replay((g["log"] as FcGameEventLog).to_dict()))
	assert_true(not FcReplay.has_replay({}))


func test_dynasty_and_career_results_open_a_replay() -> void:
	var env := FcDynastyEnv.make(31)
	var r := env.session.commit(func() -> FcDynastyResult: return FcDynastyPlay.quick_game(env.session.profile, env.catalog, "even"))
	assert_true(r.ok, r.message)
	var dynasty := FcReplay.for_dynasty(r.data)
	assert_true(not dynasty.is_empty(), "a Dynasty game has a replay")
	assert_eq((dynasty["model"] as FcReplayModel).box.scores[0], int(r.data["box"]["scores"][0]))
	FcSafeFile.remove_tree(FcDynastyEnv.DIR)
	var defs := FcDefinitionSet.load_default()
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
	var played: Array = c.advance_days(14)["games"]
	assert_true(played.size() > 0)
	var career := FcReplay.for_career(c, played[0])
	assert_true(not career.is_empty(), "a Career game has a replay")
	assert_eq((career["model"] as FcReplayModel).box.scores[1], int(played[0]["box"]["scores"][1]))
	var built := FcPostGame.for_career(c, played[0])
	assert_true(not (built["replay"] as Dictionary).is_empty(), "the Career post-game offers the replay")
