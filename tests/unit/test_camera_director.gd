extends FcTestCase
## The 2D broadcast camera (master plan B2b option B): the court projection (pure maths), the camera director (which shot at which event) and
## the camera rig (holds, cuts and eases, manual take-over, hybrid return, reset, reduced motion). All pure, so no window is needed.

const SEEDS := [12, 13, 14, 21]

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


func _timeline(seed_value: int) -> FcBroadcastTimeline:
	var ids := world.teams.ids()
	var sim := FcGameSimulator.new()
	sim.recorder = FcGameEventLog.new()
	var box := sim.simulate(FcGameTeam.from_world(world, ids[0], ratings), FcGameTeam.from_world(world, ids[1], ratings), FcRng.new(seed_value))
	return FcBroadcastTimeline.build(FcReplayModel.build(sim.recorder, box))


# --- projection ---------------------------------------------------------------------------------------------------------------

func test_the_court_is_a_trapezoid_wider_at_the_near_sideline() -> void:
	var p := FcCourtProjection.new(Vector2(520, 280))
	var c := p.corners()
	var far_width := c[1].x - c[0].x
	var near_width := c[2].x - c[3].x
	assert_true(near_width > far_width, "near %.1f far %.1f" % [near_width, far_width])
	assert_true(is_equal_approx(far_width / near_width, FcCourtProjection.FAR_SCALE), "the far edge is FAR_SCALE of the near edge")
	assert_true(c[0].y < c[3].y and c[1].y < c[2].y, "the far sideline is higher up the screen")
	assert_true(is_equal_approx(c[0].y, c[1].y) and is_equal_approx(c[2].y, c[3].y), "sidelines are level")
	assert_true(is_equal_approx(near_width, 520.0), "the near edge fits the view at zoom 1")
	assert_true(is_equal_approx((c[0].x + c[1].x) / 2.0, 260.0) and is_equal_approx((c[2].x + c[3].x) / 2.0, 260.0), "centred")
	var flat := FcCourtProjection.new(Vector2(520, 280), true)
	var f := flat.corners()
	assert_true(is_equal_approx(f[1].x - f[0].x, f[2].x - f[3].x), "the flat view is a rectangle")


func test_every_floor_point_comes_back_from_the_screen_for_any_camera() -> void:
	for flat in [false, true]:
		var p := FcCourtProjection.new(Vector2(640, 360), flat)
		for cam in [{}, {"focus": Vector2(20, 10), "zoom": 2.0}, {"focus": Vector2(80, 40), "zoom": 3.0}, {"focus": Vector2(47, 25), "zoom": 1.4}]:
			for x in range(0, 95, 9):
				for y in range(0, 51, 5):
					var back := p.unproject(p.project(float(x), float(y), 0.0, cam), cam)
					assert_true(back.distance_to(Vector2(x, y)) < 0.02, "flat %s camera %s point (%d,%d) came back as %s" % [flat, str(cam), x, y, str(back)])


func test_depth_order_height_zoom_and_focus_behave() -> void:
	var p := FcCourtProjection.new(Vector2(520, 280))
	assert_true(p.project(10, 40).y > p.project(10, 10).y, "nearer is lower on the screen")
	assert_true(p.project(10, 25, 5.0).y < p.project(10, 25, 0.0).y, "height lifts a point up")
	assert_true(is_equal_approx(p.project(10, 25, 5.0).x, p.project(10, 25, 0.0).x), "and only up")
	assert_true(p.project(10, 10, 5.0).y - p.project(10, 10, 0.0).y > p.project(10, 40, 5.0).y - p.project(10, 40, 0.0).y, "the same height lifts less (in pixels) on the near side: lift is scaled by depth")
	var cam := {"focus": Vector2(30, 20), "zoom": 2.0}
	assert_true(p.project(30, 20, 0.0, cam).is_equal_approx(Vector2(260, 140)), "the focus is at the centre of the view")
	var a := p.project(40, 20, 0.0)
	var b := p.project(50, 20, 0.0)
	var a2 := p.project(40, 20, 0.0, {"focus": Vector2(47, 25), "zoom": 2.0})
	var b2 := p.project(50, 20, 0.0, {"focus": Vector2(47, 25), "zoom": 2.0})
	assert_true(is_equal_approx((b2 - a2).length(), 2.0 * (b - a).length()), "zoom 2 doubles distances")
	assert_true(is_equal_approx(p.scale_at(0.0), FcCourtProjection.FAR_SCALE) and is_equal_approx(p.scale_at(50.0), 1.0))
	assert_eq(FcCourtProjection.new(Vector2(520, 280), true).scale_at(0.0), 1.0, "no foreshortening in the flat view")
	var clamped := FcCourtProjection.clamp_camera({"focus": Vector2(500, -9), "zoom": 99.0})
	assert_eq(clamped, {"focus": Vector2(94, 0), "zoom": FcCourtProjection.MAX_ZOOM})
	assert_eq(FcCourtProjection.clamp_camera({"zoom": 0.1})["zoom"], FcCourtProjection.MIN_ZOOM)


