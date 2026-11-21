class_name FcPlayerFigure
extends RefCounted
## Draws a resolved player visual (FcPlayerVisual.resolve) onto any CanvasItem: the portrait art when there is one (tier 1), the stylised
## procedural figure (tier 2: head, hair, face, facial hair, jersey with the team colours and number) or the monogram (tier 0).
## Everything is drawn from the description alone, so the same description always gives the same picture. `full_body` draws the
## whole player (legs, shorts, shoes) for the showcase stage instead of a head-and-shoulders bust; `draw_headshot` crops to the head.
##
## Quality rules (docs/VISUAL_IDENTITY_PLAN.md, section 9): one key light from the upper left, a darker lower right, a thin rim light on
## big sizes; detail by size (below about 30 px only the silhouette, hair and jersey; eyes from 30 px; brows, nose, mouth, ears and
## shading from about 56 px; rim light, lips and collar trim from about 90 px) so a small portrait stays clean and the same person at
## every size; head shape, eyes, brows, nose and mouth vary with the key's proportions (FcPlayerVisual.proportions).

const DEFAULTS := {"face_w": 86, "jaw": 0, "eye_gap": 34, "eye_size": 100, "brow": 1, "nose": 1, "mouth": 0, "accessory": 0, "warmth": 0}
## PROTOTYPE SWITCH (docs/PLAYER_VISUAL_PROPOSAL.md): false = the shipped figure. true routes the procedural figure through FcPlayerFigureHd.
## Off by default; only the portrait sheet tool and the screenshot tool turn it on, until the founder approves the new look.
static var hd_enabled: bool = false
const SHADOW := Color(0.04, 0.05, 0.1)
const LIGHT := Color(1, 1, 1)


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


## The same figure cropped to the head and the top of the shoulders, filling `rect` (the owner draws it inside a clipping control).
static func draw_headshot(ci: CanvasItem, rect: Rect2, visual: Dictionary) -> void:
	if int(visual.get("tier", FcPlayerVisual.TIER_PROCEDURAL)) != FcPlayerVisual.TIER_PROCEDURAL:
		draw(ci, rect, visual)
		return
	var grown := Rect2(rect.position + Vector2(-rect.size.x * 0.22, -rect.size.y * 0.06), rect.size * Vector2(1.44, 1.52))
	if hd_enabled:
		FcPlayerFigureHd.bust(ci, grown, visual)
		return
	_bust(ci, grown, visual)


static func _figure(ci: CanvasItem, rect: Rect2, visual: Dictionary, full_body: bool) -> void:
	if hd_enabled:
		if full_body:
			FcPlayerFigureHd.full(ci, rect, visual)
		else:
			FcPlayerFigureHd.bust(ci, rect, visual)
		return
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


# --- the bust ------------------------------------------------------------------------------------------------------------

