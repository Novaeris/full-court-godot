extends SceneTree
## Measures what a portrait costs to DRAW, for the shipped figure and the high-fidelity prototype, at several sizes (needs a window):
##   godot_console --path . --script res://tools/portrait_bench.gd
## For each size it draws 200 busts, a few passes, and prints the average microseconds the _draw callback took per portrait and the number of
## canvas draw commands (a proxy for GPU work). Used for the performance section of docs/PLAYER_VISUAL_PROPOSAL.md. The numbers are for THIS
## machine: compare old with HD, not with another computer. A cached texture costs one draw command whatever the figure's detail.

const SIZES := [32, 64, 128, 256]
const COUNT := 200

var _frames := 0
var _probes: Array = []
var _results: Array = []
var _step := 0
var _plan: Array = []
var _bake: FcPortraitBake = null


class Probe extends Control:
	var visual: Dictionary = {}
	var spent_usec := 0
	var draws := 0
	var texture: Texture2D = null

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var t0 := Time.get_ticks_usec()
		if texture != null:
			draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)
		else:
			FcPlayerFigure.draw(self, Rect2(Vector2.ZERO, size), visual)
		spent_usec += Time.get_ticks_usec() - t0
		draws += 1


func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1400, 900)
	DisplayServer.window_set_size(Vector2i(1400, 900))
	for mode in ["current", "hd", "hd_baked"]:
		for px in SIZES:
			_plan.append({"mode": mode, "hd": mode != "current", "px": px})
	_bake = FcPortraitBake.new()
	root.add_child(_bake)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	if _step >= _plan.size():
		print("")
		print("size   figure    avg draw time / portrait (us)    draw commands / portrait")
		for r in _results:
			print("%4d   %-9s  %10.1f                       %8.1f" % [r["px"], r["mode"], r["us"], r["cmds"]])
		quit()
		return true
	var job: Dictionary = _plan[_step]
	if _probes.is_empty():
		FcPlayerFigure.hd_enabled = job["hd"]
		for i in COUNT:
			var p := Probe.new()
			p.visual = FcPlayerVisual.resolve(FcPlayerPresentation.subject("bench:%d" % i, "Bench %d" % i, {"name": "T%d" % (i % 7), "primary": "#1F3A5F", "secondary": "#C8A951"}, i % 99))
			p.visual["age"] = 19 + i % 20
			p.size = Vector2(job["px"], job["px"])
			if job["mode"] == "hd_baked":
				p.texture = _bake.texture_for(p.visual, p.size, 1.0, "bust")
			p.position = Vector2((i % 40) * 34, (i / 40) * 34) if job["px"] <= 32 else Vector2((i % 10) * 138, ((i / 10) % 6) * 138)
			root.add_child(p)
			_probes.append(p)
		_frames = 0
		return false
	if _frames >= (14 if job["mode"] == "hd_baked" else 12):
		var total := 0
		var count := 0
		for p in _probes:
			total += p.spent_usec
			count += p.draws
		var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_results.append({"mode": job["mode"], "hd": job["hd"], "px": job["px"], "us": float(total) / float(maxi(count, 1)), "cmds": float(draws) / float(COUNT)})
		for p in _probes:
			p.queue_free()
		_probes.clear()
		_step += 1
		_frames = 0
	return false