func test_the_markings_stay_on_the_projected_floor() -> void:
	var p := FcCourtProjection.new(Vector2(520, 280))
	var c := p.corners()
	for right in [true, false]:
		var hoop := FcCourtLayout.basket(right)
		for k in 40:
			var angle := TAU * k / 40.0
			var on_arc := hoop + Vector2.from_angle(angle) * FcCourtLayout.THREE_POINT_DISTANCE
			if FcCourtLayout.inside_court(on_arc):
				var s := p.project(on_arc.x, on_arc.y)
				assert_true(Geometry2D.is_point_in_polygon(s, c) or s.y >= c[0].y - 0.5, "an arc point is inside the floor polygon")
		var hoop_screen := p.project(hoop.x, hoop.y)
		assert_true(Geometry2D.is_point_in_polygon(hoop_screen, c), "the basket is on the floor")


# --- the director -------------------------------------------------------------------------------------------------------------

func test_every_event_gets_a_valid_shot_and_the_priorities_are_in_order() -> void:
	var seen := {}
	for s in SEEDS:
		var t := _timeline(s)
		for i in t.size():
			var shot := FcCameraDirector.shot_for(t, i)
			var focus: Vector2 = shot["focus"]
			assert_true(FcCourtLayout.inside_court(focus), "the focus is on the court (event %d: %s)" % [i, str(focus)])
			assert_true(float(shot["zoom"]) >= FcCourtProjection.MIN_ZOOM and float(shot["zoom"]) <= FcCourtProjection.MAX_ZOOM)
			assert_true(float(shot["hold"]) > 0.0)
			assert_true([FcCameraDirector.TRANSITION_CUT, FcCameraDirector.TRANSITION_EASE].has(shot["transition"]))
			assert_eq(shot, FcCameraDirector.shot_for(t, i), "deterministic")
			seen[int(t.model.entries[i]["type"])] = int(shot["priority"])
	assert_true(seen[FcGameEventLog.EV_FREE_THROW] > seen[FcGameEventLog.EV_SHOT_MADE], "free throws outrank a made shot")
	assert_true(seen[FcGameEventLog.EV_SHOT_MADE] > seen[FcGameEventLog.EV_SHOT_BLOCKED], "a made shot outranks a block")
	assert_true(seen[FcGameEventLog.EV_SHOT_BLOCKED] > seen[FcGameEventLog.EV_FOUL])
	assert_true(seen[FcGameEventLog.EV_FOUL] > seen[FcGameEventLog.EV_REBOUND])
	assert_true(seen[FcGameEventLog.EV_REBOUND] > seen[FcGameEventLog.EV_SHOT_MISSED])
	assert_true(seen[FcGameEventLog.EV_SHOT_MISSED] > seen[FcGameEventLog.EV_SUBSTITUTION])
	assert_true(seen[FcGameEventLog.EV_SUBSTITUTION] > seen[FcGameEventLog.EV_PERIOD_START] - 1, "substitutions rank above the quiet rest")


func test_a_shot_frames_the_basket_the_offense_attacks() -> void:
	var t := _timeline(12)
	for i in t.size():
		var e := t.model.entries[i]
		if e["type"] != FcGameEventLog.EV_SHOT_MADE and e["type"] != FcGameEventLog.EV_FREE_THROW:
			continue
		var state := t.model.state_at(i)
		var hoop := FcCourtLayout.basket(state["attacks_right"])
		var focus: Vector2 = FcCameraDirector.shot_for(t, i)["focus"]
		var other := FcCourtLayout.basket(not state["attacks_right"])
		assert_true(focus.distance_to(hoop) < focus.distance_to(other), "event %d looks at the attacked end" % i)
	assert_eq(FcCameraDirector.shot_for(null, 0), {})
	assert_eq(FcCameraDirector.shot_for(FcBroadcastTimeline.build(null), 0), {})


