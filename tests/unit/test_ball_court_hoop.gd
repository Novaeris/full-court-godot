extends FcTestCase
## 3D overhaul M3: the ball, the court and the hoop have the real proportions and the ball moves the way a ball does. Everything here is pure maths or
## geometry, so it needs no window; the pictures are in docs/validation/3d_overhaul/m3.


func test_the_ball_has_the_real_size() -> void:
	assert_true(is_equal_approx(FcBallMotion.RADIUS * 2.0 * 12.0, 9.36), "a size 7 ball is about 9.4 inches across (%.2f)" % (FcBallMotion.RADIUS * 24.0))
	var ball := FcBasketball.new()
	assert_true(ball.mesh is SphereMesh and is_equal_approx((ball.mesh as SphereMesh).radius, FcBallMotion.RADIUS), "the mesh matches")
	assert_true(ball.material_override is ShaderMaterial and (ball.material_override as ShaderMaterial).shader != null, "the leather shader loads")
	ball.free()


func test_a_dribble_touches_the_floor_and_the_hand_in_turn() -> void:
	var hand := 3.2
	var lowest := 100.0
	var highest := 0.0
	for k in 101:
		var u := FcBallMotion.dribble_u(k / 100.0 * 0.5)   # half a loop is one bounce
		var y := FcBallMotion.dribble_height(u, hand)
		lowest = minf(lowest, y)
		highest = maxf(highest, y)
	assert_true(absf(lowest - FcBallMotion.RADIUS) < 0.02, "the ball's centre is one radius up at the floor (%.3f)" % lowest)
	assert_true(absf(highest - hand) < 0.02, "and at the hand at the top (%.3f)" % highest)
	assert_true(is_equal_approx(FcBallMotion.dribble_u(0.125), 0.5), "the ball is at the hand when the arm of the dribble is fully extended (phase 0.125)")
	assert_true(is_equal_approx(FcBallMotion.dribble_u(0.625), 0.5), "and again half a loop later: two bounces per loop")
	assert_true(FcBallMotion.dribble_height(0.5, 0.1) >= FcBallMotion.RADIUS * 2.0 - 0.001, "a hand held absurdly low still cannot push the ball into the floor")


func test_a_flight_is_an_arc_from_the_start_to_the_goal() -> void:
	var start := Vector3(10.0, 6.0, 20.0)
	var goal := Vector3(5.25, 10.0, 25.0)
	assert_true(FcBallMotion.flight_position(start, goal, 0.0).is_equal_approx(start), "it starts where it was")
	assert_true(FcBallMotion.flight_position(start, goal, 1.0).is_equal_approx(goal), "and ends at the goal")
	var straight_mid := start.lerp(goal, 0.5)
	var mid := FcBallMotion.flight_position(start, goal, 0.5)
	assert_true(mid.y > straight_mid.y + 0.3, "it is above the straight line half way (%.2f ft)" % (mid.y - straight_mid.y))
	assert_true(FcBallMotion.flight_position(start, goal, 0.5, true).y > mid.y, "a lob (a shot) is higher than a pass")
	for k in 21:
		assert_true(FcBallMotion.flight_position(start, goal, k / 20.0).is_finite())
	assert_true(FcBallMotion.arc_height(500.0, true) <= FcBallMotion.MAX_ARC, "the arc is capped")
	assert_true(FcBallMotion.flight_seconds(start, start, 20.0) >= 0.05, "a zero-length flight still takes a moment")


func test_spin_is_backspin_on_a_shot_and_none_when_held() -> void:
	var direction := Vector3(1.0, 0.0, 0.0)
	var shot := FcBallMotion.spin_axis_rate("shot", direction)
	assert_true(shot.length() > 5.0, "a shot spins")
	assert_true(absf(shot.dot(direction)) < 0.001, "about the axis at right angles to its direction")
	assert_eq(FcBallMotion.spin_axis_rate("held", direction), Vector3.ZERO)
	assert_eq(FcBallMotion.spin_axis_rate("shot", Vector3.ZERO), Vector3.ZERO, "no direction, no spin")


