extends FcTestCase
## B1c prototype checks that need no window (master plan 4.12): the procedural animation blends without popping between ANY two states, the
## looping states close their loop, the run does not slide its feet, and the identity data really drives the body (height, weight, build,
## skin, hair, facial hair, team colours, number). The visual judgement and the performance numbers are in docs/validation/.

func _subject(key: String, height: int, weight: int, hair: String = "short", facial: String = "none", jersey: int = 23) -> Dictionary:
	return {"key": key, "name": key, "jersey": jersey, "position": "SF", "appearance": {"skin": "tone_3", "hair": hair, "facial_hair": facial},
		"physical": {"height_cm": height, "weight_kg": weight}, "team": {"primary": "#2F6FED", "secondary": "#F4F7FF", "abbreviation": "HOM", "name": "Home"}}


func test_every_state_is_a_valid_pose_for_every_joint_at_every_phase() -> void:
	for state in FcBroadcastPose.STATES:
		for k in 21:
			var pose := FcBroadcastPose.pose_for(state, k / 20.0)
			for joint in FcBroadcastPose.JOINTS:
				var v: Vector3 = pose["joints"][joint]
				assert_true(v.is_finite() and absf(v.x) < 3.2 and absf(v.y) < 1.0 and absf(v.z) < 1.6, "%s %s at %d: %s is a human range" % [state, joint, k, str(v)])
			assert_true((pose["root"] as Vector3).is_finite())


func test_the_looping_states_close_their_loop_without_a_jump() -> void:
	for state in FcBroadcastPose.STATES:
		var start := FcBroadcastPose.pose_for(state, 0.0)
		var end := FcBroadcastPose.pose_for(state, 1.0)
		assert_true(FcBroadcastPose.largest_joint_change(start, end) < 0.05, "%s: the end of the loop is the start (%.3f rad)" % [state, FcBroadcastPose.largest_joint_change(start, end)])
		var step_worst := 0.0
		for k in 100:
			step_worst = maxf(step_worst, FcBroadcastPose.largest_joint_change(FcBroadcastPose.pose_for(state, k / 100.0), FcBroadcastPose.pose_for(state, (k + 1) / 100.0)))
		assert_true(step_worst < 0.42, "%s: no joint turns more than %.2f rad between hundredths of the loop" % [state, step_worst])


func test_blending_between_any_two_states_never_pops() -> void:
	var worst := 0.0
	var worst_where := ""
	var frames := 12   # a 0.2 s blend at 60 frames per second
	for a in FcBroadcastPose.STATES:
		for b in FcBroadcastPose.STATES:
			if a == b:
				continue
			for start_phase in [0.0, 0.3, 0.6, 0.9]:
				var previous := FcBroadcastPose.pose_for(a, start_phase)
				for f in range(1, frames + 1):
					var weight := f / float(frames)
					var phase_a := fmod(start_phase + f / 60.0 / float(FcBroadcastPose.CYCLE[a]), 1.0)
					var phase_b := fmod(f / 60.0 / float(FcBroadcastPose.CYCLE[b]), 1.0)
					var blended := FcBroadcastPose.blend(FcBroadcastPose.pose_for(a, phase_a), FcBroadcastPose.pose_for(b, phase_b), weight)
					var change := FcBroadcastPose.largest_joint_change(previous, blended)
					if change > worst:
						worst = change
						worst_where = "%s to %s from phase %.1f at frame %d" % [a, b, start_phase, f]
					previous = blended
	assert_true(worst < 0.6, "no joint turns more than %.2f rad in one frame while blending any state into any other (worst: %s)" % [worst, worst_where])
	var half := FcBroadcastPose.blend(FcBroadcastPose.pose_for("idle", 0.0), FcBroadcastPose.pose_for("run", 0.25), 0.5)
	assert_true(FcBroadcastPose.largest_joint_change(half, FcBroadcastPose.pose_for("idle", 0.0)) > 0.0, "a half blend is between the two")
	assert_eq(FcBroadcastPose.blend(FcBroadcastPose.pose_for("idle", 0.0), FcBroadcastPose.pose_for("run", 0.25), 0.0)["joints"], FcBroadcastPose.pose_for("idle", 0.0)["joints"], "weight 0 is the first pose")


