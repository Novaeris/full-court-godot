class_name FcPlayerFigure
extends RefCounted
## Draws a resolved player visual (FcPlayerVisual.resolve) onto any CanvasItem: the portrait art when there is one (tier 1), the stylised
## procedural figure (tier 2: head, hair, face, facial hair, jersey with the team colours and number) or the monogram (tier 0).
## Everything is drawn from the description alone, so the same description always gives the same picture. `full_body` draws the
## whole player (legs, shorts, shoes) for the showcase stage instead of a head-and-shoulders bust.


static func draw(ci: CanvasItem, rect: Rect2, visual: Dictionary, full_body: bool = false) -> void:
	match int(visual.get("tier", FcPlayerVisual.TIER_PROCEDURAL)):
		FcPlayerVisual.TIER_PORTRAIT:
			var tex := FcDynastyStyle.art_texture(str(visual.get("art_path", "")))
			if tex != null:
				var scale_fit := maxf(rect.size.x / tex.get_width(), rect.size.y / tex.get_height())
				var src_size := rect.size / scale_fit
				ci.draw_texture_rect_region(tex, rect, Rect2((Vector2(tex.get_width(), tex.get_height()) - src_size) / 2.0, src_size))
				return
			_figure(ci, rect, visual, full_body)
		FcPlayerVisual.TIER_MONOGRAM:
			_monogram(ci, rect, visual)
		_:
			_figure(ci, rect, visual, full_body)


static func _figure(ci: CanvasItem, rect: Rect2, visual: Dictionary, full_body: bool) -> void:
	if full_body:
		_full(ci, rect, visual)
	else:
		_bust(ci, rect, visual)


static func _monogram(ci: CanvasItem, rect: Rect2, visual: Dictionary) -> void:
	var font := FcUiFonts.display(700)
	if font == null:
		font = ThemeDB.fallback_font
	var text := str(visual.get("monogram", "?"))
	var fs := int(rect.size.y * 0.45)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(font, rect.position + Vector2((rect.size.x - w) / 2.0, rect.size.y * 0.66), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(visual["uniform"]["secondary"], 0.9))


## Head and shoulders, sized to fill `rect`.
static func _bust(ci: CanvasItem, rect: Rect2, visual: Dictionary) -> void:
	var id: Dictionary = visual["identity"]
	var uniform: Dictionary = visual["uniform"]
	var u := minf(rect.size.x, rect.size.y * 0.9) / 100.0   # one unit = 1% of the figure's width
	var cx := rect.position.x + rect.size.x / 2.0
	var base := rect.end.y
	var shoulder_w: float = (62.0 + float(id["build"]) * 6.0) * u
	# jersey (shoulders and chest), neck, then the head
	var chest_top := base - 34 * u
	ci.draw_polygon(PackedVector2Array([Vector2(cx - shoulder_w, base), Vector2(cx - shoulder_w * 0.92, chest_top + 8 * u), Vector2(cx - 16 * u, chest_top), Vector2(cx + 16 * u, chest_top), Vector2(cx + shoulder_w * 0.92, chest_top + 8 * u), Vector2(cx + shoulder_w, base)]), PackedColorArray([uniform["primary"]]))
	ci.draw_polygon(PackedVector2Array([Vector2(cx - 17 * u, chest_top - 1), Vector2(cx, chest_top + 11 * u), Vector2(cx + 17 * u, chest_top - 1), Vector2(cx + 12 * u, chest_top - 1), Vector2(cx, chest_top + 5 * u), Vector2(cx - 12 * u, chest_top - 1)]), PackedColorArray([uniform["secondary"]]))
	var skin: Color = id["skin_color"]
	ci.draw_rect(Rect2(cx - 9 * u, chest_top - 16 * u, 18 * u, 18 * u), skin.darkened(0.12))
	var head_center := Vector2(cx, chest_top - 36 * u)
	var head_r := 26.0 * u
	ci.draw_set_transform(head_center, 0.0, Vector2(0.86, 1.0))
	ci.draw_circle(Vector2.ZERO, head_r, skin)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_hair(ci, head_center, head_r, str(id["hair"]), id["hair_color"], u)
	_face(ci, head_center, head_r, str(id["face"]), skin, u)
	_facial_hair(ci, head_center, head_r, str(id["facial_hair"]), id["hair_color"], u)
	# the number on the jersey
	if int(uniform["number"]) > 0 or str(uniform["abbreviation"]) != "":
		var font := FcUiFonts.display(700)
		if font == null:
			font = ThemeDB.fallback_font
		var text := str(uniform["number"]) if int(uniform["number"]) > 0 else str(uniform["abbreviation"]).substr(0, 3)
		var fs := int(15 * u)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(font, Vector2(cx - w / 2.0, base - 8 * u), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, uniform["secondary"])


## The whole player standing: legs, shoes, shorts, jersey, head. The bust is drawn at the top of the rectangle.
static func _full(ci: CanvasItem, rect: Rect2, visual: Dictionary) -> void:
	var id: Dictionary = visual["identity"]
	var uniform: Dictionary = visual["uniform"]
	var skin: Color = id["skin_color"]
	var cx := rect.position.x + rect.size.x / 2.0
	var h := rect.size.y
	var u := minf(rect.size.x, h * 0.5) / 100.0
	var upper := Rect2(rect.position.x, rect.position.y, rect.size.x, h * 0.56)
	_bust(ci, upper, visual)
	var hip := upper.end.y
	var leg_w := 15 * u
	var shorts_end := hip + h * 0.16
	ci.draw_rect(Rect2(cx - 24 * u, hip - 4 * u, 48 * u, shorts_end - hip + 4 * u), uniform["primary"])
	ci.draw_rect(Rect2(cx - 24 * u, shorts_end - 3 * u, 48 * u, 3 * u), uniform["secondary"])
	for side in [-1.0, 1.0]:
		var lx: float = cx + side * 11 * u - leg_w / 2.0
		ci.draw_rect(Rect2(lx, shorts_end, leg_w, rect.end.y - shorts_end - 8 * u), skin)
		ci.draw_rect(Rect2(lx - 3 * u, rect.end.y - 10 * u, leg_w + 8 * u, 10 * u), uniform["secondary"])


