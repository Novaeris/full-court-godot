extends SceneTree
## The replay performance benchmark (master plan 4.7.2, docs/validation/PERFORMANCE_THRESHOLDS.md). Opens a real 1920 x 1080 window with the
## project's renderer (gl_compatibility), vsync OFF (so frame time is the true cost of a frame, not the monitor's refresh), plays the fixed
## benchmark game and records the frame-time distribution and memory. Used for the 2D baseline now and, with mode=3d, for the 3D prototype
## and later the 3D viewer, with the SAME procedure, so a 3D result is always read against the 2D baseline on the same machine.
##
## Run (a window opens):  godot_console --path . --script res://tools/perf_benchmark.gd -- mode=2d run=standard [seconds=120] [seed=N]
##   mode: 2d (the replay screen) | 3d (the B1b prototype in prototypes/b1b; options crowd=N shadows=0|1 board=0|1)
##   run:  standard (1x, automatic camera) | fast (4x) | camera (scripted pan/zoom/preset sweep) | leak (enter/exit cycles) | soak (long run)
## Prints one block of numbers; writes nothing else.

const BENCHMARK_SEED_LIMIT := 400

var _mode := "2d"
var _run := "standard"
var _seconds := -1.0
var _seed := -1
var _crowd := 6000
var _shadows := true
var _board := true
var _shot := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"mode": _mode = kv[1]
			"run": _run = kv[1]
			"seconds": _seconds = float(kv[1])
			"seed": _seed = int(kv[1])
			"crowd": _crowd = int(kv[1])
			"shot": _shot = kv[1]
			"shadows": _shadows = kv[1] != "0"
			"board": _board = kv[1] != "0"
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_go.call_deferred()


func _go() -> void:
	await process_frame
	var game := _benchmark_game()
	print("benchmark game: seed %d, %d events, overtimes %d, home %s away %s" % [game["seed"], game["model"].size(), game["box"].overtimes, game["box"].abbreviations[0], game["box"].abbreviations[1]])
	print("machine: %s | %s | renderer %s | window %s | vsync off" % [OS.get_processor_name(), RenderingServer.get_video_adapter_name(), str(ProjectSettings.get_setting("rendering/renderer/rendering_method")), str(DisplayServer.window_get_size())])
	await process_frame
	_memory("M0 (league and game generated, no replay screen)")
	if _run == "leak":
		await _leak(game)
	else:
		await _play(game)
	quit(0)


## The fixed benchmark game: the first seeded game, scanning seeds upward, that goes to overtime and has free throws and substitutions.
func _benchmark_game() -> Dictionary:
	var data := FcGenerationData.load_default()
	var defs := FcDefinitionSet.load_default()
	var ratings := FcPlayerRatings.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 4
	cfg.conference_count = 1
	cfg.divisions_per_conference = 1
	cfg.free_agent_count = 0
	var world := FcWorldGenerator.new(data, defs, cfg).generate(31415)
	var ids := world.teams.ids()
	var first := _seed if _seed >= 0 else 1
	for s in range(first, first + BENCHMARK_SEED_LIMIT):
		var sim := FcGameSimulator.new()
		sim.recorder = FcGameEventLog.new()
		var box := sim.simulate(FcGameTeam.from_world(world, ids[0], ratings), FcGameTeam.from_world(world, ids[1], ratings), FcRng.new(s))
		var has_ft := false
		var has_sub := false
		for r in sim.recorder.rows:
			has_ft = has_ft or r[0] == FcGameEventLog.EV_FREE_THROW
			has_sub = has_sub or r[0] == FcGameEventLog.EV_SUBSTITUTION
		if _seed >= 0 or (box.overtimes > 0 and has_ft and has_sub):
			return {"seed": s, "box": box, "log": sim.recorder, "model": FcReplayModel.build(sim.recorder, box)}
	push_error("no benchmark game found")
	quit(1)
	return {}


func _make_arena() -> Node3D:
	var t0 := Time.get_ticks_usec()
	var arena := FcB1bArena.new()
	arena.crowd_count = _crowd
	arena.shadows = _shadows
	arena.viewport_scoreboard = _board
	root.add_child(arena)
	arena.build()
	arena.set_meta("build_ms", float(Time.get_ticks_usec() - t0) / 1000.0)
	return arena


