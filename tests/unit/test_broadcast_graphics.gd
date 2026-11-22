extends FcTestCase
## Broadcast graphics (master plan B2b option A): what each graphic says at each event. The text and numbers must be the ones the play-by-play
## and the BOX SCORE hold (an independent record), in every mode: Owner and Career games come from the league simulation, Dynasty games from
## the Dynasty match; all three reach the screen through the same replay model, so one set of graphics serves them.

const SEEDS := [12, 13, 14, 21, 22, 23]

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


func _timeline(seed_value: int) -> FcBroadcastTimeline:
	var ids := world.teams.ids()
	var sim := FcGameSimulator.new()
	sim.recorder = FcGameEventLog.new()
	var box := sim.simulate(FcGameTeam.from_world(world, ids[0], ratings), FcGameTeam.from_world(world, ids[1], ratings), FcRng.new(seed_value))
	return FcBroadcastTimeline.build(FcReplayModel.build(sim.recorder, box))


func _kinds(items: Array[Dictionary]) -> Array:
	return items.map(func(i: Dictionary) -> String: return str(i["kind"]))


func test_every_made_shot_has_a_scoring_alert_with_the_right_player_points_and_total() -> void:
	var checked := 0
	for s in SEEDS:
		var t := _timeline(s)
		var box := t.model.box
		for i in t.size():
			var e := t.model.entries[i]
			if e["type"] != FcGameEventLog.EV_SHOT_MADE:
				continue
			var items := FcBroadcastGraphics.items_at(t, i)
			var score := items.filter(func(it: Dictionary) -> bool: return it["kind"] == FcBroadcastGraphics.SCORE)
			assert_eq(score.size(), 1, "seed %d event %d: exactly one scoring alert" % [s, i])
			var item: Dictionary = score[0]
			var shooter: FcPlayerGameStats = null
			for p in box.players:
				if p.player_id == int(e["a"]):
					shooter = p
			assert_true(shooter != null)
			assert_true(str(item["title"]).begins_with(FcPlayByPlay.short_name(shooter.name)), "the shooter's name: %s" % item["title"])
			assert_true(str(item["title"]).ends_with("+%d" % FcGameEventLog.points_of(int(e["x"]))), "the points this shot is worth")
			assert_eq(int(item["value"]), int(t.player_line(i, shooter.player_id)["points"]), "the running total")
			assert_true(int(item["value"]) <= shooter.points, "never more than the player's box-score points")
			assert_eq(int(item["side"]), int(e["side"]))
			if int(e["b"]) != 0:
				assert_true(str(item["detail"]).contains("Assist"), "an assisted basket names the passer")
			checked += 1
	assert_true(checked >= 40, "at least 40 sampled scoring events were checked (%d)" % checked)


func test_a_players_last_scoring_alert_shows_his_box_score_points() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		var last_total := {}
		for i in t.size():
			var e := t.model.entries[i]
			if int(e["points"]) > 0:
				for item in FcBroadcastGraphics.items_at(t, i):
					if item["kind"] == FcBroadcastGraphics.SCORE:
						last_total[int(e["a"])] = int(item["value"])
		for p in t.model.box.players:
			if p.points > 0:
				assert_eq(int(last_total.get(p.player_id, -1)), p.points, "seed %d %s" % [s, p.name])


func test_the_period_and_final_panels_carry_the_box_score() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		var box := t.model.box
		var home := 0
		var away := 0
		var period := 0
		var finals := 0
		for i in t.size():
			var item := FcBroadcastGraphics.top_item_at(t, i)
			if item.is_empty():
				continue
			if item["kind"] == FcBroadcastGraphics.PERIOD_END or item["kind"] == FcBroadcastGraphics.HALFTIME:
				if item["kind"] == FcBroadcastGraphics.HALFTIME:
					assert_eq(period, 1, "halftime is the end of the second period")
				home += int((box.period_scores[0] as Array)[period])
				away += int((box.period_scores[1] as Array)[period])
				period += 1
				assert_eq(str(item["detail"]), "%s %d   %s %d" % [box.abbreviations[0], home, box.abbreviations[1], away], "seed %d end of period %d" % [s, period])
			elif item["kind"] == FcBroadcastGraphics.FINAL:
				finals += 1
				assert_eq(str(item["detail"]), "%s %d   %s %d" % [box.abbreviations[0], box.scores[0], box.abbreviations[1], box.scores[1]])
				assert_eq(str(item["title"]).contains("OT"), box.overtimes > 0, "overtime is labelled")
		assert_eq(finals, 1, "one final panel")
		assert_eq(period, box.period_scores[0].size(), "every period has an end panel")


