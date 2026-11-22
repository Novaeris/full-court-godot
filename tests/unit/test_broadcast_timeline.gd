extends FcTestCase
## Broadcast timeline (master plan B2): the running state around each event (team fouls and bonus, scoring run, lead changes, leaders,
## milestones, clutch time, when an event is shown). Every number is derived from the recorded events, so the strongest checks compare it
## with the BOX SCORE (an independent record kept by the simulator) and with brute-force recounts written here.

const SEEDS := [12, 13, 14, 21]

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


func _game(seed_value: int) -> Dictionary:
	var ids := world.teams.ids()
	var sim := FcGameSimulator.new()
	sim.recorder = FcGameEventLog.new()
	var box := sim.simulate(FcGameTeam.from_world(world, ids[0], ratings), FcGameTeam.from_world(world, ids[1], ratings), FcRng.new(seed_value))
	var model := FcReplayModel.build(sim.recorder, box)
	return {"box": box, "log": sim.recorder, "model": model, "timeline": FcBroadcastTimeline.build(model)}


func test_the_final_state_matches_the_box_score() -> void:
	for s in SEEDS:
		var g := _game(s)
		var box: FcBoxScore = g["box"]
		var t: FcBroadcastTimeline = g["timeline"]
		var last := t.snapshot(t.size() - 1)
		assert_eq(last["home"], box.scores[0], "seed %d home score" % s)
		assert_eq(last["away"], box.scores[1], "seed %d away score" % s)
		assert_eq(last["lead"], box.scores[0] - box.scores[1])
		assert_eq(t.size(), (g["model"] as FcReplayModel).size(), "one snapshot per event")


func test_every_player_line_matches_the_box_score() -> void:
	for s in SEEDS:
		var g := _game(s)
		var box: FcBoxScore = g["box"]
		var t: FcBroadcastTimeline = g["timeline"]
		var last := t.size() - 1
		for p in box.players:
			var line := t.player_line(last, p.player_id)
			for key in ["points", "fgm", "fga", "tpm", "tpa", "ftm", "fta", "oreb", "dreb", "ast", "stl", "blk", "tov", "pf"]:
				assert_eq(int(line[key]), int(p.get(key)), "seed %d %s %s" % [s, p.name, key])
			assert_eq(int(line["reb"]), p.rebounds())


func test_every_team_line_matches_the_box_score_totals() -> void:
	for s in SEEDS:
		var g := _game(s)
		var box: FcBoxScore = g["box"]
		var t: FcBroadcastTimeline = g["timeline"]
		for side in 2:
			var line := t.team_line(t.size() - 1, side)
			var totals := box.team_totals(side)
			for key in ["points", "fgm", "fga", "tpm", "tpa", "ftm", "fta", "oreb", "dreb", "ast", "stl", "blk", "tov", "pf"]:
				assert_eq(int(line[key]), int(totals[key]), "seed %d side %d %s" % [s, side, key])


func test_team_fouls_reset_each_period_and_the_bonus_follows_the_rule() -> void:
	for s in SEEDS:
		var g := _game(s)
		var t: FcBroadcastTimeline = g["timeline"]
		var entries: Array[Dictionary] = (g["model"] as FcReplayModel).entries
		var fouls := [0, 0]
		for i in entries.size():
			var e := entries[i]
			if e["type"] == FcGameEventLog.EV_PERIOD_START:
				fouls = [0, 0]
			elif e["type"] == FcGameEventLog.EV_FOUL:
				fouls[e["side"]] += 1
			var snap := t.snapshot(i)
			assert_eq(snap["team_fouls"], fouls, "seed %d event %d" % [s, i])
			assert_eq(snap["bonus_for"][0], fouls[1] >= t.bonus_fouls, "home shoots in the bonus when AWAY has the fouls")
			assert_eq(snap["bonus_for"][1], fouls[0] >= t.bonus_fouls)
	assert_eq(FcBroadcastTimeline.build((_game(12)["model"] as FcReplayModel)).bonus_fouls, int(FcGameSimulator.load_tuning()["bonus_fouls"]), "the rule is the simulation's own")


