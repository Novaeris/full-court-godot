extends FcTestCase
## 3D overhaul M2: the animation library (every state is a valid, loopable pose; arms reach the ball with inverse kinematics; feet stay on the floor
## unless a state is airborne; strides match the ground speed) and the rules that choose an action for a simulation event. The simulation is never
## asked anything: the rules only read an event that already happened.


func _subject(key: String = "anim", height: int = 201, weight: int = 98) -> Dictionary:
	return {"key": key, "name": key, "jersey": 7, "position": "SF", "appearance": {"skin": "tone_3", "hair": "short", "facial_hair": "none"},
		"physical": {"height_cm": height, "weight_kg": weight}, "team": {"primary": "#2F6FED", "secondary": "#F4F7FF", "abbreviation": "HOM", "name": "Home"}}


func test_two_bone_ik_reaches_every_reachable_target_and_never_breaks_when_out_of_reach() -> void:
	var rng := FcRng.new(77)
	for i in 200:
		var start := Vector3(rng.next_float() * 2.0 - 1.0, rng.next_float() * 2.0 - 1.0, rng.next_float() * 2.0 - 1.0)
		var upper := 0.8 + rng.next_float() * 0.6
		var lower := 0.8 + rng.next_float() * 0.6
		var dir := Vector3(rng.next_float() - 0.5, rng.next_float() - 0.5, rng.next_float() - 0.5).normalized()
		var reach := (0.3 + rng.next_float() * 0.7) * (upper + lower) * 0.95
		reach = maxf(reach, absf(upper - lower) + 0.05)
		var target := start + dir * reach
		var result := FcLimbIK.solve(start, upper, lower, target, Vector3(0.3, -0.7, -0.4))
		var end := FcLimbIK.end_point(start, upper, lower, result)
		assert_true(end.distance_to(target) < 0.01, "case %d: the end is %.4f from the target" % [i, end.distance_to(target)])
		assert_true(float(result["bend"]) >= 0.0 and float(result["bend"]) <= PI)
	var far := FcLimbIK.solve(Vector3.ZERO, 1.0, 1.0, Vector3(0.0, -10.0, 0.0), Vector3.BACK)
	assert_true(not bool(far["reached"]), "an out-of-reach target is reported")
	assert_true(absf(float(far["bend"])) < 0.05, "an out-of-reach limb stretches straight")
	var same := FcLimbIK.solve(Vector3.ZERO, 1.0, 1.0, Vector3.ZERO, Vector3.BACK)
	assert_true((same["basis"] as Basis).get_rotation_quaternion().is_finite(), "a zero-distance target gives a finite rotation")


func test_every_state_is_a_valid_loopable_pose_with_the_new_fields() -> void:
	assert_true(FcBroadcastPose.STATES.size() >= 27, "all the requested animations exist")
	for state in ["dribble", "crossover", "hesitation", "drive", "post", "layup", "shoot", "three", "dunk", "defend", "shuffle", "contest", "steal", "block", "rebound", "recover", "walk", "run", "sprint", "stop", "turn", "jump", "land", "fall", "celebrate"]:
		assert_true(FcBroadcastPose.STATES.has(state), "%s exists" % state)
	for state in FcBroadcastPose.STATES:
		assert_true(FcBroadcastPose.CYCLE.has(state), "%s has a cycle length" % state)
		for k in 21:
			var pose := FcBroadcastPose.pose_for(state, k / 20.0)
			assert_true(float(pose["air"]) >= 0.0 and float(pose["air"]) <= 1.0 and float(pose["grip"]) >= 0.0 and float(pose["grip"]) <= 1.0, "%s: air and grip are fractions" % state)
			if not FcBroadcastPose.AIRBORNE.has(state):
				assert_eq(float(pose["air"]), 0.0, "%s is a grounded state" % state)