## Head and shoulders, sized to fill `rect`.
static func _bust(ci: CanvasItem, rect: Rect2, visual: Dictionary) -> void:
	var id: Dictionary = visual["identity"]
	var uniform: Dictionary = visual["uniform"]
	var prop: Dictionary = id.get("proportions", DEFAULTS)
	var px := minf(rect.size.x, rect.size.y * 0.9)
	var u := px / 100.0   # one unit = 1% of the figure's width
	var detail := 0 if px < 30.0 else (1 if px < 56.0 else (2 if px < 90.0 else 3))
	var cx := rect.position.x + rect.size.x / 2.0
	var base := rect.end.y
	var shoulder_w: float = (46.0 + float(id["build"]) * 4.0) * u
	var chest_top := base - 34 * u
	var skin: Color = _warm(id["skin_color"], int(prop.get("warmth", 0)))
	var skin_dark := skin.darkened(0.2)
	# arms (a sleeveless jersey shows them), then the jersey on top
	var arm_w := 7.0 * u
	for side in [-1.0, 1.0]:
		var s: float = side
		var inner := shoulder_w * 0.8
		ci.draw_polygon(PackedVector2Array([Vector2(cx + s * (inner + arm_w), base), Vector2(cx + s * (inner + arm_w), chest_top + 14 * u), Vector2(cx + s * (inner + arm_w * 0.55), chest_top + 7 * u),
			Vector2(cx + s * inner, chest_top + 8 * u), Vector2(cx + s * inner, base)]), PackedColorArray([skin if s < 0.0 else skin.darkened(0.08)]))
	var jw := shoulder_w * 0.8
	var body := PackedVector2Array([Vector2(cx - jw, base), Vector2(cx - jw, chest_top + 12 * u), Vector2(cx - jw * 0.9, chest_top + 4 * u), Vector2(cx - 17 * u, chest_top - 2 * u),
		Vector2(cx + 17 * u, chest_top - 2 * u), Vector2(cx + jw * 0.9, chest_top + 4 * u), Vector2(cx + jw, chest_top + 12 * u), Vector2(cx + jw, base)])
	var primary: Color = uniform["primary"]
	var secondary: Color = uniform["secondary"]
	ci.draw_polygon(body, PackedColorArray([primary]))
	if detail >= 1:   # the jersey is a little darker toward the bottom and on the right (light from the upper left)
		ci.draw_polygon(body, PackedColorArray([Color(SHADOW, 0.0), Color(SHADOW, 0.0), Color(SHADOW, 0.0), Color(SHADOW, 0.12), Color(SHADOW, 0.22), Color(SHADOW, 0.3), Color(SHADOW, 0.3), Color(SHADOW, 0.3)]))
	# neck and the shadow the chin throws on it
	ci.draw_rect(Rect2(cx - 9 * u, chest_top - 17 * u, 18 * u, 19 * u), skin_dark)
	ci.draw_polygon(PackedVector2Array([Vector2(cx - 17 * u, chest_top - 2 * u), Vector2(cx, chest_top + 12 * u), Vector2(cx + 17 * u, chest_top - 2 * u)]), PackedColorArray([skin_dark.darkened(0.1)]))
	# collar: a V in the trim colour
	var collar_w := maxf(1.0, 3.2 * u) if detail >= 1 else maxf(1.0, 2.4 * u)
	ci.draw_polyline(PackedVector2Array([Vector2(cx - 17 * u, chest_top - 2 * u), Vector2(cx, chest_top + 12 * u), Vector2(cx + 17 * u, chest_top - 2 * u)]), secondary, collar_w, true)
	if detail >= 2:   # armhole trim
		for side in [-1.0, 1.0]:
			var s2: float = side
			ci.draw_line(Vector2(cx + s2 * jw, chest_top + 12 * u), Vector2(cx + s2 * jw, base), secondary, maxf(1.0, 2.0 * u))
	# the head
	var head_r := 26.0 * u
	var head_c := Vector2(cx, chest_top - 36 * u)
	var rx := head_r * float(prop.get("face_w", 86)) / 100.0
	var outline := _head_outline(head_c, rx, head_r, int(prop.get("jaw", 0)))
	if detail >= 2:   # ears first, so the head covers their inner edge
		for side in [-1.0, 1.0]:
			var s3: float = side
			_ellipse(ci, head_c + Vector2(s3 * rx * 0.98, head_r * 0.06), rx * 0.17, head_r * 0.2, skin_dark)
	ci.draw_colored_polygon(outline, skin)
	if detail >= 2:
		_shade_head(ci, outline, head_c, rx, head_r, skin)
	_hair(ci, head_c, rx, head_r, str(id["hair"]), id["hair_color"], u, detail)
	if int(prop.get("accessory", 0)) == 1 and detail >= 1:
		_headband(ci, head_c, rx, head_r, secondary, primary)
	_face(ci, head_c, rx, head_r, str(id["face"]), skin, prop, u, detail)
	_facial_hair(ci, head_c, rx, head_r, str(id["facial_hair"]), id["hair_color"], u, detail)
	if detail >= 3:   # a thin rim light along the upper left of the head and the left shoulder
		ci.draw_arc(head_c, head_r * 1.01, PI * 1.02, PI * 1.42, 12, Color(LIGHT, 0.32), maxf(1.0, 1.6 * u), true)
		ci.draw_line(Vector2(cx - shoulder_w * 0.98, chest_top + 17 * u), Vector2(cx - shoulder_w * 0.88, chest_top + 6 * u), Color(LIGHT, 0.3), maxf(1.0, 1.6 * u), true)
	# the number on the jersey
	if int(uniform["number"]) > 0 or str(uniform["abbreviation"]) != "":
		var font := FcUiFonts.display(700)
		if font == null:
			font = ThemeDB.fallback_font
		var text := str(uniform["number"]) if int(uniform["number"]) > 0 else str(uniform["abbreviation"]).substr(0, 3)
		var fs := int(15 * u)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string(font, Vector2(cx - w / 2.0, base - 7 * u), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, secondary)


