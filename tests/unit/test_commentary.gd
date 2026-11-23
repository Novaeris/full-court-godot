extends FcTestCase
## Commentary text (B7): built only from recorded facts, repeatable, names the right player, never empty for a scoring play, silent for events
## with nothing to say, and building it changes nothing.

const SEEDS := [3, 12, 77]
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


func test_every_made_shot_is_described_with_its_shooter_and_assister() -> void:
	var checked := 0
	for s in SEEDS:
		var t := _timeline(s)
		var names := {}
		for p in t.model.box.players:
			names[p.player_id] = FcPlayByPlay.short_name(p.name)
		for e in t.model.entries:
			if int(e["type"]) != FcGameEventLog.EV_SHOT_MADE:
				continue
			var line := FcCommentary.line_at(t, int(e["index"]))
			assert_true(line.contains(str(names[int(e["a"])])), "'%s' names the shooter" % line)
			if int(e["b"]) != 0:
				assert_true(line.contains("Assisted by %s" % names[int(e["b"])]), "'%s' names the assister" % line)
			checked += 1
	assert_true(checked > 60, "checked %d made shots" % checked)


func test_commentary_is_repeatable_and_the_game_end_gives_the_final_score() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		var first: Array = []
		for i in t.size():
			first.append(FcCommentary.line_at(t, i))
		for i in t.size():
			assert_eq(FcCommentary.line_at(t, i), first[i])
		var box := t.model.box
		var last := str(first[t.size() - 1])
		assert_true(last.contains("%d" % box.scores[0]) and last.contains("%d" % box.scores[1]), "the closing line has the final score: %s" % last)


func test_quiet_events_and_empty_input_say_nothing() -> void:
	assert_eq(FcCommentary.line_at(null, 0), "")
	var t := _timeline(SEEDS[0])
	var quiet := 0
	for e in t.model.entries:
		if int(e["type"]) in [FcGameEventLog.EV_SUBSTITUTION, FcGameEventLog.EV_PERIOD_START]:
			assert_eq(FcCommentary.line_at(t, int(e["index"])), "")
			quiet += 1
	assert_true(quiet > 0)