func test_feet_never_sink_below_the_floor_and_grounded_states_keep_them_on_it() -> void:
	var c := FcBroadcastCharacter.new().setup(_subject())
	var worst_low := 100.0
	var worst_grounded_gap := 0.0
	for state in FcBroadcastPose.STATES:
		for k in 12:
			c.pose_at(state, k / 12.0)
			var fk := c._forward_kinematics()
			var ankle: float = (c.builder.rest_origin("l_foot") as Vector3).y
			var lowest := minf((fk[int(c._bone["l_foot"])] as Transform3D).origin.y, (fk[int(c._bone["r_foot"])] as Transform3D).origin.y) - ankle
			worst_low = minf(worst_low, lowest)
			if not FcBroadcastPose.AIRBORNE.has(state):
				worst_grounded_gap = maxf(worst_grounded_gap, absf(lowest))
	assert_true(worst_low > -0.05, "no foot goes below the floor in any state (%.3f ft)" % worst_low)
	assert_true(worst_grounded_gap < 0.02, "a grounded state keeps the lower foot on the floor (%.3f ft)" % worst_grounded_gap)
	c.free()


func test_airborne_states_really_leave_the_floor_and_the_dunk_reaches_the_rim() -> void:
	var c := FcBroadcastCharacter.new().setup(_subject("dunker", 201, 98))
	for pair in [["jump", 0.5], ["layup", 0.55], ["dunk", 0.5], ["block", 0.35], ["rebound", 0.4]]:
		c.pose_at(pair[0], pair[1])
		var fk := c._forward_kinematics()
		var ankle: float = (c.builder.rest_origin("l_foot") as Vector3).y
		var foot := (fk[int(c._bone["l_foot"])] as Transform3D).origin.y - ankle
		assert_true(foot > 0.8, "%s: the feet are %.2f ft off the floor" % [pair[0], foot])
	c.pose_at("dunk", 0.5)
	var hand: float = (c._forward_kinematics()[int(c._bone["r_hand"])] as Transform3D).origin.y
	assert_true(hand > 10.0, "the hand of a 6 ft 7 in player is above the 10 ft rim at the top of a dunk (%.1f ft)" % hand)
	c.free()


func test_both_hands_are_on_the_ball_whenever_the_grip_says_so() -> void:
	var c := FcBroadcastCharacter.new().setup(_subject("grip"))
	var checked := 0
	for state in FcBroadcastPose.TWO_HAND:
		for k in 41:
			var phase := k / 40.0
			var pose := FcBroadcastPose.pose_for(state, phase)
			if float(pose["grip"]) < 0.98:
				continue
			c.pose_at(state, phase)
			var anchor := c._anchor_model
			var fk := c._forward_kinematics()
			for side in ["l", "r"]:
				var wrist: Vector3 = (fk[int(c._bone[side + "_hand"])] as Transform3D).origin
				var sign := 1.0 if side == "l" else -1.0
				var want := anchor + Vector3(sign * FcBroadcastCharacter.BALL_RADIUS * 1.05, -0.12, -0.02)
				var reach := (fk[int(c._bone[side + "_shoulder"])] as Transform3D).origin.distance_to(want)
				var arm := ((c.builder.rest_origin(side + "_hand") as Vector3) - (c.builder.rest_origin(side + "_shoulder") as Vector3)).length()
				if reach < arm * 0.98:   # reachable: the wrist must be at the ball
					assert_true(wrist.distance_to(want) < 0.06, "%s phase %.2f %s: the wrist is %.3f ft from its place on the ball" % [state, phase, side, wrist.distance_to(want)])
					checked += 1
	assert_true(checked > 20, "enough reachable grips were checked (%d)" % checked)
	c.free()


func test_a_stride_matches_the_ground_speed_so_feet_do_not_slide() -> void:
	for height in [5.9, 6.6, 7.1]:
		for state in ["walk", "run", "sprint", "dribble_run", "drive", "recover"]:
			var speed := FcBroadcastPose.ground_speed(state, height)
			assert_true(speed > 3.0 and speed < FcReconstructor.PLAYER_SPEED_LIMIT, "%s at %.1f ft: %.1f ft/s is a real speed under the reconstruction limit" % [state, height, speed])
		assert_eq(FcBroadcastPose.ground_speed("shoot", height), 0.0)
	# the playback factor makes any travelled speed look right, within a believable range
	var run := FcBroadcastPose.ground_speed("run", 6.6)
	assert_true(is_equal_approx(FcBroadcast3DRules.playback_for("run", run, 6.6), 1.0))
	assert_true(FcBroadcast3DRules.playback_for("run", 100.0, 6.6) <= 1.6 and FcBroadcast3DRules.playback_for("run", 0.1, 6.6) >= 0.55)
	assert_eq(FcBroadcast3DRules.playback_for("idle", 5.0, 6.6), 1.0)