func _make_screen(game: Dictionary) -> Control:
	var holder := Control.new()
	holder.size = Vector2(1920, 1080)
	root.add_child(holder)
	var screen := FcReplayScreen.new().setup(game["model"], [], false)
	screen.size = Vector2(1900, 1060)
	screen.position = Vector2(10, 10)
	holder.add_child(screen)
	holder.set_meta("screen", screen)
	return holder


func _play_3d() -> void:
	var load_start := Time.get_ticks_usec()
	var arena: FcB1bArena = _make_arena() as FcB1bArena
	await process_frame
	print("3d config: crowd %d instances, shadows %s, viewport scoreboard %s; arena built in %.0f ms, first frame %.0f ms after the request" % [arena.instance_count(), str(_shadows), str(_board), float(arena.get_meta("build_ms")), float(Time.get_ticks_usec() - load_start) / 1000.0])
	var duration: float = _seconds if _seconds > 0.0 else float({"standard": 120.0, "fast": 60.0, "camera": 60.0, "soak": 300.0}.get(_run, 120.0))
	await _settle(10.0)
	_memory("3D scene settled")
	if _shot != "":
		root.get_viewport().get_texture().get_image().save_png(_shot)
		print("screenshot saved to %s" % _shot)
	var shots := [[Vector3(47, 40, 82), Vector3(47, 0, 22)], [Vector3(20, 22, 60), Vector3(10, 4, 25)], [Vector3(75, 18, 70), Vector3(85, 8, 25)], [Vector3(47, 70, 30), Vector3(47, 0, 25)], [Vector3(-8, 14, 25), Vector3(30, 5, 25)]]
	var frames := PackedFloat64Array()
	var started := Time.get_ticks_usec()
	var last := started
	var next_cut := 0.0
	var cut := 0
	var cut_every := 5.0 if _run == "camera" else 8.0
	while float(Time.get_ticks_usec() - started) / 1e6 < duration:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now - last) / 1000.0)
		last = now
		var elapsed := float(now - started) / 1e6
		if elapsed >= next_cut:
			next_cut += cut_every   # a director-like cut every few seconds (the camera run uses 5 s as in the 2D run)
			var pick: Array = shots[cut % shots.size()]
			arena.set_camera(pick[0], pick[1])
			cut += 1
	_memory("memory at the end of the run")
	_report("3d/%s for %.0f s" % [_run, duration], frames)


func _play(game: Dictionary) -> void:
	if _mode == "3d":
		await _play_3d()
		return
	var holder := _make_screen(game)
	var screen: FcReplayScreen = holder.get_meta("screen")
	var duration: float = _seconds if _seconds > 0.0 else float({"standard": 120.0, "fast": 60.0, "camera": 60.0, "soak": 600.0}.get(_run, 120.0))
	screen.set_speed(4.0 if _run == "fast" else 1.0)
	screen.seek(screen.model.start_index(), false)
	await _settle(10.0)
	_memory("M2D-style snapshot (replay screen settled)")
	var frames := PackedFloat64Array()
	var started := Time.get_ticks_usec()
	var last := started
	var next_sweep := 0.0
	var sweep := 0
	if not screen.is_playing():
		screen.toggle_play()
	while float(Time.get_ticks_usec() - started) / 1e6 < duration:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now - last) / 1000.0)
		last = now
		if not screen.is_playing():
			screen.toggle_play()
		var elapsed := float(now - started) / 1e6
		if _run == "camera" and elapsed >= next_sweep:
			next_sweep += 5.0
			screen.set_camera_mode("manual")
			var presets := [[Vector2(20, 25), 2.2], [Vector2(75, 25), 2.6], [Vector2(47, 25), 1.0], [Vector2(47, 10), 1.8], [Vector2(47, 40), 1.4]]
			var pick: Array = presets[sweep % presets.size()]
			screen.court.rig.manual_set(pick[0], pick[1])
			sweep += 1
	_memory("memory at the end of the run")
	_report("%s/%s %s" % [_mode, _run, "for %.0f s" % duration], frames)