# --- the rig ------------------------------------------------------------------------------------------------------------------

func _shot(priority: int, focus: Vector2 = Vector2(20, 20), zoom: float = 2.0, hold: float = 2.0, transition: String = "ease") -> Dictionary:
	return {"preset": "test", "focus": focus, "zoom": zoom, "hold": hold, "priority": priority, "transition": transition}


func _settle(rig: FcCameraRig, seconds: float = 3.0) -> void:
	for i in int(seconds / 0.05):
		rig.advance(0.05)


func test_a_cut_jumps_an_ease_glides_and_never_overshoots() -> void:
	var rig := FcCameraRig.new()
	rig.request(_shot(90, Vector2(20, 10), 2.0, 2.0, "cut"))
	assert_eq(rig.camera(), {"focus": Vector2(20, 10), "zoom": 2.0}, "a cut is at once")
	var glide := FcCameraRig.new()
	glide.request(_shot(50, Vector2(70, 30), 2.0, 2.0, "ease"))
	assert_eq(glide.camera(), FcCourtProjection.default_camera(), "an ease has not moved yet")
	for i in 80:
		glide.advance(0.05)
	assert_true((glide.camera()["focus"] as Vector2).distance_to(Vector2(70, 30)) < 0.05, "it arrives")
	assert_true(absf(float(glide.camera()["zoom"]) - 2.0) < 0.01)
	var prev := 1e9
	var g2 := FcCameraRig.new()
	g2.request(_shot(50, Vector2(70, 30), 2.0, 2.0, "ease"))
	for i in 60:
		g2.advance(0.05)
		var d2 := (g2.camera()["focus"] as Vector2).distance_to(Vector2(70, 30))
		assert_true(d2 <= prev + 0.0001, "monotonic approach at step %d" % i)
		prev = d2


func test_a_shot_is_held_against_equal_or_lower_priority_but_not_higher() -> void:
	var rig := FcCameraRig.new()
	rig.request(_shot(80, Vector2(20, 10), 2.0, 2.0, "cut"))
	rig.advance(0.5)
	rig.request(_shot(60, Vector2(70, 40), 1.5, 1.0, "cut"))
	assert_eq(rig.target()["focus"], Vector2(20, 10), "lower priority waits")
	rig.request(_shot(80, Vector2(70, 40), 1.5, 1.0, "cut"))
	assert_eq(rig.target()["focus"], Vector2(20, 10), "equal priority waits too")
	rig.request(_shot(95, Vector2(60, 25), 2.5, 1.0, "cut"))
	assert_eq(rig.target()["focus"], Vector2(60, 25), "higher priority takes the camera at once")
	rig.advance(1.5)
	rig.request(_shot(10, Vector2(47, 25), 1.0, 0.5, "cut"))
	assert_eq(rig.target()["focus"], Vector2(47, 25), "after the hold anything can")


func test_hybrid_the_person_takes_over_and_the_director_comes_back() -> void:
	var rig := FcCameraRig.new()
	rig.resume_seconds = 4.0
	rig.request(_shot(50, Vector2(20, 20), 2.0, 1.0, "cut"))
	rig.manual_move(Vector2(10, 5), 1.0)
	assert_true(rig.is_overridden())
	rig.request(_shot(99, Vector2(80, 10), 2.5, 1.0, "cut"))
	_settle(rig, 1.0)
	assert_eq(rig.target()["focus"], Vector2(30, 25), "the director's request did not move the person's camera")
	_settle(rig, 3.5)
	assert_true(not rig.is_overridden(), "after the idle time the person is done")
	assert_eq(rig.target()["focus"], Vector2(80, 10), "and the camera returns to the director's LATEST shot")
	rig.manual_move(Vector2(-5, 0), 1.0)
	_settle(rig, 1.0)
	rig.manual_move(Vector2(-5, 0), 1.0)
	_settle(rig, 3.0)
	assert_true(rig.is_overridden(), "each move restarts the wait")
	rig.reset()
	assert_true(not rig.is_overridden(), "reset gives it back at once")
	assert_eq(rig.target(), FcCourtProjection.default_camera())
	rig.request(_shot(50, Vector2(40, 30), 1.6, 1.0, "cut"))
	assert_eq(rig.target()["focus"], Vector2(40, 30), "and the director works again")