func test_runs_milestones_lead_changes_and_the_bonus_follow_the_timeline() -> void:
	var runs := 0
	var milestones := 0
	var changes := 0
	var bonuses := 0
	for s in SEEDS:
		var t := _timeline(s)
		var announced := 0
		for i in t.size():
			var snap := t.snapshot(i)
			var items := FcBroadcastGraphics.items_at(t, i)
			for item in items:
				match item["kind"]:
					FcBroadcastGraphics.RUN:
						runs += 1
						assert_true(int(item["value"]) >= FcBroadcastTimeline.RUN_DISPLAY_MIN)
						assert_eq(int(item["side"]), int(snap["run"]["side"]), "a run is announced for the side that is scoring")
						assert_true(str(item["title"]).begins_with("%d-0 run" % int(snap["run"]["points"])))
					FcBroadcastGraphics.MILESTONE:
						milestones += 1
						announced += 1
						assert_eq(int(item["value"]), int(snap["milestone"]["points"]))
					FcBroadcastGraphics.LEAD_CHANGE:
						changes += 1
						assert_true(int(snap["lead_changes"]) > int(t.snapshot(i - 1)["lead_changes"]))
					FcBroadcastGraphics.BONUS:
						bonuses += 1
						assert_true(int((snap["team_fouls"] as Array)[1 - int(item["side"])]) >= t.bonus_fouls, "the other team has the fouls")
		var expected := 0
		for p in t.model.box.players:
			for threshold in FcBroadcastTimeline.MILESTONE_POINTS:
				if p.points >= threshold:
					expected += 1
		assert_eq(announced, expected, "seed %d: every milestone the box score implies is announced once" % s)
		assert_eq(t.snapshot(t.size() - 1)["lead_changes"], _count_kind(t, FcBroadcastGraphics.LEAD_CHANGE), "one lead-change graphic per lead change")
	assert_true(runs > 0 and milestones > 0 and changes > 0 and bonuses > 0, "every kind occurred in the sample (runs %d, milestones %d, lead changes %d, bonuses %d)" % [runs, milestones, changes, bonuses])


func _count_kind(t: FcBroadcastTimeline, kind: String) -> int:
	var n := 0
	for i in t.size():
		for item in FcBroadcastGraphics.items_at(t, i):
			if item["kind"] == kind:
				n += 1
	return n


func test_items_are_ordered_by_priority_and_nothing_is_invented() -> void:
	var seen_kinds := {}
	for s in SEEDS:
		var t := _timeline(s)
		for i in t.size():
			var items := FcBroadcastGraphics.items_at(t, i)
			for k in items.size():
				seen_kinds[items[k]["kind"]] = true
				if k > 0:
					assert_true(int(items[k - 1]["priority"]) >= int(items[k]["priority"]), "most important first")
				assert_true(str(items[k]["title"]) != "")
				assert_true(["score", "milestone", "run", "lead_change", "tied", "bonus", "foul", "substitution", "injury", "turnover", "block", "period_start", "period_end", "halftime", "final", "clutch"].has(items[k]["kind"]))
	for kind in ["score", "foul", "substitution", "period_start", "period_end", "final", "turnover"]:
		assert_true(seen_kinds.has(kind), "%s appeared in the sample" % kind)


func test_the_clutch_graphic_appears_once_at_the_start_of_clutch_time() -> void:
	var total := 0
	for s in SEEDS:
		var t := _timeline(s)
		var count := _count_kind(t, FcBroadcastGraphics.CLUTCH)
		assert_true(count <= 1, "never more than one")
		assert_eq(count == 1, t.clutch_start_index() >= 0)
		total += count
	assert_true(total > 0, "at least one sample game had clutch time")