func test_the_hoop_has_the_real_proportions() -> void:
	assert_eq(FcHoopBuilder.RIM_HEIGHT, 10.0, "the rim is 10 feet up")
	assert_true(absf((FcHoopBuilder.RIM_RADIUS - FcHoopBuilder.RIM_TUBE) * 2.0 * 12.0 - 17.28) < 0.2, "the rim's inside diameter is 18 inches (%.2f in)" % ((FcHoopBuilder.RIM_RADIUS - FcHoopBuilder.RIM_TUBE) * 24.0))
	assert_eq(FcHoopBuilder.BOARD_WIDTH, 6.0, "the backboard is 6 feet wide")
	assert_eq(FcHoopBuilder.BOARD_HEIGHT, 3.5, "and 3.5 feet tall")
	assert_eq(FcHoopBuilder.BOARD_BEHIND_RIM, 1.25, "the rim centre is 15 inches from the board")
	assert_true(is_equal_approx(FcCourtLayout.BASKET_FROM_BASELINE, 4.0 + FcHoopBuilder.BOARD_BEHIND_RIM), "the board's face is 4 feet from the baseline")
	var mesh := FcHoopBuilder.net_mesh()
	assert_eq(mesh.get_surface_count(), 1)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), FcHoopBuilder.NET_LEVELS * FcHoopBuilder.NET_STRANDS * 4, "a diamond net: four line ends per node of every level")
	var lowest := 0.0
	var widest_top := 0.0
	for v in verts:
		lowest = minf(lowest, v.y)
		widest_top = maxf(widest_top, Vector2(v.x, v.z).length())
	assert_true(is_equal_approx(lowest, -FcHoopBuilder.NET_DEPTH), "the net hangs 1.5 feet")
	assert_true(widest_top <= FcHoopBuilder.RIM_RADIUS + 0.001, "and never wider than the rim")


func test_a_hoop_builds_facing_either_way_and_the_net_can_swing() -> void:
	var scene := Node3D.new()
	var left := FcHoopBuilder.build(scene, Vector3(5.25, 10.0, 25.0), 1)
	var right := FcHoopBuilder.build(scene, Vector3(88.75, 10.0, 25.0), -1)
	assert_eq((left["root"] as Node3D).rotation_degrees.y, 0.0)
	assert_eq((right["root"] as Node3D).rotation_degrees.y, 180.0, "the far hoop is turned to face the court")
	var net: ShaderMaterial = left["net"]
	FcHoopBuilder.swish(net, 5.0)
	assert_eq(float(net.get_shader_parameter("swish")), 1.0, "the swing is clamped to 0..1")
	FcHoopBuilder.swish(net, -1.0)
	assert_eq(float(net.get_shader_parameter("swish")), 0.0)
	scene.free()


func test_the_floor_and_other_shaders_load_and_the_palette_is_complete() -> void:
	for path in ["court_floor", "basketball", "net", "crowd"]:
		var shader := load("res://src/ui/broadcast3d/%s.gdshader" % path) as Shader
		assert_true(shader != null and shader.code.length() > 100, "%s loads" % path)
	assert_true(FcScenePalette.names().size() >= 15, "the palette has its colours")
	for name in FcScenePalette.names():
		assert_true(FcScenePalette.color(str(name)) != Color.MAGENTA, "%s parses" % name)
	assert_eq(FcScenePalette.color("not_a_colour"), Color.MAGENTA, "a missing name is magenta, easy to spot")


func test_the_court_scene_builds_with_two_hoops_and_swishes_the_right_one() -> void:
	var scene := FcCourtScene.new()
	scene.crowd_count = 200
	scene.build(Color.html("2F6FED"), Color.html("F28A2E"), "HOM")
	assert_eq(scene.rim_position(false), Vector3(FcCourtLayout.BASKET_FROM_BASELINE, 10.0, 25.0))
	assert_eq(scene.rim_position(true), Vector3(FcCourtLayout.COURT_LENGTH - FcCourtLayout.BASKET_FROM_BASELINE, 10.0, 25.0))
	scene.swish(true)
	scene.advance_crowd(0.1)
	scene.free()
