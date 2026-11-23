extends FcTestCase
## Broadcast pass 2, M2: the identity kit is valid, every presentation event says where it came from, the estimated shot clock is
## deterministic, never negative and hidden when it would mislead, the spotlight says only what the box score says, and none of it changes
## the game.

const SEEDS := [3, 12, 77, 404]
var world: FcWorld
var ratings: FcPlayerRatings


func before_each() -> void:
	var data := FcGenerationData.load_default()
	var defs := FcDefinitionSet.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 4
	cfg.conference_count = 1
	cfg.divisions_per_conference = 1
	cfg.free_agent_count = 0
	world = FcWorldGenerator.new(data, defs, cfg).generate(31415)
	ratings = FcPlayerRatings.load_default()


func _timeline(seed_value: int) -> FcBroadcastTimeline:
	var ids := world.teams.ids()
	var sim := FcGameSimulator.new()
	sim.recorder = FcGameEventLog.new()
	var box := sim.simulate(FcGameTeam.from_world(world, ids[0], ratings), FcGameTeam.from_world(world, ids[1], ratings), FcRng.new(seed_value))
	return FcBroadcastTimeline.build(FcReplayModel.build(sim.recorder, box))


# --- identity kit -------------------------------------------------------------------------------------------------------------

func test_the_identity_file_is_valid() -> void:
	assert_eq(FcBroadcastStyle.problems(), [], "no problems in data/ui/broadcast_identity.json")


func test_timings_are_positive_and_reduced_motion_is_never_slower() -> void:
	for name in FcBroadcastStyle.REQUIRED_TIMINGS:
		var normal := FcBroadcastStyle.timing(name, false)
		var reduced := FcBroadcastStyle.timing(name, true)
		assert_true(normal["hold"] >= 0.0 and normal["in"] >= 0.0 and normal["out"] >= 0.0)
		assert_true(reduced["in"] <= normal["in"] and reduced["out"] <= normal["out"], "%s: reduced motion never animates longer" % name)
	assert_true(FcBroadcastStyle.timing("no_such_graphic")["hold"] > 0.0, "an unknown name still gives a usable default")


func test_the_style_names_real_graphic_kinds() -> void:
	var known := [FcBroadcastGraphics.SCORE, FcBroadcastGraphics.MILESTONE, FcBroadcastGraphics.RUN, FcBroadcastGraphics.LEAD_CHANGE, FcBroadcastGraphics.TIED,
		FcBroadcastGraphics.BONUS, FcBroadcastGraphics.FOUL, FcBroadcastGraphics.SUBSTITUTION, FcBroadcastGraphics.INJURY, FcBroadcastGraphics.TURNOVER,
		FcBroadcastGraphics.BLOCK, FcBroadcastGraphics.PERIOD_START, FcBroadcastGraphics.PERIOD_END, FcBroadcastGraphics.FINAL, FcBroadcastGraphics.CLUTCH,
		FcBroadcastGraphics.HALFTIME]
	for k in FcBroadcastStyle.gold_kinds() + FcBroadcastStyle.spotlight_kinds():
		assert_true(known.has(k), "%s is a real graphic kind" % k)


# --- provenance ---------------------------------------------------------------------------------------------------------------

func test_every_presentation_event_has_provenance() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		for i in range(0, t.size(), 3):
			for ev in FcPresentationEvent.for_event(t, i):
				assert_true(ev["source"] in FcPresentationEvent.SOURCES, "known source")
				assert_true(ev["confidence"] in FcPresentationEvent.CONFIDENCES, "known confidence")
				assert_true(int(ev["importance"]) > 0 and not (ev["actions"] as Array).is_empty())
				assert_eq(ev["seconds"], t.seconds_at(i))


func test_only_recorded_or_derived_exact_data_may_be_stated_as_fact() -> void:
	var t := _timeline(12)
	var saw := {}
	for i in t.size():
		for ev in FcPresentationEvent.for_event(t, i):
			saw[ev["source"]] = true
			if ev["source"] == FcPresentationEvent.PRESENTATION:
				assert_true(not FcPresentationEvent.may_state_as_fact(ev), "a presentation label is not a fact")
			else:
				assert_true(FcPresentationEvent.may_state_as_fact(ev))
	assert_true(saw.has(FcPresentationEvent.SIM_RECORDED) and saw.has(FcPresentationEvent.DERIVED_FROM_RECORDED), "both recorded and derived events occur")
	var clock := FcPresentationEvent.for_shot_clock(t, 5, {"visible": true})
	assert_true(not FcPresentationEvent.may_state_as_fact(clock), "the shot clock estimate is never a fact")
	assert_true(not FcPresentationEvent.may_state_as_fact({"source": FcPresentationEvent.RECONSTRUCTED, "confidence": FcPresentationEvent.EXACT}), "reconstructed data is never a fact")


