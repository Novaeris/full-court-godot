extends FcTestCase
## Performance regression guard for the 3D broadcast that runs on any machine, with no GPU (AI toolkit, phase 7). A window and a graphics card are needed to
## measure frame time (tools/scene_benchmark.gd and tools/perf_benchmark.gd, run by hand and recorded in docs/validation), so this checks what CAN be
## checked headless and exactly: the SIZE of the work (triangles per player, characters per scene, nodes, crowd), which is what makes frames slow, plus loose
## timing guards that only trip on a many-times slowdown (the limits are about 10x the numbers measured on the development machine: building 31 characters
## took 0.26 s there, a second of animation for all of them 0.11 s).
## Budgets, from the measurements in docs/validation/3d_overhaul/M6_VALIDATION.md: a generated player 5,024 to 6,008 triangles; the court scene 202 nodes and
## one crowd MultiMesh. Raise a limit only with a measurement that justifies it, in the same change as the code that needs it.

const MAX_TRIANGLES_PER_PLAYER := 9000
const MIN_TRIANGLES_PER_PLAYER := 3000
const MAX_SCENE_NODES := 320
const MAX_BUILD_SECONDS_FOR_31 := 3.0
const MAX_ANIMATE_SECONDS_FOR_31_X_200 := 2.0


func _subject(i: int) -> Dictionary:
	return {"key": "budget:%d" % i, "name": "p", "jersey": i, "position": ["PG", "SG", "SF", "PF", "C"][i % 5],
		"appearance": {"hair": ["bald", "short", "fade", "afro", "braids", "locs", "curly", "long"][i % 8], "facial_hair": ["none", "stubble", "goatee", "beard"][i % 4]},
		"physical": {"height_cm": 185 + (i * 7) % 30, "weight_kg": 80 + (i * 5) % 40}, "team": {"primary": "#2F6FED", "secondary": "#F4F7FF"}}


func test_every_hair_and_build_stays_inside_the_triangle_budget() -> void:
	var worst := 0
	var best := 1000000
	for i in 31:
		var c := FcBroadcastCharacter.new().setup(_subject(i))
		worst = maxi(worst, c.triangle_count())
		best = mini(best, c.triangle_count())
		c.free()
	assert_true(worst <= MAX_TRIANGLES_PER_PLAYER, "the biggest player has %d triangles (budget %d)" % [worst, MAX_TRIANGLES_PER_PLAYER])
	assert_true(best >= MIN_TRIANGLES_PER_PLAYER, "the smallest player has %d triangles: a body that is too simple is a regression too (floor %d)" % [best, MIN_TRIANGLES_PER_PLAYER])
	var proto := FcBroadcastCharacter.new().setup({"key": "p", "name": "p", "jersey": 1, "position": "SF", "physical": {"height_cm": 198, "weight_kg": 95}, "model": "res://assets/players/fc_player_proto.glb", "team": {"primary": "#2F6FED", "secondary": "#F4F7FF"}})
	assert_true(proto.imported and proto.triangle_count() <= MAX_TRIANGLES_PER_PLAYER, "an imported player is inside the same budget (%d)" % proto.triangle_count())
	proto.free()


func test_the_court_scene_has_a_bounded_number_of_nodes_and_one_crowd() -> void:
	var scene := FcCourtScene.new()
	scene.crowd_count = 6000
	scene.build(Color.html("2F6FED"), Color.html("F28A2E"), "HOM")
	var count := 0
	var stack: Array = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		count += 1
		stack.append_array(n.get_children())
	assert_true(count <= MAX_SCENE_NODES, "the court scene has %d nodes (budget %d)" % [count, MAX_SCENE_NODES])
	assert_eq(scene.instance_count(), 6000, "the crowd is one MultiMesh of 6,000 instances: no per-spectator node")
	scene.free()


func test_building_and_animating_a_full_cast_is_not_many_times_slower_than_it_was() -> void:
	var started := Time.get_ticks_usec()
	var cast: Array = []
	for i in 31:
		var c := FcBroadcastCharacter.new().setup(_subject(i), float(i) * 0.1)
		c.auto_advance = false
		cast.append(c)
	var build_seconds := float(Time.get_ticks_usec() - started) / 1000000.0
	assert_true(build_seconds < MAX_BUILD_SECONDS_FOR_31, "building 31 characters took %.2f s (limit %.1f, measured 0.26 on the development machine)" % [build_seconds, MAX_BUILD_SECONDS_FOR_31])
	started = Time.get_ticks_usec()
	for frame in 200:
		for c in cast:
			(c as FcBroadcastCharacter).advance(1.0 / 60.0)
	var animate_seconds := float(Time.get_ticks_usec() - started) / 1000000.0
	assert_true(animate_seconds < MAX_ANIMATE_SECONDS_FOR_31_X_200, "200 frames of 31 characters took %.2f s (limit %.1f, measured 0.11)" % [animate_seconds, MAX_ANIMATE_SECONDS_FOR_31_X_200])
	for c in cast:
		c.free()