func test_the_scoring_run_is_unanswered_points_by_one_side() -> void:
	for s in SEEDS:
		var g := _game(s)
		var t: FcBroadcastTimeline = g["timeline"]
		var entries: Array[Dictionary] = (g["model"] as FcReplayModel).entries
		var side := -1
		var points := 0
		for i in entries.size():
			var e := entries[i]
			if int(e["points"]) > 0:
				if int(e["side"]) == side:
					points += int(e["points"])
				else:
					side = int(e["side"])
					points = int(e["points"])
			var run: Dictionary = t.snapshot(i)["run"]
			assert_eq(int(run["side"]), side, "seed %d event %d side" % [s, i])
			assert_eq(int(run["points"]), points, "seed %d event %d points" % [s, i])


func test_lead_changes_ties_and_largest_leads_are_recounted_exactly() -> void:
	for s in SEEDS:
		var g := _game(s)
		var t: FcBroadcastTimeline = g["timeline"]
		var entries: Array[Dictionary] = (g["model"] as FcReplayModel).entries
		var leader := -1
		var changes := 0
		var ties := 0
		var largest := [0, 0]
		for i in entries.size():
			var e := entries[i]
			if int(e["points"]) > 0:
				var now := 0 if e["home"] > e["away"] else (1 if e["away"] > e["home"] else -1)
				if now == -1:
					ties += 1
				elif leader != -1 and now != leader:
					changes += 1
				if now != -1:
					leader = now
			largest[0] = maxi(largest[0], int(e["home"]) - int(e["away"]))
			largest[1] = maxi(largest[1], int(e["away"]) - int(e["home"]))
			var snap := t.snapshot(i)
			assert_eq(int(snap["lead_changes"]), changes, "seed %d event %d" % [s, i])
			assert_eq(int(snap["ties"]), ties)
			assert_eq(snap["largest_lead"], largest)
		var box: FcBoxScore = g["box"]
		var winner_margin := absi(box.scores[0] - box.scores[1])
		var final_largest: Array = t.snapshot(t.size() - 1)["largest_lead"]
		assert_true(maxi(final_largest[0], final_largest[1]) >= winner_margin, "the biggest lead is at least the final margin")


func test_the_leaders_at_the_end_are_the_box_score_leaders() -> void:
	for s in SEEDS:
		var g := _game(s)
		var box: FcBoxScore = g["box"]
		var t: FcBroadcastTimeline = g["timeline"]
		var leaders: Array = t.snapshot(t.size() - 1)["leaders"]
		for side in 2:
			var best_points := 0
			var best_rebounds := 0
			var best_assists := 0
			for p in box.players_of(side):
				best_points = maxi(best_points, p.points)
				best_rebounds = maxi(best_rebounds, p.rebounds())
				best_assists = maxi(best_assists, p.ast)
			assert_eq(int(leaders[side]["points"]["value"]), best_points, "seed %d side %d points" % [s, side])
			assert_eq(int(leaders[side]["rebounds"]["value"]), best_rebounds, "seed %d side %d rebounds" % [s, side])
			assert_eq(int(leaders[side]["assists"]["value"]), best_assists, "seed %d side %d assists" % [s, side])
			var leader_id := int(leaders[side]["points"]["player_id"])
			var found := false
			for p in box.players_of(side):
				if p.player_id == leader_id:
					assert_eq(p.points, best_points)
					found = true
			assert_true(found or best_points == 0, "the points leader is a player of that side")


func test_a_milestone_is_announced_once_at_the_event_that_reaches_it() -> void:
	for s in SEEDS:
		var g := _game(s)
		var box: FcBoxScore = g["box"]
		var t: FcBroadcastTimeline = g["timeline"]
		var announced := {}
		for i in t.size():
			var m: Dictionary = t.snapshot(i)["milestone"]
			if m.is_empty():
				continue
			var key := "%d:%d" % [int(m["player_id"]), int(m["points"])]
			assert_true(not announced.has(key), "%s is announced once" % key)
			announced[key] = i
			assert_true(t.player_line(i, int(m["player_id"]))["points"] >= int(m["points"]), "the player has reached it at that event")
			assert_true(t.player_line(i - 1, int(m["player_id"]))["points"] < int(m["points"]), "and had not the event before")
		for p in box.players:
			for threshold in FcBroadcastTimeline.MILESTONE_POINTS:
				assert_eq(announced.has("%d:%d" % [p.player_id, threshold]), p.points >= threshold, "seed %d %s %d" % [s, p.name, threshold])