func test_events_choose_actions_the_way_basketball_works() -> void:
	var rim := FcGameEventLog.SHOT_RIM
	assert_eq(FcBroadcast3DRules.action_for(FcGameEventLog.EV_SHOT_MISSED, rim, "actor", 1), "layup")
	assert_eq(FcBroadcast3DRules.action_for(FcGameEventLog.EV_SHOT_MADE, rim, "actor", 4), "dunk", "some made rim shots are dunks, always the same ones for a player")
	assert_eq(FcBroadcast3DRules.action_for(FcGameEventLog.EV_SHOT_MADE, rim, "actor", 4), "dunk")
	assert_eq(FcBroadcast3DRules.action_for(FcGameEventLog.EV_SHOT_MISSED, rim, "actor", 4), "layup", "a miss is never a dunk")
	assert_eq(FcBroadcast3DRules.action_for(FcGameEventLog.EV_SHOT_MADE, FcGameEventLog.SHOT_THREE, "actor", 1), "three")
	assert_eq(FcBroadcast3DRules.action_for(FcGameEventLog.EV_SHOT_MADE, FcGameEventLog.SHOT_MID, "actor", 1), "shoot")
	assert_eq(FcBroadcast3DRules.action_for(FcGameEventLog.EV_SHOT_BLOCKED, rim, "partner", 1), "block")
	assert_eq(FcBroadcast3DRules.action_for(FcGameEventLog.EV_SHOT_MISSED, rim, "contester", 1), "contest")
	assert_eq(FcBroadcast3DRules.action_for(FcGameEventLog.EV_REBOUND, 0, "actor", 1), "rebound")
	assert_eq(FcBroadcast3DRules.action_for(FcGameEventLog.EV_TURNOVER, 0, "partner", 1), "steal")
	assert_eq(FcBroadcast3DRules.action_for(FcGameEventLog.EV_FREE_THROW, 0, "actor", 1), "shoot")
	assert_eq(FcBroadcast3DRules.action_for(FcGameEventLog.EV_SUBSTITUTION, 0, "actor", 1), "", "an event with no action leaves the player to move normally")
	for role in ["ball", "defender", "other"]:
		for speed in [0.0, 3.0, 8.0, 12.0, 20.0]:
			assert_true(FcBroadcastPose.STATES.has(FcBroadcast3DRules.motion_for(role, speed)), "%s at %.0f ft/s gets a real state" % [role, speed])
	assert_eq(FcBroadcast3DRules.motion_for("other", 3.0), "walk")
	assert_eq(FcBroadcast3DRules.motion_for("other", 11.0), "run")
	assert_eq(FcBroadcast3DRules.motion_for("other", 19.0), "sprint")
	assert_eq(FcBroadcast3DRules.motion_for("defender", 6.0), "shuffle")
	assert_true(FcBroadcast3DRules.travel_speed_for(100.0) <= FcReconstructor.PLAYER_SPEED_LIMIT, "never faster than the reconstruction allows")


func test_the_left_arm_is_at_plus_x_and_swings_outward_with_a_positive_roll() -> void:
	var c := FcBroadcastCharacter.new().setup(_subject("sides"))
	c.pose_at("defend", 0.0)
	var fk := c._forward_kinematics()
	var left: Vector3 = (fk[int(c._bone["l_hand"])] as Transform3D).origin
	var right: Vector3 = (fk[int(c._bone["r_hand"])] as Transform3D).origin
	assert_true(left.x > 0.5 and right.x < -0.5, "in the defensive stance the arms are out to the sides (%.2f, %.2f)" % [left.x, right.x])
	assert_true(absf(left.x + right.x) < 0.01, "and the stance is symmetric")
	c.free()
