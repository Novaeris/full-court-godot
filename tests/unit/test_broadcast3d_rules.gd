extends FcTestCase
## B4 pure rules (master plan 4.12, decision D-070): jersey display numbers, the 3D camera pose, facing, body measurements and what a player does at
## an event. None of this needs a window.


func test_jersey_numbers_are_unique_in_range_and_stable_for_a_roster() -> void:
	var ids: Array = []
	for i in 15:
		ids.append(1000 + i * 7)
	var a := FcJerseyNumbers.assign(ids)
	var seen := {}
	for id in ids:
		var n: int = a[id]
		assert_true(n >= FcJerseyNumbers.MIN_NUMBER and n <= FcJerseyNumbers.MAX_NUMBER, "number %d in range" % n)
		assert_true(not seen.has(n), "no two teammates share %d" % n)
		seen[n] = true


func test_jersey_numbers_do_not_depend_on_listing_order() -> void:
	var ids: Array = [5, 17, 99, 120, 4000, 4001, 4002]
	var reversed := ids.duplicate()
	reversed.reverse()
	assert_eq(FcJerseyNumbers.assign(ids), FcJerseyNumbers.assign(reversed))


func test_jersey_numbers_skip_retired_numbers() -> void:
	var ids: Array = [11, 12, 13, 14]
	var plain := FcJerseyNumbers.assign(ids)
	var retired: Array = plain.values()
	var with_retired := FcJerseyNumbers.assign(ids, retired)
	for id in ids:
		assert_true(not retired.has(with_retired[id]), "retired numbers are never issued")


func test_jersey_numbers_end_when_every_number_is_taken() -> void:
	var retired: Array = []
	for n in range(1, 100):
		retired.append(n)
	var out := FcJerseyNumbers.assign([1, 2], retired)
	assert_eq(out[1], 0, "no free number: 0 (display nothing), and the loop ends")


func test_camera_never_closer_than_the_minimum_distance() -> void:
	for zoom in [0.2, 1.0, 1.5, 1.8, 3.0, 50.0]:
		for focus in [Vector2(47, 25), Vector2(5, 3), Vector2(-40, 90), Vector2(200, 200)]:
			var pose := FcBroadcast3DRules.camera_pose(focus, zoom)
			var distance: float = (pose["position"] as Vector3).distance_to(pose["target"] as Vector3)
			assert_true(distance >= FcBroadcast3DRules.MIN_DISTANCE - 0.001, "zoom %s focus %s: distance %.2f" % [str(zoom), str(focus), distance])
			var t: Vector3 = pose["target"]
			assert_true(t.x >= 0.0 and t.x <= FcCourtLayout.COURT_LENGTH and t.z >= 0.0 and t.z <= FcCourtLayout.COURT_WIDTH, "target stays on the court")


func test_camera_stands_on_the_near_sideline_looking_across_the_court() -> void:
	var pose := FcBroadcast3DRules.camera_pose(Vector2(47, 25), 1.0)
	assert_true((pose["position"] as Vector3).z > (pose["target"] as Vector3).z, "camera is on the near side")
	assert_true((pose["position"] as Vector3).y > 10.0, "and elevated")


func test_facing_turns_towards_the_target() -> void:
	assert_between(FcBroadcast3DRules.facing_yaw(Vector2(0, 0), Vector2(0, 10)), 0.0 - 0.001, 0.0 + 0.001)
	assert_between(FcBroadcast3DRules.facing_yaw(Vector2(0, 0), Vector2(10, 0)), 90.0 - 0.001, 90.0 + 0.001)
	assert_between(FcBroadcast3DRules.facing_yaw(Vector2(3, 3), Vector2(3, 3)), 0.0 - 0.001, 0.0 + 0.001)


func test_bodies_follow_position_and_stay_human() -> void:
	var guard := FcBroadcast3DRules.body_for(77, 1)
	var center := FcBroadcast3DRules.body_for(77, 5)
	assert_true(center[0] > guard[0] and center[1] > guard[1], "a centre is taller and heavier than a guard")
	assert_eq(FcBroadcast3DRules.body_for(77, 3), FcBroadcast3DRules.body_for(77, 3), "steady for one player")
	for id in 200:
		for pos in [1, 2, 3, 4, 5]:
			var b := FcBroadcast3DRules.body_for(id, pos)
			assert_true(b[0] >= 150 and b[0] <= 250 and b[1] >= 50 and b[1] <= 200)


func test_states_for_events() -> void:
	assert_eq(FcBroadcast3DRules.state_for(FcGameEventLog.EV_SHOT_MADE, FcGameEventLog.SHOT_RIM, "actor", false), "layup")
	assert_eq(FcBroadcast3DRules.state_for(FcGameEventLog.EV_SHOT_MISSED, FcGameEventLog.SHOT_THREE, "actor", false), "shoot")
	assert_eq(FcBroadcast3DRules.state_for(FcGameEventLog.EV_FREE_THROW, 0, "actor", false), "shoot")
	assert_eq(FcBroadcast3DRules.state_for(0, 0, "ball", false), "dribble")
	assert_eq(FcBroadcast3DRules.state_for(0, 0, "defender", false), "defend")
	assert_eq(FcBroadcast3DRules.state_for(0, 0, "other", false), "idle")
	assert_eq(FcBroadcast3DRules.state_for(0, 0, "defender", true), "run")


func test_travel_never_exceeds_the_reconstruction_speed_limit() -> void:
	for state in FcBroadcastPose.STATES:
		for h in [5.5, 6.5, 7.2]:
			assert_true(FcBroadcast3DRules.travel_speed(state, h) <= FcReconstructor.PLAYER_SPEED_LIMIT + 0.001)