func _leak_3d() -> void:
	print("leak check: 10 enter/exit cycles of the 3d prototype (15 s each, 5 s settle after exit)")
	var arena := _make_arena()
	await _settle(10.0)
	_memory("3D settled baseline")
	arena.queue_free()
	await _settle(2.0)
	var worst := 0
	var first_after := 0
	for cycle in 10:
		arena = _make_arena()
		await _settle(15.0)
		arena.queue_free()
		await _settle(5.0)
		var m := _memory("after exit %d" % (cycle + 1))
		if cycle == 0:
			first_after = int(m["working_set_mb"])
		worst = maxi(worst, int(m["working_set_mb"]))
	print("leak summary: working set after the first exit %d MB, worst after any exit %d MB, growth %d MB" % [first_after, worst, worst - first_after])


func _leak(game: Dictionary) -> void:
	if _mode == "3d":
		await _leak_3d()
		return
	print("leak check: 10 enter/exit cycles of the %s replay (15 s play each, 5 s settle after exit)" % _mode)
	var holder := _make_screen(game)
	var screen: FcReplayScreen = holder.get_meta("screen")
	screen.seek(screen.model.start_index(), false)
	await _settle(10.0)
	_memory("M2D-style baseline")
	holder.queue_free()
	await _settle(2.0)
	var worst := 0
	var first_after := 0
	for cycle in 10:
		holder = _make_screen(game)
		screen = holder.get_meta("screen")
		screen.seek(screen.model.start_index(), false)
		screen.toggle_play()
		await _settle(15.0)
		holder.queue_free()
		await _settle(5.0)
		var m := _memory("after exit %d" % (cycle + 1))
		if cycle == 0:
			first_after = int(m["working_set_mb"])
		worst = maxi(worst, int(m["working_set_mb"]))
	print("leak summary: working set after the first exit %d MB, worst after any exit %d MB, growth %d MB" % [first_after, worst, worst - first_after])


func _settle(seconds: float) -> void:
	var t0 := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - t0) / 1e6 < seconds:
		await process_frame


## A snapshot of memory and rendering monitors (engine side) and the process working set (operating system side).
func _memory(label: String) -> Dictionary:
	var out := {"working_set_mb": _working_set_mb(), "static_mb": int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0), "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), "video_mb": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		"texture_mb": int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0), "buffer_mb": int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), "primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))}
	print("memory | %s | process working set %d MB | engine static %d MB | nodes %d (orphans %d) | video %d MB (texture %d, buffer %d) | draw calls %d, primitives %d" % [label, out["working_set_mb"], out["static_mb"], out["nodes"], out["orphans"], out["video_mb"], out["texture_mb"], out["buffer_mb"], out["draw_calls"], out["primitives"]])
	return out


func _working_set_mb() -> int:
	var output: Array = []
	var code := OS.execute("powershell", ["-NoProfile", "-Command", "(Get-Process -Id %d).WorkingSet64" % OS.get_process_id()], output)
	if code != 0 or output.is_empty():
		return -1
	return int(float(str(output[0]).strip_edges()) / 1048576.0)


func _report(title: String, frames: PackedFloat64Array) -> void:
	var sorted := frames.duplicate()
	sorted.sort()
	var n := sorted.size()
	var total := 0.0
	var over_16 := 0
	var over_33 := 0
	for f in frames:
		total += f
		over_16 += 1 if f > 16.6 else 0
		over_33 += 1 if f > 33.3 else 0
	print("frame time | %s | %d frames | avg %.2f ms (%.0f fps) | p50 %.2f | p95 %.2f | p99 %.2f | worst %.2f ms | over 16.6 ms: %d (%.2f%%) | over 33.3 ms: %d (%.2f%%)" % [
		title, n, total / n, 1000.0 / (total / n), sorted[n / 2], sorted[int(n * 0.95)], sorted[int(n * 0.99)], sorted[n - 1], over_16, 100.0 * over_16 / n, over_33, 100.0 * over_33 / n])