func test_the_run_does_not_slide_its_feet_and_stays_under_the_reconstruction_limit() -> void:
	for height in [1.7, 1.9, 2.1, 2.27]:
		var feet: float = height * 3.28084
		var speed: float = FcBroadcastPose.ground_speed("run", feet)
		assert_true(speed > 8.0 and speed < FcReconstructor.PLAYER_SPEED_LIMIT, "a %.1f ft player runs at %.1f ft/s, under %d" % [feet, speed, int(FcReconstructor.PLAYER_SPEED_LIMIT)])
		# the swinging foot moves back at the ground speed while it is planted: the leg's reach per stride equals the distance travelled
		var stride: float = speed * float(FcBroadcastPose.CYCLE["run"])
		assert_true(is_equal_approx(stride, 1.3 * feet), "one loop covers the same 1.3 body heights for every body (feet do not slide for tall or short players)")
	assert_eq(FcBroadcastPose.ground_speed("idle", 6.5), 0.0)
	assert_eq(FcBroadcastPose.ground_speed("shoot", 6.5), 0.0)


func test_the_identity_data_drives_the_body() -> void:
	var tall := FcBroadcastCharacter.new().setup(_subject("tall", 221, 128))
	var short := FcBroadcastCharacter.new().setup(_subject("short", 175, 70))
	assert_true(is_equal_approx(tall.height_feet, 221.0 / 30.48) and is_equal_approx(short.height_feet, 175.0 / 30.48), "height comes from the player's height")
	assert_true(tall.height_feet > short.height_feet)
	var heavy := FcBroadcastCharacter.new().setup(_subject("heavy", 198, 140))
	var slim := FcBroadcastCharacter.new().setup(_subject("slim", 198, 80))
	assert_true(heavy.width_scale > slim.width_scale, "weight widens the body (%.2f vs %.2f)" % [heavy.width_scale, slim.width_scale])
	assert_eq(tall.jersey_number, 23)
	var numbered := FcBroadcastCharacter.new().setup(_subject("n", 198, 95, "short", "none", 99))
	assert_eq(numbered.jersey_number, 99)
	for hair in ["bald", "short", "fade", "afro", "braids", "locs", "curly", "long"]:
		for facial in ["none", "stubble", "goatee", "beard"]:
			var c := FcBroadcastCharacter.new().setup(_subject("hf", 198, 95, hair, facial))
			assert_eq(c.identity["hair"], hair)
			assert_eq(c.identity["facial_hair"], facial)
			assert_true(c.part_count() >= 14, "%s %s: a body of at least 14 parts (%d)" % [hair, facial, c.part_count()])
			c.free()
	var bald := FcBroadcastCharacter.new().setup(_subject("b", 198, 95, "bald"))
	var afro := FcBroadcastCharacter.new().setup(_subject("a", 198, 95, "afro"))
	assert_true(afro.part_count() > bald.part_count(), "an afro adds a part a bald head does not have")
	var same_a := FcBroadcastCharacter.new().setup(_subject("same", 198, 95))
	var same_b := FcBroadcastCharacter.new().setup(_subject("same", 198, 95))
	assert_eq(same_a.identity, same_b.identity, "the same player always looks the same")
	for n in [tall, short, heavy, slim, numbered, bald, afro, same_a, same_b]:
		n.free()


func test_a_character_has_the_whole_joint_hierarchy_and_cross_fades_through_states() -> void:
	var c := FcBroadcastCharacter.new().setup(_subject("rig", 198, 95))
	for joint in FcBroadcastPose.JOINTS:
		assert_true(c.joint_names().has(joint), "%s exists" % joint)
	var previous := c.current_pose()
	var worst := 0.0
	for state in ["run", "shoot", "layup", "defend", "dribble", "idle", "run"]:
		c.set_state(state)
		for f in 30:
			c.advance(1.0 / 60.0)
			var pose := c.current_pose()
			worst = maxf(worst, FcBroadcastPose.largest_joint_change(previous, pose))
			previous = pose
	assert_true(worst < 0.6, "stepping a character through every state at 60 fps never pops (%.2f rad)" % worst)
	assert_eq(c.state, "run")
	c.set_state("not_a_state")
	assert_eq(c.state, "run", "an unknown state is ignored")
	c.free()