## The whole player standing: legs, shoes, shorts, jersey, head. The bust is drawn at the top of the rectangle.
static func _full(ci: CanvasItem, rect: Rect2, visual: Dictionary) -> void:
	var id: Dictionary = visual["identity"]
	var uniform: Dictionary = visual["uniform"]
	var prop: Dictionary = id.get("proportions", DEFAULTS)
	var skin: Color = _warm(id["skin_color"], int(prop.get("warmth", 0)))
	var cx := rect.position.x + rect.size.x / 2.0
	var h := rect.size.y
	var u := minf(rect.size.x, h * 0.5) / 100.0
	var upper := Rect2(rect.position.x, rect.position.y, rect.size.x, h * 0.56)
	_bust(ci, upper, visual)
	var hip := upper.end.y
	var leg_w := 17 * u
	var shorts_end := hip + h * 0.16
	var primary: Color = uniform["primary"]
	var secondary: Color = uniform["secondary"]
	ci.draw_rect(Rect2(cx - 24 * u, hip - 4 * u, 48 * u, shorts_end - hip + 4 * u), primary.darkened(0.08))
	ci.draw_rect(Rect2(cx - 24 * u, hip - 4 * u, 10 * u, shorts_end - hip + 4 * u), Color(LIGHT, 0.06))
	ci.draw_rect(Rect2(cx - 24 * u, shorts_end - 3 * u, 48 * u, 3 * u), secondary)
	ci.draw_line(Vector2(cx - 24 * u, hip - 4 * u), Vector2(cx - 24 * u, shorts_end), secondary, maxf(1.0, 1.6 * u))
	ci.draw_line(Vector2(cx + 24 * u, hip - 4 * u), Vector2(cx + 24 * u, shorts_end), secondary, maxf(1.0, 1.6 * u))
	for side in [-1.0, 1.0]:
		var s: float = side
		var lx: float = cx + s * 11 * u - leg_w / 2.0
		ci.draw_rect(Rect2(lx, shorts_end, leg_w, rect.end.y - shorts_end - 8 * u), skin if s < 0.0 else skin.darkened(0.06))
		ci.draw_rect(Rect2(lx + leg_w * 0.72, shorts_end, leg_w * 0.28, rect.end.y - shorts_end - 8 * u), Color(SHADOW, 0.14))
		# shoes: a white upper with a team-colour sole
		ci.draw_rect(Rect2(lx - 3 * u, rect.end.y - 10 * u, leg_w + 8 * u, 7 * u), Color(0.94, 0.95, 0.98))
		ci.draw_rect(Rect2(lx - 3 * u, rect.end.y - 3.5 * u, leg_w + 8 * u, 3.5 * u), secondary)


# --- head parts ----------------------------------------------------------------------------------------------------------

