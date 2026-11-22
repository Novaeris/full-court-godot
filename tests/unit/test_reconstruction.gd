extends FcTestCase
## Reconstruction feasibility (master plan B1): the reconstructor turns the recorded events into deterministic, plausible, LABELLED movement,
## and an independent validator checks it. The validator is itself tested by breaking a good reconstruction in each way and requiring a
## complaint, so a pass means something.

const SEEDS := [12, 13, 14, 21, 22, 23, 24, 25]

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


func test_every_sampled_game_reconstructs_into_a_valid_labelled_result() -> void:
	var total := 0
	for s in SEEDS:
		var g := _game(s)
		var t: FcBroadcastTimeline = g["timeline"]
		var result := FcReconstructor.build(t)
		assert_eq(result["reconstructed"], true, "labelled as reconstructed")
		var problems := FcReconstructionValidator.validate(t, result)
		assert_eq(problems.size(), 0, "seed %d: %s" % [s, str(problems.slice(0, 3))])
		assert_true((result["keyframes"] as Array).size() >= t.size() - t.model.start_index(), "at least one keyframe per event from the tip-off")
		total += (result["keyframes"] as Array).size()
	assert_true(total > 3000, "a real sample was checked (%d keyframes)" % total)


func test_the_output_is_identical_every_time_and_nothing_is_changed() -> void:
	for s in [12, 14]:
		var g := _game(s)
		var t: FcBroadcastTimeline = g["timeline"]
		var rows_before := FcOnlineCrypto.canonical((g["log"] as FcGameEventLog).rows)
		var box_before := FcOnlineCrypto.canonical((g["box"] as FcBoxScore).to_dict())
		var a := FcReconstructor.build(t)
		var b := FcReconstructor.build(t)
		assert_eq(_serialise(a), _serialise(b), "two builds are byte-identical")
		var again := FcReconstructor.build(FcBroadcastTimeline.build(g["model"]))
		assert_eq(_serialise(a), _serialise(again), "even from a fresh timeline")
		assert_eq(FcOnlineCrypto.canonical((g["log"] as FcGameEventLog).rows), rows_before, "rows unchanged")
		assert_eq(FcOnlineCrypto.canonical((g["box"] as FcBoxScore).to_dict()), box_before, "box score unchanged")
	assert_true(_serialise(FcReconstructor.build(_game(12)["timeline"])) != _serialise(FcReconstructor.build(_game(13)["timeline"])), "different games reconstruct differently")


func _serialise(result: Dictionary) -> String:
	var lines: Array = []
	for f in result["keyframes"]:
		var ids: Array = (f["players"] as Dictionary).keys()
		ids.sort()
		var parts: Array = []
		for pid in ids:
			parts.append("%d:%.4f,%.4f" % [int(pid), f["players"][pid].x, f["players"][pid].y])
		lines.append("%d|%s|%.4f|%s|%.4f,%.4f,%.4f|%d" % [int(f["event"]), f["kind"], float(f["t"]), ",".join(PackedStringArray(parts)), f["ball"].x, f["ball"].y, f["ball"].z, int(f["holder"])])
	return "%d\n%s" % [int(result["seed"]), "\n".join(PackedStringArray(lines))]


func test_every_ball_interaction_in_the_plan_occurs_and_assists_become_passes_from_the_assister() -> void:
	var seen := {}
	var passes := 0
	for s in SEEDS:
		var g := _game(s)
		var t: FcBroadcastTimeline = g["timeline"]
		var result := FcReconstructor.build(t)
		for f in result["keyframes"]:
			seen[str(f["kind"])] = true
		for e in t.model.entries:
			if e["type"] == FcGameEventLog.EV_SHOT_MADE and int(e["b"]) != 0:
				passes += 1
	for kind in [FcReconstructor.KIND_HOLD, FcReconstructor.KIND_PASS, FcReconstructor.KIND_SHOT_MADE, FcReconstructor.KIND_SHOT_MISSED, FcReconstructor.KIND_SHOT_BLOCKED, FcReconstructor.KIND_FT_SHOT, FcReconstructor.KIND_REBOUND, FcReconstructor.KIND_LOOSE, FcReconstructor.KIND_DEAD]:
		assert_true(seen.has(kind), "%s occurred in the sample" % kind)
	assert_true(passes > 50, "many assisted baskets were reconstructed with a pass (%d)" % passes)


func test_the_time_axis_never_asks_for_more_than_the_speed_limits() -> void:
	for s in [12, 13]:
		var t: FcBroadcastTimeline = _game(s)["timeline"]
		var result := FcReconstructor.build(t)
		var frames: Array = result["keyframes"]
		var longest := 0.0
		for k in range(1, frames.size()):
			var dt := float(frames[k]["t"]) - float(frames[k - 1]["t"])
			assert_true(dt >= FcReconstructor.MIN_DT - 0.0001, "every step takes at least %.1f s" % FcReconstructor.MIN_DT)
			longest = maxf(longest, dt)
		assert_true(longest < 10.0, "no single step is longer than ten seconds (%.1f)" % longest)