func test_manual_mode_stays_put_until_reset_and_auto_mode_ignores_the_person() -> void:
	var manual := FcCameraRig.new()
	manual.mode = FcCameraRig.Mode.MANUAL
	manual.manual_set(Vector2(30, 30), 2.0)
	manual.request(_shot(99, Vector2(80, 10), 2.5, 1.0, "cut"))
	_settle(manual, 10.0)
	assert_eq(manual.target()["focus"], Vector2(30, 30), "the director cannot move a manual camera")
	manual.reset()
	assert_eq(manual.mode, FcCameraRig.Mode.HYBRID, "reset returns to the shared mode")
	var auto := FcCameraRig.new()
	auto.mode = FcCameraRig.Mode.AUTO
	auto.request(_shot(50, Vector2(20, 20), 2.0, 1.0, "cut"))
	auto.manual_move(Vector2(30, 0), 2.0)
	auto.manual_set(Vector2(70, 40), 3.0)
	assert_eq(auto.target()["focus"], Vector2(20, 20), "automatic mode ignores manual input")


func test_manual_moves_are_kept_inside_the_court_and_the_zoom_range() -> void:
	var rig := FcCameraRig.new()
	for i in 30:
		rig.manual_move(Vector2(40, 40), 1.5)
	var t := rig.target()
	assert_eq(t["focus"], Vector2(94, 50))
	assert_eq(t["zoom"], FcCourtProjection.MAX_ZOOM)
	for i in 30:
		rig.manual_move(Vector2(-40, -40), 0.5)
	assert_eq(rig.target()["zoom"], FcCourtProjection.MIN_ZOOM)
	assert_eq(rig.target()["focus"], Vector2(0, 0))


func test_reduced_motion_makes_every_move_happen_at_once() -> void:
	var rig := FcCameraRig.new()
	rig.reduced = true
	rig.request(_shot(50, Vector2(70, 30), 2.0, 1.0, "ease"))
	assert_eq(rig.camera(), {"focus": Vector2(70, 30), "zoom": 2.0}, "no glide")
	rig.manual_move(Vector2(-10, 0), 1.0)
	assert_eq(rig.camera()["focus"], Vector2(60, 30))
	rig.reset()
	assert_eq(rig.camera(), FcCourtProjection.default_camera())


func test_replaying_a_whole_game_through_the_rig_is_repeatable() -> void:
	var t := _timeline(12)
	var run := func() -> Array:
		var rig := FcCameraRig.new()
		var trace: Array = []
		for i in t.size():
			rig.request(FcCameraDirector.shot_for(t, i))
			rig.advance(t.model.dwell(i))
			trace.append(rig.camera())
		return trace
	assert_eq(run.call(), run.call())
	for cam in run.call():
		assert_true(float(cam["zoom"]) >= FcCourtProjection.MIN_ZOOM and float(cam["zoom"]) <= FcCourtProjection.MAX_ZOOM)
		assert_true(FcCourtLayout.inside_court(cam["focus"]))


func test_the_centre_circle_is_a_polygon_the_engine_can_fill_even_after_projection() -> void:
	# Regression: the filled centre circle used an arc whose last point repeated its first, so every frame logged "Invalid polygon data,
	# triangulation failed" (found by the performance benchmark, which prints engine errors; the live tests do not fail on them).
	for steps in [3, 12, 40]:
		var circle := FcCourtView.circle_polygon(Vector2(47, 25), 6.0, steps)
		assert_eq(circle.size(), steps)
		for k in circle.size():
			assert_true(circle[k].distance_to(circle[(k + 1) % circle.size()]) > 0.0001, "no repeated vertex (steps %d, point %d)" % [steps, k])
		assert_true(not Geometry2D.triangulate_polygon(circle).is_empty(), "the flat polygon triangulates (%d steps)" % steps)
	var p := FcCourtProjection.new(Vector2(520, 280))
	for cam in [{}, {"focus": Vector2(20, 10), "zoom": 2.5}, {"focus": Vector2(80, 40), "zoom": 3.0}]:
		var screen := PackedVector2Array()
		for pt in FcCourtView.circle_polygon(Vector2(47, 25), 6.0, 40):
			screen.append(p.project(pt.x, pt.y, 0.0, cam))
		assert_true(not Geometry2D.triangulate_polygon(screen).is_empty(), "the projected polygon triangulates for camera %s" % str(cam))
