extends FcTestCase
## Highlight selection (B6): repeatable, in game order, at most the asked count, spaced apart, every highlight is a real scoring-or-swing event,
## the last basket of a game is always among them, navigation finds the neighbours, and building them changes nothing.

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


func test_highlights_are_repeatable_ordered_spaced_and_limited() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		var a := FcHighlights.select(t, 6)
		assert_eq(a, FcHighlights.select(t, 6), "same game, same highlights (seed %d)" % s)
		assert_true(a.size() >= 1 and a.size() <= 6, "between 1 and 6 (got %d)" % a.size())
		for k in a.size():
			if k > 0:
				assert_true(int(a[k]["index"]) - int(a[k - 1]["index"]) >= FcHighlights.MIN_GAP, "spaced apart")
			assert_true(int(a[k]["index"]) >= 0 and int(a[k]["index"]) < t.size())
			assert_true(str(a[k]["title"]) != "", "every highlight says what it is")


func test_the_last_basket_of_the_game_is_a_highlight() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		var last := -1
		for e in t.model.entries:
			if int(e["type"]) == FcGameEventLog.EV_SHOT_MADE:
				last = int(e["index"])
		var near := false
		for h in FcHighlights.select(t, 8):
			if absi(int(h["index"]) - last) < FcHighlights.MIN_GAP:
				near = true
		assert_true(near, "the closing basket (event %d) is in or next to a highlight (seed %d)" % [last, s])


func test_neighbours_and_edges() -> void:
	var t := _timeline(SEEDS[0])
	var hs := FcHighlights.select(t, 5)
	assert_true(FcHighlights.neighbor(hs, -1, -1).is_empty(), "nothing before the start")
	assert_eq(FcHighlights.neighbor(hs, -1, 1), hs[0])
	assert_true(FcHighlights.neighbor(hs, t.size(), 1).is_empty(), "nothing after the end")
	assert_eq(FcHighlights.neighbor(hs, int(hs[hs.size() - 1]["index"]) + 1, -1), hs[hs.size() - 1])
	assert_true(FcHighlights.select(null).is_empty())
	assert_true(FcHighlights.select(t, 0).is_empty())


func test_selecting_highlights_changes_no_game_data() -> void:
	var t := _timeline(SEEDS[1])
	var before := JSON.stringify(t.model.box.to_dict())
	FcHighlights.select(t, 8)
	assert_eq(JSON.stringify(t.model.box.to_dict()), before)
