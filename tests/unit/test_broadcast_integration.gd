extends FcTestCase
## 3D overhaul M5: the broadcast camera shows the upgraded characters (a front three-quarter close shot that never gets nearer than the 28 ft of D-070),
## introductions and celebrations are reflected in the 3D pose rules, and the main camera still keeps its distance.


func test_the_front_close_shot_never_gets_nearer_than_the_minimum_and_looks_at_the_chest() -> void:
	for yaw in [0.0, 45.0, 90.0, 135.0, 180.0, -90.0, 270.0]:
		for zoom in [1.0, 1.4, 1.8, 3.0]:
			for spot in [Vector2(5.0, 5.0), Vector2(47.0, 25.0), Vector2(90.0, 45.0), Vector2(-20.0, 80.0)]:
				var pose := FcBroadcast3DRules.camera_pose_front(spot, zoom, yaw)
				var d: float = (pose["position"] as Vector3).distance_to(pose["target"])
				assert_true(d >= FcBroadcast3DRules.MIN_DISTANCE - 0.001, "yaw %.0f zoom %.1f: %.2f ft from the subject, never under %.0f" % [yaw, zoom, d, FcBroadcast3DRules.MIN_DISTANCE])
				var t: Vector3 = pose["target"]
				assert_true(t.x >= 0.0 and t.x <= FcCourtLayout.COURT_LENGTH and t.z >= 0.0 and t.z <= FcCourtLayout.COURT_WIDTH, "the target is on the court")
				assert_true(t.y > 3.0 and t.y < 6.0, "the camera looks at the chest, not the floor")
				assert_true((pose["position"] as Vector3).is_finite())


func test_the_front_close_shot_is_in_front_of_the_player() -> void:
	for yaw in [0.0, 90.0, 180.0, 270.0, 33.0]:
		var pose := FcBroadcast3DRules.camera_pose_front(Vector2(47.0, 25.0), 1.8, yaw)
		var away: Vector3 = (pose["position"] as Vector3) - (pose["target"] as Vector3)
		var facing := Vector3(sin(deg_to_rad(yaw)), 0.0, cos(deg_to_rad(yaw)))
		var flat := Vector3(away.x, 0.0, away.z).normalized()
		assert_true(flat.dot(facing) > 0.7, "yaw %.0f: the camera is on the side the player faces (%.2f)" % [yaw, flat.dot(facing)])
		assert_true(flat.dot(facing) < 0.99, "and a little off the line, so it is a three-quarter view, not a mug shot")


func test_the_main_camera_keeps_its_distance_and_sees_more_of_the_players() -> void:
	for zoom in [1.0, 1.8, 5.0]:
		var pose := FcBroadcast3DRules.camera_pose(Vector2(47.0, 25.0), zoom)
		assert_true((pose["position"] as Vector3).distance_to(pose["target"]) >= FcBroadcast3DRules.MIN_DISTANCE - 0.001)
	var main: Vector3 = FcBroadcast3DRules.ANGLE_OFFSETS["main"]
	assert_true(main.y / main.z < 0.7, "the main camera is lower than before (a 31 degree look, not 35) so faces are seen")
	assert_true(FcBroadcast3DRules.yaw_towards(Vector3(0, 0, 0), Vector3(0, 0, 10)) == 0.0, "turning to a point in front is no turn")
	assert_true(is_equal_approx(FcBroadcast3DRules.yaw_towards(Vector3(0, 0, 0), Vector3(10, 0, 0)), 90.0))


func test_a_scorer_s_teammates_celebrate_and_the_intro_pose_is_valid() -> void:
	assert_eq(FcBroadcast3DRules.action_for(FcGameEventLog.EV_SHOT_MADE, FcGameEventLog.SHOT_THREE, "celebrant", 3), "celebrate")
	assert_eq(FcBroadcast3DRules.action_for(FcGameEventLog.EV_SHOT_MISSED, FcGameEventLog.SHOT_THREE, "celebrant", 3), "", "nobody celebrates a miss")
	assert_true(FcBroadcastPose.STATES.has("intro"))
	var start := FcBroadcastPose.pose_for("intro", 0.0)
	var end := FcBroadcastPose.pose_for("intro", 1.0)
	assert_true(FcBroadcastPose.largest_joint_change(start, end) < 0.05, "the introduction wave loops")
	var arm: Vector3 = FcBroadcastPose.pose_for("intro", 0.25)["joints"]["r_shoulder"]
	assert_true(arm.x < -1.8, "the right arm is raised to the crowd (%.2f)" % arm.x)


func test_the_rig_reports_its_last_shot_for_the_celebration() -> void:
	var rig := FcCameraRig.new()
	assert_eq(rig.last_shot(), {}, "nothing before the first shot")
	rig.request({"preset": "celebration", "focus": Vector2(40.0, 25.0), "zoom": 2.2, "hold": 2.4, "priority": 95, "transition": "cut", "angle": "closeup", "side": 1, "critical": true, "reason": "celebration"}, true)
	assert_eq(str(rig.last_shot().get("reason", "")), "celebration")
