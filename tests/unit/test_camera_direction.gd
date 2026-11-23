extends FcTestCase
## Camera direction v2 (Broadcast pass 2, M3): every preset exists and is used by real events, the director is deterministic, the rig's
## direction rules (minimum shot time, critical interruptions, cooldowns, switch limit, styles, manual override) hold over whole games, the 3D
## pose of every angle respects the 28 ft limit (D-070), and the director style is a remembered preference.

const SEEDS := [3, 12, 77, 404, 9001, 31, 55, 808]
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


func _shot(preset: String, priority: int, critical: bool = false, hold: float = 2.0, focus: Vector2 = Vector2(20, 20)) -> Dictionary:
	return {"preset": preset, "focus": focus, "zoom": 1.5, "hold": hold, "priority": priority, "transition": "cut", "angle": "main", "side": 1, "critical": critical}


# --- the director -------------------------------------------------------------------------------------------------------------

func test_every_shot_is_complete_valid_and_deterministic() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		for i in t.size():
			var shot := FcCameraDirector.shot_for(t, i)
			assert_true(FcCameraDirector.PRESETS.has(shot["preset"]), "known preset %s" % shot["preset"])
			assert_true(FcCameraDirector.ANGLES.has(shot["angle"]))
			assert_true(FcCameraDirector.TRANSITIONS.has(shot["transition"]))
			assert_true(int(shot["side"]) == 1 or int(shot["side"]) == -1)
			assert_true(str(shot["reason"]) != "")
			assert_true(FcCourtLayout.inside_court(shot["focus"]))
			assert_eq(shot, FcCameraDirector.shot_for(t, i), "deterministic")


func test_the_brief_s_camera_behaviours_are_all_used_by_real_events() -> void:
	var presets := {}
	var angles := {}
	var transitions := {}
	for s in SEEDS:
		var t := _timeline(s)
		for i in t.size():
			var shot := FcCameraDirector.shot_for(t, i)
			presets[shot["preset"]] = true
			angles[shot["angle"]] = true
			transitions[shot["transition"]] = true
	for p in [FcCameraDirector.PRESET_WIDE, FcCameraDirector.PRESET_BASELINE, FcCameraDirector.PRESET_OVERHEAD, FcCameraDirector.PRESET_CLOSEUP,
			FcCameraDirector.PRESET_FREE_THROW, FcCameraDirector.PRESET_CELEBRATION, FcCameraDirector.PRESET_STOPPAGE]:
		assert_true(presets.has(p), "the director uses %s" % p)
	for a in FcCameraDirector.ANGLES:
		assert_true(angles.has(a), "the angle %s is used" % a)
	assert_true(transitions.has("cut") and transitions.has("ease") and transitions.has("whip"))


func test_free_throws_celebrations_and_the_buzzer_are_critical_and_nothing_else_is() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		for i in t.size():
			var shot := FcCameraDirector.shot_for(t, i)
			var type := int(t.model.entries[i]["type"])
			var should: bool = type == FcGameEventLog.EV_FREE_THROW or type == FcGameEventLog.EV_GAME_END or shot["preset"] == FcCameraDirector.PRESET_CELEBRATION
			assert_eq(bool(shot["critical"]), should, "event %d (%s)" % [i, shot["reason"]])


func test_a_baseline_shot_stands_behind_the_basket_the_offence_attacks() -> void:
	var t := _timeline(12)
	var checked := 0
	for i in t.size():
		var shot := FcCameraDirector.shot_for(t, i)
		if shot["angle"] != FcCameraDirector.ANGLE_BASELINE:
			continue
		var right: bool = t.model.state_at(i)["attacks_right"]
		assert_eq(int(shot["side"]), 1 if right else -1, "possession decides the side")
		checked += 1
	assert_true(checked > 10)


func test_a_slow_follow_is_never_used_after_a_compressed_step() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		for i in range(1, t.size()):
			if FcCameraDirector._follows_compressed_step(t, i):
				assert_true(FcCameraDirector.shot_for(t, i)["transition"] != FcCameraDirector.TRANSITION_EASE, "event %d follows a rebound, steal or whistle" % i)


func test_replay_shots_cycle_the_angles_and_are_critical() -> void:
	var t := _timeline(12)
	var seen := {}
	for v in 6:
		var shot := FcCameraDirector.replay_shot_for(t, 40, v)
		assert_eq(shot["preset"], FcCameraDirector.PRESET_REPLAY)
		assert_true(bool(shot["critical"]))
		assert_eq(shot["angle"], FcCameraDirector.REPLAY_ANGLES[v % 3])
		seen[shot["angle"]] = true
	assert_eq(seen.size(), 3)
	assert_eq(FcCameraDirector.replay_shot_for(null, 0), {})


