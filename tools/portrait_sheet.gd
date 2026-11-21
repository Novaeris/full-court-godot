extends SceneTree
## Renders portrait contact sheets to PNG files so the faces can be LOOKED at (needs a window; not headless):
##   godot_console --path . --script res://tools/portrait_sheet.gd -- out=docs/validation/portraits/current mode=current
##   godot_console --path . --script res://tools/portrait_sheet.gd -- out=docs/validation/portraits/hd mode=hd
## mode=current draws the shipped figure (FcPlayerFigure); mode=hd draws the same players with the prototype (FcPlayerFigure.hd_enabled).
## Sheets written: bust (120 players), headshot (120), full (24 standing), sizes (the size ladder for 6 players), cards (Dynasty cards),
## uniforms (one player in 12 team kits), ages (one face from 19 to 38).
## The players are SEEDED fictional ones ("sheet:N"): the same sheet every run, on every machine.

const SHEET_COUNT := 120
const TEAMS := [
	["Harbor Kings", "HBK", "#1F3A5F", "#C8A951"], ["Desert Suns", "DSU", "#C4501B", "#F4E3B2"], ["Pine Wolves", "PNW", "#1E5A3A", "#D9E4DC"],
	["Iron Foxes", "IRF", "#6B1D2A", "#E8DCC8"], ["River Hawks", "RVH", "#0F6C8C", "#F2F6F8"], ["Bay Comets", "BYC", "#3B2A7A", "#F2C94C"],
	["Summit Bears", "SMB", "#4A3A28", "#F0D9A8"], ["Lake Sharks", "LKS", "#14456B", "#BFD9EA"], ["Metro Owls", "MTO", "#222831", "#E94560"],
	["Coast Pelicans", "CPL", "#0B7A75", "#FFD166"], ["Valley Stags", "VLS", "#7A4B1F", "#EADBC0"], ["Gold Rush", "GLR", "#B8860B", "#1B1B1B"],
]

var _out := "user://portraits"
var _mode := "current"
var _frames := 0
var _canvas: Control = null
var _jobs: Array = []


class Sheet extends Control:
	var items: Array = []   # [{rect: Rect2, visual: Dictionary, kind: String}]
	var bg := Color("11151D")
	var labels: Array = []

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), bg)
		for it in items:
			var r: Rect2 = it["rect"]
			var v: Dictionary = it["visual"]
			var kind: String = it["kind"]
			var uni: Dictionary = v["uniform"]
			var well: Color = Color(uni["primary"]).darkened(0.55)
			if kind == "headshot":
				draw_rect(r, well)
				FcPlayerFigure.draw_headshot(self, Rect2(r.position + r.size * 0.04, r.size * 0.92), v)
			elif kind == "full":
				draw_rect(r, well)
				FcPlayerFigure.draw(self, r.grow(-6), v, true)
			elif kind == "card":
				pass
			else:
				draw_rect(r, well)
				FcPlayerFigure.draw(self, Rect2(r.position + Vector2(r.size.x * 0.06, r.size.y * 0.1), r.size * Vector2(0.88, 0.9)), v)
		var font := ThemeDB.fallback_font
		for l in labels:
			draw_string(font, l["pos"], l["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, l.get("size", 13), Color("C9D3E3"))


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() == 2:
			match kv[0]:
				"out": _out = kv[1]
				"mode": _mode = kv[1]
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DirAccess.make_dir_recursive_absolute(_out)
	FcPlayerFigure.hd_enabled = _mode == "hd"
	_jobs = ["bust", "headshot", "full", "sizes", "uniforms", "ages"]


func _visual(i: int, age: int = 0, team_index: int = -1) -> Dictionary:
	var t: Array = TEAMS[(i if team_index < 0 else team_index) % TEAMS.size()]
	var v := FcPlayerVisual.resolve(FcPlayerPresentation.subject("sheet:%d" % i, "Sheet Player %d" % i, {"name": t[0], "abbreviation": t[1], "primary": t[2], "secondary": t[3]}, 1 + FcPlayerVisual.fnv1a("n%d" % i) % 98))
	if age > 0:
		v["age"] = age
	return v


func _process(_delta: float) -> bool:
	_frames += 1
	if _canvas == null:
		if _jobs.is_empty():
			quit()
			return true
		_build(_jobs[0])
		return false
	if _frames % 6 == 0:
		var image := root.get_texture().get_image()
		image.save_png("%s/%s_%s.png" % [_out, _jobs[0], _mode])
		print("saved ", _jobs[0])
		_canvas.queue_free()
		_canvas = null
		_jobs.pop_front()
	return false


func _build(kind: String) -> void:
	var s := Sheet.new()
	var size := Vector2i(1920, 1000)
	match kind:
		"bust", "headshot":
			var cell := 120 if kind == "bust" else 120
			var cols := 15
			size = Vector2i(cols * (cell + 8) + 8, ceili(SHEET_COUNT / float(cols)) * (cell + 8) + 8)
			for i in SHEET_COUNT:
				var r := Rect2(Vector2(8 + (i % cols) * (cell + 8), 8 + (i / cols) * (cell + 8)), Vector2(cell, cell))
				s.items.append({"rect": r, "visual": _visual(i, 19 + FcPlayerVisual.fnv1a("age%d" % i) % 20), "kind": kind})
		"full":
			size = Vector2i(12 * 150 + 16, 2 * 330 + 24)
			for i in 24:
				var r := Rect2(Vector2(8 + (i % 12) * 150, 8 + (i / 12) * 330), Vector2(142, 322))
				s.items.append({"rect": r, "visual": _visual(i, 19 + FcPlayerVisual.fnv1a("age%d" % i) % 20), "kind": "full"})
		"sizes":
			var px := [24, 32, 48, 64, 96, 128, 192, 256]
			size = Vector2i(1500, 6 * 280 + 20)
			for row in 6:
				var x := 12.0
				for p in px:
					var r := Rect2(Vector2(x, 12 + row * 280), Vector2(p, p))
					s.items.append({"rect": r, "visual": _visual(row * 7 + 3, 19 + (row * 5) % 19), "kind": "bust"})
					x += p + 12
				var hx := x + 20
				for p in [32, 64, 128]:
					s.items.append({"rect": Rect2(Vector2(hx, 12 + row * 280), Vector2(p, p)), "visual": _visual(row * 7 + 3, 19 + (row * 5) % 19), "kind": "headshot"})
					hx += p + 12
		"uniforms":
			size = Vector2i(6 * 250 + 16, 2 * 270 + 16)
			for i in 12:
				var r := Rect2(Vector2(8 + (i % 6) * 250, 8 + (i / 6) * 270), Vector2(240, 260))
				s.items.append({"rect": r, "visual": _visual(7, 27, i), "kind": "bust"})
		"ages":
			size = Vector2i(10 * 150 + 16, 2 * 160 + 16)
			for j in 2:
				for k in 10:
					var r := Rect2(Vector2(8 + k * 150, 8 + j * 160), Vector2(142, 150))
					s.items.append({"rect": r, "visual": _visual(11 + j * 20, 19 + k * 2), "kind": "bust"})
					s.labels.append({"pos": r.position + Vector2(6, 14), "text": "age %d" % (19 + k * 2)})
	s.size = Vector2(size)
	s.custom_minimum_size = Vector2(size)
	root.size = size
	DisplayServer.window_set_size(size)
	root.add_child(s)
	_canvas = s
	_frames = 0