## A head outline polygon: a superellipse for the skull and a chin that is round, square or pointed.
static func _head_outline(c: Vector2, rx: float, ry: float, jaw: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 2.0 if jaw == 0 else (2.7 if jaw == 1 else 2.0)
	var taper := 0.0 if jaw != 2 else 0.3
	for i in 36:
		var t := TAU * float(i) / 36.0
		var ct := cos(t)
		var st := sin(t)
		var x := rx * signf(ct) * pow(absf(ct), 2.0 / n)
		var y := ry * signf(st) * pow(absf(st), 2.0 / (n if st > 0.0 else 2.0))
		if st > 0.0:
			x *= 1.0 - taper * st * st
		pts.append(c + Vector2(x, y))
	return pts


## Soft shading on the head: the lower right in shadow and a faint highlight on the upper left (clipped to the head's own outline).
static func _shade_head(ci: CanvasItem, outline: PackedVector2Array, c: Vector2, rx: float, ry: float, skin: Color) -> void:
	var right := PackedVector2Array([c + Vector2(rx * 0.25, -ry * 1.2), c + Vector2(rx * 1.4, -ry * 1.2), c + Vector2(rx * 1.4, ry * 1.4), c + Vector2(-rx * 0.1, ry * 1.4)])
	for poly in Geometry2D.intersect_polygons(outline, right):
		ci.draw_colored_polygon(poly, Color(SHADOW, 0.14))
	var left := PackedVector2Array([c + Vector2(-rx * 1.4, -ry * 1.4), c + Vector2(-rx * 0.15, -ry * 1.4), c + Vector2(-rx * 0.5, ry * 0.2), c + Vector2(-rx * 1.4, ry * 0.2)])
	for poly in Geometry2D.intersect_polygons(outline, left):
		ci.draw_colored_polygon(poly, Color(LIGHT, 0.07))


static func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var t := TAU * float(i) / 16.0
		pts.append(c + Vector2(cos(t) * rx, sin(t) * ry))
	ci.draw_colored_polygon(pts, color)


static func _warm(skin: Color, warmth: int) -> Color:
	if warmth == 0:
		return skin
	return Color(clampf(skin.r + 0.025 * warmth, 0.0, 1.0), skin.g, clampf(skin.b - 0.02 * warmth, 0.0, 1.0))


static func _hair(ci: CanvasItem, c: Vector2, rx: float, ry: float, style: String, color: Color, u: float, detail: int) -> void:
	var cap := _arc_points(c, 1.0, PI * 1.04, PI * 1.96, 18, c + Vector2(0, -ry * 0.08), rx * 1.04, ry * 1.04)
	var shine := Color(LIGHT, 0.22)
	match style:
		"bald":
			if detail >= 2:   # a highlight on the scalp
				_ellipse(ci, c + Vector2(-rx * 0.28, -ry * 0.72), rx * 0.2, ry * 0.08, Color(LIGHT, 0.16))
		"short", "fade":
			ci.draw_colored_polygon(cap, color)
			if style == "fade":
				var dark := color.darkened(0.0)
				ci.draw_rect(Rect2(c.x - rx * 0.97, c.y - ry * 0.2, rx * 0.2, ry * 0.55), Color(dark, 0.85))
				ci.draw_rect(Rect2(c.x + rx * 0.77, c.y - ry * 0.2, rx * 0.2, ry * 0.55), Color(dark, 0.85))
			if detail >= 2:
				ci.draw_arc(c, ry * 0.94, PI * 1.15, PI * 1.45, 8, shine, maxf(1.0, 1.6 * u), true)
		"afro":
			ci.draw_circle(c + Vector2(0, -ry * 0.25), ry * 1.26, color)
			if detail >= 2:
				for i in 7:
					var a := PI * 1.1 + float(i) * 0.5
					ci.draw_circle(c + Vector2(cos(a), sin(a)) * ry * 1.0 + Vector2(0, -ry * 0.25), ry * 0.14, Color(color.lightened(0.12), 0.6))
		"curly":
			for i in 9:
				var a2 := PI * 1.05 + float(i) * PI * 0.9 / 8.0
				ci.draw_circle(c + Vector2(cos(a2) * rx, sin(a2) * ry) * 1.0, ry * 0.28, color)
			ci.draw_circle(c + Vector2(0, -ry * 0.5), ry * 0.72, color)
		"braids", "locs":
			ci.draw_colored_polygon(cap, color)
			var width := maxf(1.0, (2.5 if style == "braids" else 3.4) * u)
			for side in [-1.0, 1.0]:
				var s: float = side
				for j in 3:
					var x := c.x + s * (0.66 + float(j) * 0.15) * rx
					ci.draw_line(Vector2(x, c.y - ry * 0.55), Vector2(x + s * 1.2 * u, c.y + ry * (0.95 if style == "locs" else 0.7)), color, width, true)
			if detail >= 2:
				ci.draw_arc(c, ry * 0.94, PI * 1.15, PI * 1.45, 8, shine, maxf(1.0, 1.6 * u), true)
		"long":
			ci.draw_colored_polygon(cap, color)
			ci.draw_rect(Rect2(c.x - rx * 1.04, c.y - ry * 0.2, rx * 0.3, ry * 1.5), color)
			ci.draw_rect(Rect2(c.x + rx * 0.74, c.y - ry * 0.2, rx * 0.3, ry * 1.5), color)
			if detail >= 2:
				ci.draw_arc(c, ry * 0.94, PI * 1.15, PI * 1.45, 8, shine, maxf(1.0, 1.6 * u), true)


static func _headband(ci: CanvasItem, c: Vector2, rx: float, ry: float, color: Color, edge: Color) -> void:
	var y := c.y - ry * 0.5
	var half := rx * 0.98 * sqrt(maxf(0.0, 1.0 - pow(0.5, 2.0)))
	ci.draw_rect(Rect2(c.x - half, y - ry * 0.07, half * 2.0, ry * 0.14), color)
	ci.draw_line(Vector2(c.x - half, y + ry * 0.07), Vector2(c.x + half, y + ry * 0.07), edge, maxf(1.0, ry * 0.03))


static func _face(ci: CanvasItem, c: Vector2, rx: float, ry: float, face: String, skin: Color, prop: Dictionary, u: float, detail: int) -> void:
	var variant := int(face.trim_prefix("face_")) if face.begins_with("face_") else 1
	if detail == 0:
		return
	var ink := skin.darkened(0.78)
	var gap := rx * (float(prop.get("eye_gap", 34)) / 100.0 + 0.02 * float(variant % 2))
	var eye_y := c.y - ry * 0.04 + float(variant % 2) * ry * 0.03
	var eye_r := maxf(1.0, ry * 0.075 * float(prop.get("eye_size", 100)) / 100.0)
	for side in [-1.0, 1.0]:
		var s: float = side
		var ex := c.x + s * gap
		if detail >= 2:   # the white of the eye, then the iris
			_ellipse(ci, Vector2(ex, eye_y), eye_r * 1.7, eye_r * 1.05, Color(0.97, 0.97, 0.98))
			ci.draw_circle(Vector2(ex + s * -0.0, eye_y), eye_r * 0.95, ink)
			ci.draw_circle(Vector2(ex - eye_r * 0.3, eye_y - eye_r * 0.3), maxf(0.6, eye_r * 0.28), Color(LIGHT, 0.85))
		else:
			ci.draw_circle(Vector2(ex, eye_y), eye_r, ink)
	if detail < 2:
		return
	# brows: thin, medium or thick, a little lower toward the nose for variants 1 and 2
	var brow_w := maxf(1.0, ry * (0.04 + 0.025 * float(prop.get("brow", 1))))
	for side in [-1.0, 1.0]:
		var s2: float = side
		var inner := Vector2(c.x + s2 * (gap - ry * 0.12), eye_y - ry * (0.2 + 0.01 * float(variant % 3)))
		var outer := Vector2(c.x + s2 * (gap + ry * 0.14), eye_y - ry * 0.2 - ry * 0.02 * float((variant + 1) % 3))
		ci.draw_line(inner, outer, ink, brow_w, true)
	# nose: a soft shadow on the right and a small base
	var nose := int(prop.get("nose", 1))
	var nose_w := ry * (0.10 + 0.04 * float(nose))
	ci.draw_line(Vector2(c.x + rx * 0.02, eye_y + ry * 0.08), Vector2(c.x + rx * 0.06, c.y + ry * 0.22), Color(ink, 0.28), maxf(1.0, ry * 0.05), true)
	ci.draw_arc(Vector2(c.x, c.y + ry * 0.24), nose_w, 0.25, PI - 0.25, 8, Color(ink, 0.5), maxf(1.0, ry * 0.045), true)
	# mouth: smile, neutral or smirk
	var my := c.y + ry * 0.46
	var mw := rx * 0.3
	match int(prop.get("mouth", 0)):
		0:
			ci.draw_arc(Vector2(c.x, my - ry * 0.1), mw * 1.1, 0.35, PI - 0.35, 12, ink, maxf(1.0, ry * 0.05), true)
		1:
			ci.draw_line(Vector2(c.x - mw, my), Vector2(c.x + mw, my), ink, maxf(1.0, ry * 0.05), true)
		_:
			ci.draw_line(Vector2(c.x - mw, my + ry * 0.01), Vector2(c.x + mw * 0.5, my + ry * 0.01), ink, maxf(1.0, ry * 0.05), true)
			ci.draw_line(Vector2(c.x + mw * 0.5, my + ry * 0.01), Vector2(c.x + mw, my - ry * 0.05), ink, maxf(1.0, ry * 0.05), true)
	if detail >= 3:   # lips and a hint of colour in the cheeks
		ci.draw_arc(Vector2(c.x, my + ry * 0.07), mw * 0.7, 0.4, PI - 0.4, 8, Color(skin.darkened(0.3).lerp(Color(0.8, 0.3, 0.3), 0.3), 0.6), maxf(1.0, ry * 0.06), true)
		for side in [-1.0, 1.0]:
			var s3: float = side
			ci.draw_circle(Vector2(c.x + s3 * rx * 0.55, c.y + ry * 0.28), ry * 0.14, Color(0.9, 0.35, 0.3, 0.07))


static func _facial_hair(ci: CanvasItem, c: Vector2, rx: float, ry: float, style: String, color: Color, u: float, detail: int) -> void:
	if style == "none" or detail == 0:
		return
	match style:
		"stubble":
			for i in 14:
				var a := 0.4 + float(i) * (PI - 0.8) / 13.0
				ci.draw_circle(c + Vector2(cos(a) * rx * 0.64, sin(a) * ry * 0.78), maxf(0.8, ry * 0.035), Color(color, 0.5))
		"goatee":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-rx * 0.22, ry * 0.52), c + Vector2(rx * 0.22, ry * 0.52), c + Vector2(rx * 0.13, ry * 0.95), c + Vector2(-rx * 0.13, ry * 0.95)]), color)
			if detail >= 2:   # a moustache above it
				ci.draw_line(Vector2(c.x - rx * 0.3, c.y + ry * 0.36), Vector2(c.x + rx * 0.3, c.y + ry * 0.36), color, maxf(1.0, ry * 0.07), true)
		"beard":
			ci.draw_colored_polygon(_arc_points(c, 1.0, 0.15, PI - 0.15, 16, c + Vector2(0, ry * 0.4), rx * 0.99, ry * 0.99), color)
			if detail >= 2:
				ci.draw_line(Vector2(c.x - rx * 0.3, c.y + ry * 0.37), Vector2(c.x + rx * 0.3, c.y + ry * 0.37), color.lightened(0.1), maxf(1.0, ry * 0.07), true)


## A fan (arc) polygon from a hub, with separate x and y radii.
static func _arc_points(c: Vector2, scale_unit: float, from: float, to: float, steps: int, hub: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array([hub])
	for i in steps + 1:
		var a := from + (to - from) * float(i) / float(steps)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry) * scale_unit)
	return pts