func test_clutch_time_follows_its_definition() -> void:
	var flagged := 0
	for s in SEEDS:
		var g := _game(s)
		var t: FcBroadcastTimeline = g["timeline"]
		var entries: Array[Dictionary] = (g["model"] as FcReplayModel).entries
		for i in entries.size():
			var e := entries[i]
			var expected: bool = int(e["period"]) >= 4 and float(e["clock"]) <= FcBroadcastTimeline.CLUTCH_SECONDS and absi(int(e["home"]) - int(e["away"])) <= FcBroadcastTimeline.CLUTCH_MARGIN and e["type"] != FcGameEventLog.EV_GAME_END
			assert_eq(bool(t.snapshot(i)["clutch"]), expected, "seed %d event %d" % [s, i])
			if expected:
				flagged += 1
	assert_true(flagged > 0, "at least one of the sample games has a clutch stretch, so the rule was exercised")


func test_the_time_an_event_is_shown_runs_forward_and_matches_the_pacing() -> void:
	var g := _game(12)
	var t: FcBroadcastTimeline = g["timeline"]
	var model: FcReplayModel = g["model"]
	var expected := 0.0
	for i in t.size():
		assert_eq(snappedf(t.seconds_at(i), 0.0001), snappedf(expected, 0.0001), "event %d starts after the visible events before it" % i)
		if bool(model.entries[i]["visible"]):
			expected += model.dwell(i)
		if i > 0:
			assert_true(t.seconds_at(i) >= t.seconds_at(i - 1))
		var back := t.index_at_seconds(t.seconds_at(i))
		assert_true(back >= i or t.seconds_at(back) == t.seconds_at(i), "looking a start time up finds that event or a hidden one sharing it")
		assert_true(t.seconds_at(back) <= t.seconds_at(i))
	assert_eq(snappedf(t.total_seconds(), 0.0001), snappedf(expected, 0.0001))
	assert_eq(t.index_at_seconds(-5.0), 0)
	assert_eq(t.index_at_seconds(t.total_seconds() + 100.0), t.size() - 1)


func test_building_it_changes_nothing_and_is_repeatable() -> void:
	for s in [12, 14]:
		var g := _game(s)
		var log: FcGameEventLog = g["log"]
		var box: FcBoxScore = g["box"]
		var rows_before := FcOnlineCrypto.canonical(log.rows)
		var box_before := FcOnlineCrypto.canonical(box.to_dict())
		var model: FcReplayModel = g["model"]
		var a := FcBroadcastTimeline.build(model)
		var b := FcBroadcastTimeline.build(model)
		for i in a.size():
			a.player_line(i, 1)   # reading lines must not change anything either
		assert_eq(FcOnlineCrypto.canonical(log.rows), rows_before, "the event rows are unchanged")
		assert_eq(FcOnlineCrypto.canonical(box.to_dict()), box_before, "the box score is unchanged")
		for i in a.size():
			assert_eq(FcOnlineCrypto.canonical(a.snapshot(i)), FcOnlineCrypto.canonical(b.snapshot(i)), "two builds agree at event %d" % i)


func test_an_empty_or_missing_game_is_an_empty_timeline_not_an_error() -> void:
	var t := FcBroadcastTimeline.build(FcReplayModel.build(null, null))
	assert_true(t.is_empty())
	assert_eq(t.size(), 0)
	assert_eq(t.snapshot(3), {})
	assert_eq(t.seconds_at(2), 0.0)
	assert_eq(t.index_at_seconds(9.0), 0)
	assert_eq(t.clutch_start_index(), -1)
	assert_eq(int(t.player_line(5, 1)["points"]), 0)
	var none := FcBroadcastTimeline.build(null)
	assert_true(none.is_empty())
