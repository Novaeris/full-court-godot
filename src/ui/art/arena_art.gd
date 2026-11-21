class_name FcArenaArt
extends RefCounted
## The "arena" backdrop of the Full Court menu, drawn from shapes (no image files): a deep navy hall, two soft spotlight cones from the
## top corners, a warm haze in the middle and a reflective court floor along the bottom with perspective court lines and an orange glow,
## the same mood as the Full Court logo banner. Resolution-independent: it is computed from the rectangle it is given, so it looks the
## same on a phone, a 1080p window and an ultrawide.


static func paint(canvas: CanvasItem, rect: Rect2, accent: Color) -> void:
	var w := rect.size.x
	var h := rect.size.y
	var x0 := rect.position.x
	var y0 := rect.position.y
	# the hall: navy, a touch lighter toward the floor
	canvas.draw_polygon(PackedVector2Array([rect.position, Vector2(x0 + w, y0), Vector2(x0 + w, y0 + h), Vector2(x0, y0 + h)]),
		PackedColorArray([FcUiTokens.BG, FcUiTokens.BG, FcUiTokens.SURFACE, FcUiTokens.SURFACE]))
	# spotlight cones from the top corners: bright at the lamp, gone before the floor
	for side_value in [-1.0, 1.0]:
		var side: float = side_value
		var lamp := Vector2(x0 + (w * 0.06 if side < 0.0 else w * 0.94), y0 - h * 0.02)
		var reach := h * 0.78
		var spread := w * 0.2
		var far_x := lamp.x + (-side) * w * 0.12
		canvas.draw_polygon(PackedVector2Array([lamp + Vector2(-8, 0), lamp + Vector2(8, 0), Vector2(far_x + spread, y0 + reach), Vector2(far_x - spread, y0 + reach)]),
			PackedColorArray([Color(0.75, 0.85, 1.0, 0.1), Color(0.75, 0.85, 1.0, 0.1), Color(0.75, 0.85, 1.0, 0.0), Color(0.75, 0.85, 1.0, 0.0)]))
		canvas.draw_circle(lamp, maxf(3.0, h * 0.006), Color(0.9, 0.95, 1.0, 0.5))
	# a row of small lights along the top like the arena roof in the banner
	for i in 9:
		var lx := x0 + w * (0.12 + 0.095 * i)
		canvas.draw_circle(Vector2(lx, y0 + h * 0.035 + 6.0 * sin(float(i))), maxf(1.5, h * 0.0025), Color(0.8, 0.9, 1.0, 0.22))
	# the floor: starts at 78% of the height
	var horizon := y0 + h * 0.78
	canvas.draw_polygon(PackedVector2Array([Vector2(x0, horizon), Vector2(x0 + w, horizon), Vector2(x0 + w, y0 + h), Vector2(x0, y0 + h)]),
		PackedColorArray([Color(accent, 0.0), Color(accent, 0.0), Color(accent, 0.16), Color(accent, 0.16)]))
	# the reflection of the lights on the floor
	canvas.draw_polygon(PackedVector2Array([Vector2(x0 + w * 0.5, horizon), Vector2(x0 + w * 0.5 + w * 0.22, y0 + h), Vector2(x0 + w * 0.5 - w * 0.22, y0 + h)]),
		PackedColorArray([Color(accent, 0.0), Color(accent, 0.12), Color(accent, 0.12)]))
	# court lines in perspective: the baseline, the key and the centre circle, drawn flattened
	var line := Color(0.9, 0.95, 1.0, 0.16)
	var width := maxf(1.0, h * 0.0016)
	var floor_h := y0 + h - horizon
	canvas.draw_line(Vector2(x0, horizon + floor_h * 0.08), Vector2(x0 + w, horizon + floor_h * 0.08), line, width)
	canvas.draw_set_transform(Vector2(x0 + w * 0.5, horizon + floor_h * 0.62), 0.0, Vector2(1.0, 0.22))
	canvas.draw_arc(Vector2.ZERO, w * 0.16, 0.0, TAU, 64, line, width * 1.6, true)
	canvas.draw_arc(Vector2.ZERO, w * 0.34, PI * 1.08, PI * 1.92, 48, line, width * 1.4, true)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	canvas.draw_line(Vector2(x0 + w * 0.38, horizon + floor_h * 0.08), Vector2(x0 + w * 0.3, y0 + h), line, width)
	canvas.draw_line(Vector2(x0 + w * 0.62, horizon + floor_h * 0.08), Vector2(x0 + w * 0.7, y0 + h), line, width)