static func _hair(ci: CanvasItem, c: Vector2, r: float, style: String, color: Color, u: float) -> void:
	match style:
		"bald":
			return
		"short", "fade":
			ci.draw_polygon(_arc_points(c, r * 1.02, PI * 1.08, PI * 1.92, 14, c + Vector2(0, -r * 0.1)), PackedColorArray([color]))
			if style == "fade":
				ci.draw_rect(Rect2(c.x - r * 0.9, c.y - r * 0.15, r * 0.18, r * 0.5), color.lightened(0.0))
				ci.draw_rect(Rect2(c.x + r * 0.72, c.y - r * 0.15, r * 0.18, r * 0.5), color)
		"afro":
			ci.draw_circle(c + Vector2(0, -r * 0.25), r * 1.28, color)
		"curly":
			for i in 9:
				var a := PI * 1.05 + i * PI * 0.9 / 8.0
				ci.draw_circle(c + Vector2(cos(a), sin(a)) * r * 0.98, r * 0.28, color)
			ci.draw_circle(c + Vector2(0, -r * 0.5), r * 0.7, color)
		"braids", "locs":
			ci.draw_polygon(_arc_points(c, r * 1.02, PI * 1.05, PI * 1.95, 14, c + Vector2(0, -r * 0.1)), PackedColorArray([color]))
			# strands hang at the sides of the face (never across it)
			for side in [-1.0, 1.0]:
				for j in 3:
					var x: float = c.x + side * (0.64 + j * 0.15) * r
					ci.draw_line(Vector2(x, c.y - r * 0.55), Vector2(x + side * 1.2 * u, c.y + r * (0.95 if style == "locs" else 0.7)), color, maxf(1.0, 2.5 * u))
		"long":
			ci.draw_polygon(_arc_points(c, r * 1.05, PI * 1.05, PI * 1.95, 14, c + Vector2(0, -r * 0.1)), PackedColorArray([color]))
			ci.draw_rect(Rect2(c.x - r * 1.0, c.y - r * 0.2, r * 0.3, r * 1.5), color)
			ci.draw_rect(Rect2(c.x + r * 0.7, c.y - r * 0.2, r * 0.3, r * 1.5), color)


static func _face(ci: CanvasItem, c: Vector2, r: float, face: String, skin: Color, u: float) -> void:
	var variant := int(face.trim_prefix("face_")) if face.begins_with("face_") else 1
	var eye_gap := r * (0.34 + 0.03 * (variant % 3))
	var eye_y := c.y - r * 0.05 + (variant % 2) * r * 0.04
	var ink := skin.darkened(0.78)
	var eye_r := maxf(1.0, r * (0.07 + 0.01 * (variant % 2)))
	ci.draw_circle(Vector2(c.x - eye_gap, eye_y), eye_r, ink)
	ci.draw_circle(Vector2(c.x + eye_gap, eye_y), eye_r, ink)
	ci.draw_line(Vector2(c.x - eye_gap - r * 0.1, eye_y - r * 0.16), Vector2(c.x - eye_gap + r * 0.1, eye_y - r * 0.17 - (variant % 3) * r * 0.01), ink, maxf(1.0, r * 0.05))
	ci.draw_line(Vector2(c.x + eye_gap - r * 0.1, eye_y - r * 0.17 - (variant % 3) * r * 0.01), Vector2(c.x + eye_gap + r * 0.1, eye_y - r * 0.16), ink, maxf(1.0, r * 0.05))
	ci.draw_arc(Vector2(c.x, c.y + r * 0.38), r * 0.22, 0.25, PI - 0.25, 10, ink, maxf(1.0, r * 0.05), true)


static func _facial_hair(ci: CanvasItem, c: Vector2, r: float, style: String, color: Color, u: float) -> void:
	match style:
		"stubble":
			for i in 14:
				var a := 0.4 + i * (PI - 0.8) / 13.0
				ci.draw_circle(c + Vector2(cos(a) * r * 0.62, sin(a) * r * 0.78), maxf(0.8, r * 0.035), Color(color, 0.55))
		"goatee":
			ci.draw_polygon(PackedVector2Array([c + Vector2(-r * 0.2, r * 0.52), c + Vector2(r * 0.2, r * 0.52), c + Vector2(r * 0.12, r * 0.95), c + Vector2(-r * 0.12, r * 0.95)]), PackedColorArray([color]))
		"beard":
			ci.draw_polygon(_arc_points(c, r * 0.98, 0.15, PI - 0.15, 14, c + Vector2(0, r * 0.4)), PackedColorArray([color]))
			ci.draw_arc(c + Vector2(0, r * 0.4), r * 0.2, 0.35, PI - 0.35, 8, color.lightened(0.15), maxf(1.0, r * 0.05), true)


static func _arc_points(c: Vector2, radius: float, from: float, to: float, steps: int, hub: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array([hub])
	for i in steps + 1:
		var a := from + (to - from) * i / steps
		pts.append(c + Vector2(cos(a), sin(a)) * radius)
	return pts