# --- the rig's direction rules --------------------------------------------------------------------------------------------------

func test_a_non_critical_shot_cannot_interrupt_before_its_minimum_time_but_a_critical_one_can() -> void:
	var rig := FcCameraRig.new()
	rig.request(_shot("ball", 50, false, 3.0, Vector2(10, 10)))
	rig.advance(0.3)
	rig.request(_shot("basket", 99, false, 1.0, Vector2(70, 40)))
	assert_eq(rig.target()["focus"], Vector2(10, 10), "even a much higher priority waits for the minimum time")
	rig.request(_shot("free_throw", 100, true, 1.0, Vector2(80, 25)))
	assert_eq(rig.target()["focus"], Vector2(80, 25), "a critical shot takes the camera at once")
	assert_eq(rig.switch_log().size(), 2)


func test_a_preset_cannot_be_taken_again_inside_its_cooldown() -> void:
	var rig := FcCameraRig.new()
	rig.request(_shot("celebration", 95, false, 1.0, Vector2(10, 10)))
	rig.advance(1.5)
	rig.request(_shot("ball", 10, false, 0.5, Vector2(40, 20)))
	rig.advance(1.0)
	rig.request(_shot("celebration", 95, false, 1.0, Vector2(70, 30)))
	assert_eq(rig.target()["focus"], Vector2(40, 20), "the celebration is still on cooldown (6 s)")
	rig.advance(5.0)
	rig.request(_shot("celebration", 95, false, 1.0, Vector2(70, 30)))
	assert_eq(rig.target()["focus"], Vector2(70, 30), "and available again after it")


func test_the_switch_limit_stops_a_flurry() -> void:
	var rig := FcCameraRig.new()
	var limit := FcBroadcastStyle.max_switches_per_10s()
	var taken := 0
	for i in 30:
		rig.advance(0.9)   # just over the minimum time, so only the limit can refuse
		var before := rig.switch_log().size()
		rig.request(_shot("p%d" % i, 50, false, 0.1, Vector2(10 + i, 10)))
		taken += rig.switch_log().size() - before
	assert_true(taken <= limit * 3 + 2, "far fewer switches than requests (%d of 30)" % taken)
	for entry in rig.switch_log():
		var inside := 0
		for other in rig.switch_log():
			if float(other["t"]) <= float(entry["t"]) and float(entry["t"]) - float(other["t"]) < 10.0:
				inside += 1
		assert_true(inside <= limit + 1, "no ten seconds hold more than the limit")


func test_styles_scale_holds_and_calm_switches_less_than_energetic() -> void:
	var count := {}
	for style in ["calm", "standard", "energetic"]:
		var rig := FcCameraRig.new()
		rig.style = style
		for i in 60:
			rig.advance(0.4)
			rig.request(_shot("p%d" % i, 50, false, 0.5, Vector2(10 + i, 10)))
		count[style] = rig.switch_log().size()
	assert_true(count["calm"] <= count["standard"] and count["standard"] <= count["energetic"], "calm <= standard <= energetic: %s" % str(count))
	assert_true(count["calm"] < count["energetic"])
	assert_eq(FcBroadcastStyle.camera_style("nonsense"), FcBroadcastStyle.camera_style("standard"), "an unknown style is the standard one")


func test_a_whip_arrives_faster_than_an_ease() -> void:
	var steps := {}
	for move in ["ease", "whip"]:
		var rig := FcCameraRig.new()
		var shot := _shot("x", 50, false, 1.0, Vector2(80, 40))
		shot["transition"] = move
		rig.request(shot)
		var n := 0
		while (rig.camera()["focus"] as Vector2).distance_to(Vector2(80, 40)) > 0.5 and n < 400:
			rig.advance(0.02)
			n += 1
		steps[move] = n
	assert_true(steps["whip"] < steps["ease"], "whip %d steps, ease %d" % [steps["whip"], steps["ease"]])


