extends SceneTree
## Measures the portrait texture cache in a real window (needs a window; the headless renderer cannot read pixels back):
##   godot_console --path . --script res://tools/portrait_perf.gd [-- budget_mb=20 out=docs/validation/portraits/perf.txt]
## Scenarios: a large roster, rapid navigation between screens, a player profile opened and closed repeatedly, one player on many cards,
## cache pressure with a tiny budget, and a scrolling-style forced redraw with and without the cache. For each it prints the bake time, hit
## rate, cache bytes, texture memory and the average frame time (vsync off). Numbers are for THIS machine; the proposal compares with/without.

var _out := ""
var _budget_mb := 20
var _lines: Array = []
var _bake: FcPortraitBake


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() == 2:
			match kv[0]:
				"out": _out = kv[1]
				"budget_mb": _budget_mb = int(kv[1])
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 800)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_run.call_deferred()


func _log(text: String) -> void:
	print(text)
	_lines.append(text)


func _visual(i: int, age_offset: int = 0) -> Dictionary:
	var subject := FcPlayerPresentation.subject("perf:%d" % i, "Perf %d" % i, {"name": "T%d" % (i % 9), "abbreviation": "T%d" % (i % 9), "primary": "#1F3A5F", "secondary": "#C8A951"}, 1 + i % 98, {}, "", {"age": 19 + (i + age_offset) % 20})
	return FcPlayerVisual.resolve(subject)


func _portraits(count: int, px: int, parent: Control, offset: int = 0) -> Array:
	var out: Array = []
	for i in count:
		var p := FcPlayerPortrait.new()
		p.setup(FcPlayerPresentation.subject("perf:%d" % (i + offset), "Perf %d" % i, {"name": "T%d" % (i % 9), "abbreviation": "T%d" % (i % 9), "primary": "#1F3A5F", "secondary": "#C8A951"}, 1 + i % 98, {}, "", {"age": 19 + i % 20}), px, "head" if i % 3 == 0 else "bust")
		parent.add_child(p)
		out.append(p)
	return out


func _frame_ms(frames: int, redraw: Array) -> float:
	var total := 0.0
	for i in frames:
		for p in redraw:
			(p as CanvasItem).queue_redraw()
		var t0 := Time.get_ticks_usec()
		await process_frame
		total += float(Time.get_ticks_usec() - t0) / 1000.0
	return total / float(frames)


func _texture_mb() -> float:
	return Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0


func _report(title: String, extra: String = "") -> void:
	var s: Dictionary = _bake.stats
	_log("%-34s baked %4d  hits %5d  misses %5d  live %5d  hit-rate %3.0f%%  evicted %4d  cache %5.2f MB (peak %5.2f)  bake %6.1f ms  texmem %6.1f MB  %s" % [title, s["baked"], s["hits"], s["misses"], s["live_draws"], _bake.hit_rate() * 100.0, s["evicted"], float(_bake.bytes_used()) / 1048576.0, float(s["peak_bytes"]) / 1048576.0, float(s["bake_usec"]) / 1000.0, _texture_mb(), extra])


func _reset_stats() -> void:
	_bake.clear()
	_bake.stats = {"hits": 0, "misses": 0, "evicted": 0, "baked": 0, "bake_usec": 0, "failed": 0, "peak_bytes": 0, "live_draws": 0}


func _run() -> void:
	await process_frame
	_bake = FcPortraitBake.new()
	_bake.budget_bytes = _budget_mb * 1048576
	root.add_child(_bake)
	var host := Control.new()
	host.size = Vector2(1280, 800)
	root.add_child(host)
	await process_frame
	_log("Portrait cache measurements (budget %d MB, window 1280x800, vsync off)" % _budget_mb)

	# 1. a large roster: first draw (cold), then a forced redraw of everything (warm), with and without the cache
	var flow := HFlowContainer.new()
	flow.size = Vector2(1280, 800)
	host.add_child(flow)
	var roster := _portraits(400, 64, flow)
	var cold := await _frame_ms(1, [])
	for i in 8:
		await process_frame
	_report("roster of 400, cold", "first frames %.1f ms" % cold)
	var waited := 0
	while not _bake._pending.is_empty() or int(_bake.stats["baked"]) < 400:
		for p in roster:
			(p as CanvasItem).queue_redraw()
		await process_frame
		waited += 1
		if waited > 300:
			break
	_log("roster of 400: every picture baked after %d frames" % waited)
	var warm_cached := await _frame_ms(30, roster)
	_report("roster of 400, forced redraw, cached", "frame %.2f ms" % warm_cached)
	_bake.enabled = false
	var warm_live := await _frame_ms(30, roster)
	_log("roster of 400, forced redraw, live          frame %.2f ms  (cache off)" % warm_live)
	_bake.enabled = true
	host.remove_child(flow)
	flow.queue_free()
	await process_frame

	# 2. rapid navigation: a 120-row screen built and thrown away 40 times
	_reset_stats()
	var t0 := Time.get_ticks_usec()
	for cycle in 40:
		var screen := HFlowContainer.new()
		screen.size = Vector2(1280, 800)
		host.add_child(screen)
		_portraits(120, 48, screen)
		await process_frame
		screen.queue_free()
		await process_frame
	_report("40 screens x 120 portraits", "wall %.0f ms" % (float(Time.get_ticks_usec() - t0) / 1000.0))

	# 3. the same player on many cards (a collection with duplicates) and a profile opened and closed
	_reset_stats()
	var cards := HFlowContainer.new()
	cards.size = Vector2(1280, 800)
	host.add_child(cards)
	for i in 60:
		var card := FcCardFace.new().setup({"card_id": "same", "player_id": "perf_one", "name": "Same Player", "rarity": "rare", "overall": 82, "position": "SG", "edition": "Base", "team": "Perf", "owned": true, "available": true}, {"size": FcCardFace.SIZE_SMALL})
		cards.add_child(card)
	for i in 6:
		await process_frame
	_report("60 cards of one player")
	cards.queue_free()
	await process_frame
	_reset_stats()
	for cycle in 30:
		var stage := FcShowcaseStage.new().setup(FcPlayerPresentation.subject("perf:profile", "Profile Player", {"name": "T", "abbreviation": "TTT", "primary": "#1F3A5F", "secondary": "#C8A951"}, 11, {}, "", {"age": 27, "physical": {"height_cm": 201, "weight_kg": 98}, "position": "SF"}), 260)
		host.add_child(stage)
		await process_frame
		await process_frame
		stage.queue_free()
		await process_frame
	_report("profile opened and closed 30 times")

	# 4. cache pressure: a tiny budget against 700 different players
	_reset_stats()
	_bake.budget_bytes = 2 * 1048576
	var pressure := HFlowContainer.new()
	pressure.size = Vector2(1280, 800)
	host.add_child(pressure)
	for batch in 7:
		var ps := _portraits(100, 96, pressure, batch * 100)
		for i in 4:
			await process_frame
		for p in ps:
			p.queue_free()
		await process_frame
	_report("700 players against a 2 MB budget", "ceiling held: %s" % ("yes" if int(_bake.stats["peak_bytes"]) <= _bake.budget_bytes else "NO"))
	_bake.budget_bytes = _budget_mb * 1048576

	if _out != "":
		var file := FileAccess.open(_out, FileAccess.WRITE)
		file.store_string("\n".join(_lines) + "\n")
		file.close()
	quit()