# --- the validator catches what it should --------------------------------------------------------------------------------------

func _good() -> Array:
	var t: FcBroadcastTimeline = _game(12)["timeline"]
	return [t, FcReconstructor.build(t)]


func _complains(t: FcBroadcastTimeline, result: Dictionary, fragment: String) -> bool:
	for p in FcReconstructionValidator.validate(t, result):
		if p.contains(fragment):
			return true
	return false


func test_the_validator_catches_each_kind_of_break() -> void:
	var base := _good()
	var t: FcBroadcastTimeline = base[0]
	var good: Dictionary = base[1]
	assert_eq(FcReconstructionValidator.validate(t, good).size(), 0, "the untouched result is valid")
	var broken := func(mutate: Callable) -> Dictionary:
		var copy: Dictionary = good.duplicate(true)
		mutate.call(copy)
		return copy
	assert_true(_complains(t, broken.call(func(r: Dictionary) -> void: r["reconstructed"] = false), "not labelled reconstructed"))
	assert_true(_complains(t, broken.call(func(r: Dictionary) -> void: r["keyframes"][20]["ball"] = Vector3(90, 5, 3)), "jumps at"), "a teleporting ball")
	assert_true(_complains(t, broken.call(func(r: Dictionary) -> void:
		var pid: int = (r["keyframes"][30]["players"] as Dictionary).keys()[0]
		r["keyframes"][30]["players"][pid] = Vector2(1, 1)), "moves at"), "a teleporting player")
	assert_true(_complains(t, broken.call(func(r: Dictionary) -> void: (r["keyframes"][25]["players"] as Dictionary).erase((r["keyframes"][25]["players"] as Dictionary).keys()[0])), "players placed"), "a missing player")
	assert_true(_complains(t, broken.call(func(r: Dictionary) -> void: r["keyframes"][25]["players"][999999] = Vector2(40, 20)), "not on court"), "an extra player")
	assert_true(_complains(t, broken.call(func(r: Dictionary) -> void:
		var ids: Array = (r["keyframes"][40]["players"] as Dictionary).keys()
		r["keyframes"][40]["players"][ids[1]] = r["keyframes"][40]["players"][ids[0]] + Vector2(0.2, 0.0)), "overlap"), "two players in one place")
	assert_true(_complains(t, broken.call(func(r: Dictionary) -> void:
		var ids: Array = (r["keyframes"][50]["players"] as Dictionary).keys()
		r["keyframes"][50]["players"][ids[0]] = Vector2(-5, 20)), "off the court"), "a player off the court")
	assert_true(_complains(t, broken.call(func(r: Dictionary) -> void: r["keyframes"][35]["t"] = float(r["keyframes"][34]["t"])), "time does not move forward"))
	assert_true(_complains(t, broken.call(func(r: Dictionary) -> void:
		var event: int = r["keyframes"][60]["event"]
		r["keyframes"] = (r["keyframes"] as Array).filter(func(f: Dictionary) -> bool: return int(f["event"]) != event)), "no keyframe"), "an event with no keyframe")
	assert_true(_complains(t, broken.call(func(r: Dictionary) -> void:
		for f in r["keyframes"]:
			if f["kind"] == FcReconstructor.KIND_HOLD:
				f["ball"] = Vector3(f["ball"].x + 0.5, f["ball"].y, f["ball"].z)
				return), "not in the holder's hands"), "a ball not in the holder's hands")
	assert_true(_complains(t, broken.call(func(r: Dictionary) -> void:
		for f in r["keyframes"]:
			if f["kind"] == FcReconstructor.KIND_SHOT_MADE:
				f["kind"] = FcReconstructor.KIND_SHOT_MISSED
				return), "does not end in a made shot"), "a made shot recorded as a miss")
	assert_true(_complains(t, broken.call(func(r: Dictionary) -> void:
		for f in r["keyframes"]:
			if f["kind"] == FcReconstructor.KIND_PASS:
				f["kind"] = FcReconstructor.KIND_DEAD
				return), "has no pass"), "an assist without a pass")
	assert_true(_complains(t, broken.call(func(r: Dictionary) -> void:
		for f in r["keyframes"]:
			if f["kind"] == FcReconstructor.KIND_REBOUND:
				f["holder"] = 0
				return), "no holder"), "a rebound nobody holds")
	assert_true(not FcReconstructionValidator.validate(t, {"reconstructed": true, "keyframes": []}).is_empty(), "no keyframes for a real game is a problem")


func test_an_empty_game_reconstructs_to_nothing_and_validates() -> void:
	var empty := FcBroadcastTimeline.build(null)
	var result := FcReconstructor.build(empty)
	assert_eq((result["keyframes"] as Array).size(), 0)
	assert_eq(FcReconstructionValidator.validate(empty, result).size(), 0)
	assert_eq((FcReconstructor.build(null)["keyframes"] as Array).size(), 0)