func test_manual_input_suspends_the_rules_and_the_return_is_never_refused() -> void:
	var rig := FcCameraRig.new()
	rig.resume_seconds = 2.0
	rig.request(_shot("celebration", 95, false, 1.0, Vector2(15, 15)))
	rig.advance(1.0)
	rig.manual_move(Vector2(5, 0))
	var by_hand: Vector2 = rig.target()["focus"]
	rig.request(_shot("celebration", 95, false, 1.0, Vector2(70, 30)))   # on cooldown, and the person has the camera
	assert_eq(rig.target()["focus"], by_hand, "the director cannot take the camera from the person")
	rig.advance(2.5)
	assert_eq(rig.target()["focus"], Vector2(70, 30), "the director's latest shot comes back after the idle time even though its preset is on cooldown")


func test_whole_games_never_switch_faster_than_the_minimum_time_at_any_speed() -> void:
	for s in SEEDS:
		var t := _timeline(s)
		for speed in [1.0, 4.0]:
			var rig := FcCameraRig.new()
			for i in t.size():
				rig.request(FcCameraDirector.shot_for(t, i))
				rig.advance(t.model.dwell(i) / speed)
			var log := rig.switch_log()
			assert_true(log.size() > 20, "the camera does switch (seed %d: %d)" % [s, log.size()])
			for k in range(1, log.size()):
				if not bool(log[k]["critical"]):
					assert_true(float(log[k]["t"]) - float(log[k - 1]["t"]) >= FcBroadcastStyle.min_shot_seconds() - 0.0001, "seed %d speed %s switch %d came too soon" % [s, speed, k])
			for k in log.size():
				var recent := 0
				for j in k + 1:
					if not bool(log[j]["critical"]) and float(log[k]["t"]) - float(log[j]["t"]) < 10.0:
						recent += 1
				assert_true(recent <= FcBroadcastStyle.max_switches_per_10s() + 1, "seed %d: at most %d non-critical switches per ten seconds" % [s, FcBroadcastStyle.max_switches_per_10s()])


func test_a_whole_game_through_the_rig_is_repeatable_with_the_new_rules() -> void:
	var t := _timeline(12)
	var run := func() -> Array:
		var rig := FcCameraRig.new()
		for i in t.size():
			rig.request(FcCameraDirector.shot_for(t, i))
			rig.advance(t.model.dwell(i))
		return rig.switch_log()
	assert_eq(run.call(), run.call())


# --- the 3D pose of each angle ------------------------------------------------------------------------------------------------------

func test_every_angle_keeps_the_3d_camera_at_least_28_feet_away_and_above_the_floor() -> void:
	for angle in FcCameraDirector.ANGLES:
		for side in [-1, 1]:
			for zoom in [1.0, 1.4, 1.8, 3.5]:
				for focus in [Vector2(5, 5), Vector2(47, 25), Vector2(89, 45)]:
					var pose := FcBroadcast3DRules.camera_pose(focus, zoom, angle, side)
					var d: float = (pose["position"] as Vector3).distance_to(pose["target"])
					assert_true(d >= FcBroadcast3DRules.MIN_DISTANCE - 0.001, "%s zoom %s: %s ft" % [angle, zoom, d])
					assert_true((pose["position"] as Vector3).y > 3.0)


func test_the_baseline_camera_is_behind_the_attacked_end_and_overhead_is_high() -> void:
	var right := FcBroadcast3DRules.camera_pose(Vector2(80, 25), 1.0, "baseline", 1)
	var left := FcBroadcast3DRules.camera_pose(Vector2(14, 25), 1.0, "baseline", -1)
	assert_true((right["position"] as Vector3).x > 80.0, "behind the right-hand basket")
	assert_true((left["position"] as Vector3).x < 14.0, "behind the left-hand basket")
	var top := FcBroadcast3DRules.camera_pose(Vector2(47, 25), 1.0, "overhead", 1)
	assert_true((top["position"] as Vector3).y > 60.0)
	assert_eq(FcBroadcast3DRules.camera_pose(Vector2(47, 25), 1.0), FcBroadcast3DRules.camera_pose(Vector2(47, 25), 1.0, "main", 1), "main is the default")


# --- the remembered style ----------------------------------------------------------------------------------------------------------

func test_the_director_style_is_a_remembered_preference() -> void:
	var path := "user://test_preferences_camera_style.cfg"
	DirAccess.remove_absolute(path)
	var p := FcPreferences.new(path)
	assert_eq(p.camera_style, "standard")
	p.camera_style = "calm"
	assert_true(p.save_file())
	assert_eq(FcPreferences.new(path).camera_style, "calm")
	var cfg := ConfigFile.new()
	cfg.set_value("broadcast", "camera_style", "bogus")
	cfg.save(path)
	assert_eq(FcPreferences.new(path).camera_style, "standard", "a bad value falls back")
	DirAccess.remove_absolute(path)