func test_steals_blocks_and_substitutions_name_the_right_players() -> void:
	var t := _timeline(12)
	var names := {}
	for p in t.model.box.players:
		names[p.player_id] = FcPlayByPlay.short_name(p.name)
	var checked := 0
	for i in t.size():
		var e := t.model.entries[i]
		var item := FcBroadcastGraphics.top_item_at(t, i)
		if item.is_empty():
			continue
		if e["type"] == FcGameEventLog.EV_SUBSTITUTION and item["kind"] == FcBroadcastGraphics.SUBSTITUTION:
			assert_eq(str(item["title"]), "In: %s" % names[int(e["a"])])
			assert_eq(str(item["detail"]), "Out: %s" % names[int(e["b"])])
			checked += 1
		if e["type"] == FcGameEventLog.EV_SHOT_BLOCKED:
			assert_true(str(item["title"]).contains(str(names[int(e["b"])])) or item["kind"] != FcBroadcastGraphics.BLOCK, "the blocker is named")
	assert_true(checked > 0)


func test_a_dynasty_game_gets_the_same_graphics() -> void:
	var env := FcDynastyEnv.make(41)
	var r := env.session.commit(func() -> FcDynastyResult: return FcDynastyPlay.quick_game(env.session.profile, env.catalog, "even"))
	assert_true(r.ok, r.message)
	var entry: Dictionary = env.profile().replays[env.profile().replays.size() - 1]
	var built := FcReplay.build(entry["box"], entry["events"])
	assert_true(not built.is_empty(), "the kept Dynasty replay builds a model")
	var t := FcBroadcastTimeline.build(built["model"])
	var box: FcBoxScore = built["model"].box
	var scoring := 0
	for i in t.size():
		for item in FcBroadcastGraphics.items_at(t, i):
			if item["kind"] == FcBroadcastGraphics.FINAL:
				assert_eq(str(item["detail"]), "%s %d   %s %d" % [box.abbreviations[0], box.scores[0], box.abbreviations[1], box.scores[1]])
			if item["kind"] == FcBroadcastGraphics.SCORE:
				scoring += 1
	assert_true(scoring > 20, "a Dynasty game has many scoring alerts (%d)" % scoring)
	FcSafeFile.remove_tree(FcDynastyEnv.DIR)


func test_a_missing_game_gives_no_graphics() -> void:
	assert_eq(FcBroadcastGraphics.items_at(null, 3), [] as Array[Dictionary])
	assert_eq(FcBroadcastGraphics.top_item_at(FcBroadcastTimeline.build(null), 0), {})


func test_the_team_comparison_card_matches_the_box_score_at_the_end_and_counts_up_through_the_game() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		var box := t.model.box
		var card := FcBroadcastGraphics.team_card_at(t, t.size() - 1)
		for side in 2:
			var totals := box.team_totals(side)
			var rows: Array = card["rows"]
			var col := 1 + side
			assert_eq(str(rows[0][col]), "%d-%d" % [totals["fgm"], totals["fga"]], "seed %d side %d FG" % [s, side])
			assert_eq(str(rows[1][col]), "%d-%d" % [totals["tpm"], totals["tpa"]])
			assert_eq(str(rows[2][col]), "%d-%d" % [totals["ftm"], totals["fta"]])
			assert_eq(str(rows[3][col]), str(int(totals["oreb"]) + int(totals["dreb"])))
			assert_eq(str(rows[4][col]), str(totals["ast"]))
			assert_eq(str(rows[5][col]), str(totals["tov"]))
			assert_eq(str(rows[6][col]), str(totals["pf"]))
		var last_fga := 0
		for i in range(0, t.size(), 25):
			var fga := int(FcBroadcastGraphics.team_card_at(t, i)["home"]["fga"])
			assert_true(fga >= last_fga, "attempts never go down during the game")
			last_fga = fga
	assert_eq(FcBroadcastGraphics.team_card_at(null, 0), {})
