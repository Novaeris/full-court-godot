extends SceneTree
## Contact sheet of portraits rendered from the 3D players (FcPlayerRender, M1.6). NOT headless: it needs a renderer.
##   godot_console --path . --script res://tools/portrait_render_sheet.gd -- out=docs/validation/player_m1/portraits.png [count=12]
## It also times the renders and proves the cache: a second request for the same player is served from memory.

var _out := "user://portraits.png"
var _count := 12
var _visuals: Array = []
var _frame := 0
var _started := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() == 2:
			match kv[0]:
				"out": _out = kv[1]
				"count": _count = int(kv[1])
	root.size = Vector2i(512, 512)
	FcPlayerRender.enabled = true
	var teams := [["#2F6FED", "#F4F7FF"], ["#C8352B", "#FFFFFF"], ["#1F8A5B", "#F6E27A"], ["#6B3FA0", "#FFFFFF"]]
	var positions := ["PG", "SG", "SF", "PF", "C"]
	for i in _count:
		var team: Array = teams[i % teams.size()]
		_visuals.append(FcPlayerVisual.resolve({"key": "portrait-%d" % i, "name": "Player %d" % i, "position": positions[i % 5], "jersey": 3 + i * 4,
			"physical": {"height_cm": 183 + (i % 5) * 8, "weight_kg": 78 + (i % 5) * 11}, "team": {"primary": team[0], "secondary": team[1], "abbreviation": "TST"}}))
	_started = Time.get_ticks_msec()
	for v in _visuals:
		FcPlayerRender.texture_for(v)


func _process(_delta: float) -> bool:
	_frame += 1
	var done := true
	for v in _visuals:
		if not FcPlayerRender.cached(v):
			done = false
	if done or _frame > 1500:
		var elapsed := Time.get_ticks_msec() - _started
		var sheet := Image.create_empty(256 * 4, 256 * ceili(_count / 4.0), false, Image.FORMAT_RGBA8)
		for i in _visuals.size():
			var tex := FcPlayerRender.texture_for(_visuals[i])
			var back := Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
			back.fill((_visuals[i]["uniform"]["primary"] as Color).darkened(0.55))
			sheet.blit_rect(back, Rect2i(0, 0, 256, 256), Vector2i((i % 4) * 256, (i / 4) * 256))
			if tex != null:
				var img := tex.get_image()
				img.convert(Image.FORMAT_RGBA8)
				sheet.blend_rect(img, Rect2i(0, 0, 256, 256), Vector2i((i % 4) * 256, (i / 4) * 256))
		sheet.save_png(ProjectSettings.globalize_path(_out) if _out.begins_with("user://") else _out)
		var again := Time.get_ticks_msec()
		for v in _visuals:
			FcPlayerRender.texture_for(v)
		print("rendered %d portraits in %d ms (%d ms to serve them all again from the cache); frames %d; saved %s" % [_visuals.size(), elapsed, Time.get_ticks_msec() - again, _frame, _out])
		quit()
	return false
