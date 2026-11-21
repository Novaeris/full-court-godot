extends SceneTree
## Pixel-level variety of the rendered faces (needs a window): draws 400 seeded players at the size a roster row or card shows them (96 px bust),
## reduces each picture to a 20 x 20 colour thumbnail and measures how far every face is from its NEAREST neighbour. A large nearest distance means
## there is no obvious look-alike. Run for both figures and compare:
##   godot_console --path . --script res://tools/portrait_variety.gd -- mode=hd out=docs/validation/portraits/variety_hd
##   godot_console --path . --script res://tools/portrait_variety.gd -- mode=current out=docs/validation/portraits/variety_current
## Writes <out>.txt (the numbers), <out>_sheet.png (all 400) and <out>_closest.png (the ten most alike pairs, side by side) for a person to judge.
## Distances use a flat team colour for every player (so only the FACE and body count, not the kit) and the same age for everyone.

const COUNT := 400
const PX := 96
const THUMB := 20

var _mode := "hd"
var _out := "user://variety"
var _frames := 0
var _canvas: Control = null
var _viewport: SubViewport = null
var _visuals: Array = []


class Sheet extends Control:
	var visuals: Array = []
	var cols := 25

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("11151D"))
		for i in visuals.size():
			var r := Rect2(Vector2((i % cols) * 100 + 2, (i / cols) * 100 + 2), Vector2(96, 96))
			draw_rect(r, Color("1F2A3F"))
			FcPlayerFigure.draw_live(self, Rect2(r.position + Vector2(5, 10), Vector2(86, 86)), visuals[i])


class Pair extends Control:
	var visuals: Array = []

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("11151D"))
		for i in visuals.size():
			var r := Rect2(Vector2((i % 6) * 200 + 4, (i / 6) * 200 + 4), Vector2(192, 192))
			draw_rect(r, Color("1F2A3F"))
			FcPlayerFigure.draw_live(self, Rect2(r.position + Vector2(10, 20), Vector2(172, 172)), visuals[i])


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() == 2:
			match kv[0]:
				"mode": _mode = kv[1]
				"out": _out = kv[1]
	FcPlayerFigure.hd_enabled = _mode == "hd"
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(2500, 1600)
	DisplayServer.window_set_size(Vector2i(2500, 1600))
	for i in COUNT:
		_visuals.append(FcPlayerVisual.resolve(FcPlayerPresentation.subject("variety:%d" % i, "V", {"primary": "#2B3A55", "secondary": "#C8A951", "abbreviation": "VAR"}, 10, {}, "", {"age": 27})))
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_viewport = SubViewport.new()   # off-screen, so the sheet may be larger than the monitor
		_viewport.size = Vector2i(2500, 1600)
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var s := Sheet.new()
		s.visuals = _visuals
		s.size = Vector2(2500, 1600)
		_viewport.add_child(s)
		root.add_child(_viewport)
		_canvas = s
	elif _frames == 6:
		var image := _viewport.get_texture().get_image()
		image.save_png(_out + "_sheet.png")
		_analyse(image)
	return false


func _thumb(image: Image, i: int) -> PackedFloat32Array:
	var tile := image.get_region(Rect2i((i % 25) * 100 + 2, (i / 25) * 100 + 2, 96, 96))
	tile.resize(THUMB, THUMB, Image.INTERPOLATE_BILINEAR)
	var out := PackedFloat32Array()
	for y in THUMB:
		for x in THUMB:
			var c := tile.get_pixel(x, y)
			out.append_array([c.r, c.g, c.b])
	return out


func _analyse(image: Image) -> void:
	var thumbs: Array = []
	for i in COUNT:
		thumbs.append(_thumb(image, i))
	var nearest := PackedFloat32Array()
	var pairs: Array = []
	for i in COUNT:
		var best := 1.0e9
		var best_j := -1
		for j in COUNT:
			if i == j:
				continue
			var d := 0.0
			var a: PackedFloat32Array = thumbs[i]
			var b: PackedFloat32Array = thumbs[j]
			for k in a.size():
				var diff := a[k] - b[k]
				d += diff * diff
			if d < best:
				best = d
				best_j = j
		nearest.append(sqrt(best))
		pairs.append([sqrt(best), i, best_j])
	var sorted := Array(nearest)
	sorted.sort()
	var lines := [
		"Portrait variety, mode=%s, %d players at %d px, thumbnail %dx%d" % [_mode, COUNT, PX, THUMB, THUMB],
		"nearest-neighbour distance: min %.2f  5th percentile %.2f  median %.2f  mean %.2f" % [sorted[0], sorted[int(COUNT * 0.05)], sorted[COUNT / 2], _mean(sorted)],
		"(higher is more varied; compare the two modes, the unit is arbitrary)",
	]
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var seen := {}
	var closest: Array = []
	for p in pairs:
		var key := "%d-%d" % [mini(p[1], p[2]), maxi(p[1], p[2])]
		if seen.has(key):
			continue
		seen[key] = true
		closest.append(_visuals[p[1]])
		closest.append(_visuals[p[2]])
		lines.append("closest pair %d: variety:%d and variety:%d, distance %.2f" % [closest.size() / 2, p[1], p[2], p[0]])
		if closest.size() >= 12:
			break
	var file := FileAccess.open(_out + ".txt", FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	print("\n".join(lines))
	_canvas.queue_free()
	var pair_sheet := Pair.new()
	pair_sheet.visuals = closest
	pair_sheet.size = Vector2(1208, 408)
	root.add_child(pair_sheet)
	_save_pairs.call_deferred(pair_sheet)


func _save_pairs(sheet: Control) -> void:
	await process_frame
	await process_frame
	var image := root.get_texture().get_image().get_region(Rect2i(0, 0, 1208, 408))
	image.save_png(_out + "_closest.png")
	quit()


func _mean(values: Array) -> float:
	var total := 0.0
	for v in values:
		total += float(v)
	return total / float(values.size())