# --- shot clock ---------------------------------------------------------------------------------------------------------------

func test_shot_clock_is_deterministic_bounded_and_hidden_when_misleading() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		var shown := 0
		for i in t.size():
			var a := FcShotClockModel.at(t, i)
			assert_eq(a, FcShotClockModel.at(t, i), "same event, same answer")
			if bool(a["visible"]):
				shown += 1
				assert_true(int(a["seconds"]) >= 0 and int(a["seconds"]) <= FcBroadcastStyle.shot_clock_max(), "between 0 and 24")
				assert_true(float(a["elapsed"]) >= 0.0)
				assert_eq(a["confidence"], FcPresentationEvent.APPROXIMATE)
			var type := int(t.model.entries[i]["type"])
			if type in [FcGameEventLog.EV_FREE_THROW, FcGameEventLog.EV_PERIOD_START, FcGameEventLog.EV_PERIOD_END, FcGameEventLog.EV_GAME_END]:
				assert_true(not bool(a["visible"]), "hidden during free throws and at period boundaries")
			if FcBroadcastTimeline.ends_possession(t.model.entries[i]):
				assert_true(not bool(a["visible"]), "hidden on the event that ends a possession")
		assert_true(shown > 20, "it is shown for a fair part of the game (seed %d: %d)" % [s, shown])


func test_shot_clock_counts_down_within_a_possession() -> void:
	var t := _timeline(12)
	var checked := 0
	for i in range(t.model.start_index() + 1, t.size()):
		var a := FcShotClockModel.at(t, i)
		var b := FcShotClockModel.at(t, i - 1)
		if bool(a["visible"]) and bool(b["visible"]):
			assert_true(float(a["elapsed"]) >= float(b["elapsed"]), "elapsed time never goes backwards inside a possession")
			checked += 1
	assert_true(checked > 20)


func test_shot_clock_handles_empty_and_never_changes_the_game() -> void:
	assert_true(not bool(FcShotClockModel.at(null, 0)["visible"]))
	var t := _timeline(77)
	var before := t.model.entries.duplicate(true)
	for i in t.size():
		FcShotClockModel.at(t, i)
		FcSpotlightModel.at(t, i)
		FcPresentationEvent.for_event(t, i)
	assert_eq(t.model.entries, before, "reading the presentation data changes no recorded event")


# --- spotlight ----------------------------------------------------------------------------------------------------------------

func test_spotlight_says_only_what_the_box_score_says() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		var by_id := {}
		for p in t.model.box.players:
			by_id[p.player_id] = p
		var final := t.size() - 1
		var seen := 0
		for i in t.size():
			var sp := FcSpotlightModel.at(t, i)
			if sp.is_empty():
				continue
			seen += 1
			assert_true(by_id.has(int(sp["player_id"])), "the spotlight player is in the box score")
			assert_eq(sp["name"], FcPlayByPlay.short_name(by_id[int(sp["player_id"])].name))
			var line := t.player_line(i, int(sp["player_id"]))
			assert_eq(int(sp["stats"][0][1]), int(line["points"]))
			assert_true(int(line["points"]) <= by_id[int(sp["player_id"])].points, "never more points than the final box score")
			assert_true(int(sp["number"]) >= 0 and int(sp["number"]) <= 99)
		assert_true(seen > 10, "there are spotlights in a game (seed %d)" % s)
		# at the final event the running line equals the box score for any player
		var any: FcPlayerGameStats = t.model.box.players[0]
		assert_eq(int(t.player_line(final, any.player_id)["points"]), any.points)


func test_spotlight_is_empty_for_quiet_events_and_formats_its_line() -> void:
	var t := _timeline(3)
	var quiet := 0
	for i in t.size():
		if int(t.model.entries[i]["type"]) == FcGameEventLog.EV_SHOT_MISSED:
			assert_true(FcSpotlightModel.at(t, i).is_empty(), "a plain miss has no spotlight")
			quiet += 1
	assert_true(quiet > 0)
	assert_eq(FcSpotlightModel.stat_text({"stats": [["PTS", 12], ["REB", 4]]}), "12 PTS  ·  4 REB")
	assert_eq(FcSpotlightModel.stat_text({}), "")
