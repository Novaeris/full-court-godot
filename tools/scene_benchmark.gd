extends SceneTree
## Scene scaling benchmark (3D overhaul, M6): how the cost of the 3D broadcast grows from ONE animated player to a FULL arena, and how it changes with
## the window size. It builds the real FcCourtScene (court, hoops, benches, dressing, crowd) and real FcBroadcastCharacters (the same skinned bodies the
## replay uses), animates them every frame through the real states, and measures frame time with vsync OFF, with the broadcast camera.
## NOT headless: it opens a window.
##   godot_console --path . --script res://tools/scene_benchmark.gd
## Prints one line per case: frame time (avg, p95, p99, worst), draw calls, video memory and the process working set.
## Cases: arena only (no crowd, no people), 1 player, 10 players, 31 characters (the 10 on court, 16 on the benches, 3 referees, 2 coaches), the same
## with the full 6,000 crowd, a 12,000 crowd stress, and the full scene at three resolutions. Measured on the machine it is run on, nothing else.

const WARMUP_FRAMES := 40
const MEASURE_FRAMES := 400
const ANIMATIONS := ["run", "dribble_run", "defend", "shoot", "layup", "shuffle", "idle", "drive", "contest", "walk"]

var _cases: Array = [
	{"name": "arena only, no crowd", "people": 0, "crowd": 0, "size": Vector2i(1920, 1080)},
	{"name": "1 player, no crowd", "people": 1, "crowd": 0, "size": Vector2i(1920, 1080)},
	{"name": "10 players, no crowd", "people": 10, "crowd": 0, "size": Vector2i(1920, 1080)},
	{"name": "31 characters, no crowd", "people": 31, "crowd": 0, "size": Vector2i(1920, 1080)},
	{"name": "arena + crowd 6000, no people", "people": 0, "crowd": 6000, "size": Vector2i(1920, 1080)},
	{"name": "10 players + crowd 6000", "people": 10, "crowd": 6000, "size": Vector2i(1920, 1080)},
	{"name": "FULL: 31 characters + crowd 6000, 1080p", "people": 31, "crowd": 6000, "size": Vector2i(1920, 1080)},
	{"name": "stress: 31 characters + crowd 12000, 1080p", "people": 31, "crowd": 12000, "size": Vector2i(1920, 1080)},
	{"name": "FULL at 1280x720", "people": 31, "crowd": 6000, "size": Vector2i(1280, 720)},
	{"name": "FULL at 2560x1440", "people": 31, "crowd": 6000, "size": Vector2i(2560, 1440)},
]
var _case := -1
var _scene: FcCourtScene
var _people: Array = []
var _frame := 0
var _times: PackedFloat64Array = PackedFloat64Array()
var _last_usec := 0
var _build_ms := 0.0
var _clock := 0.0
var _model := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("model="):
			_model = arg.get_slice("=", 1)   # model=library benchmarks the M1 players
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	print("machine: %s | %s | renderer %s" % [OS.get_processor_name(), RenderingServer.get_video_adapter_name(), str(ProjectSettings.get_setting("rendering/renderer/rendering_method"))])
	_next_case()


func _next_case() -> void:
	if _scene != null:
		_scene.queue_free()
		_scene = null
	_people.clear()
	_case += 1
	if _case >= _cases.size():
		quit()
		return
	var c: Dictionary = _cases[_case]
	var size: Vector2i = c["size"]
	DisplayServer.window_set_size(size)
	root.size = size
	var started := Time.get_ticks_usec()
	var home := Color.html("2F6FED")
	var away := Color.html("F28A2E")
	_scene = FcCourtScene.new()
	_scene.crowd_count = int(c["crowd"])
	root.add_child(_scene)
	_scene.build(home, away, "HOU", FcArenaIdentity.make({"home": {"abbr": "HOU", "name": "Houston Comets", "color": home}, "away": {"abbr": "DAL", "name": "Dallas", "color": away}}))
	_scene.set_bench_figures_visible(false)
	FcBroadcastCharacter.defer_v2_bake = true   # as the replay view does: build all, then bake the V2 morphs in parallel
	for i in int(c["people"]):
		var side := i % 2
		var subject := {"key": "bench:%d" % i, "name": "p%d" % i, "jersey": i, "position": ["PG", "SG", "SF", "PF", "C"][i % 5], "model": _model,
			"physical": {"height_cm": 185 + (i * 7) % 30, "weight_kg": 80 + (i * 5) % 40}, "team": {"primary": "#" + (home if side == 0 else away).to_html(false), "secondary": "#F4F7FF", "abbreviation": "HOU", "name": "Houston"}}
		var p := FcBroadcastCharacter.new().setup(subject, float(i) * 0.137)
		p.auto_advance = false
		p.position = Vector3(20.0 + float(i % 10) * 5.0, 0.0, 12.0 + float(i / 10) * 9.0)
		p.set_state(ANIMATIONS[i % ANIMATIONS.size()])
		_scene.add_child(p)
		_people.append(p)
	FcBroadcastCharacter.defer_v2_bake = false
	FcPlayerLod.bake_characters(_people)
	_scene.set_camera(FcBroadcast3DRules.camera_pose(Vector2(47.0, 25.0), 1.0))
	_build_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_frame = 0
	_times = PackedFloat64Array()
	_last_usec = Time.get_ticks_usec()


func _process(delta: float) -> bool:
	if _scene == null:
		return false
	var now := Time.get_ticks_usec()
	_frame += 1
	_clock += delta
	for i in _people.size():
		var p := _people[i] as FcBroadcastCharacter
		if i >= 13 and i < 29:   # the bench and the coaches: 20 times a second, as the replay view does
			if _clock >= 0.05:
				p.advance(_clock)
		else:
			p.advance(delta)
	if _clock >= 0.05:
		_clock = 0.0
	if _frame > WARMUP_FRAMES:
		_times.append(float(now - _last_usec) / 1000.0)
	_last_usec = now
	if _times.size() >= MEASURE_FRAMES:
		_report()
		_next_case()
	return false


func _report() -> void:
	var sorted := _times.duplicate()
	sorted.sort()
	var total := 0.0
	for t in sorted:
		total += t
	var n := sorted.size()
	var c: Dictionary = _cases[_case]
	var over := 0
	for t in sorted:
		if t > 16.6:
			over += 1
	print("%-46s | avg %6.2f ms | p95 %6.2f | p99 %6.2f | worst %6.2f | >16.6 ms: %3d | draw calls %5d | video %3d MB | working set %4d MB | build %5.0f ms" % [
		str(c["name"]), total / float(n), sorted[int(n * 0.95)], sorted[int(n * 0.99)], sorted[n - 1], over,
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0), int(OS.get_static_memory_usage() / 1048576.0), _build_ms])
