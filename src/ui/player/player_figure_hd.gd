class_name FcPlayerFigureHd
extends RefCounted
## PROTOTYPE (docs/PLAYER_VISUAL_PROPOSAL.md): the high-fidelity procedural player figure. Same contract as FcPlayerFigure (draw a resolved
## FcPlayerVisual onto any CanvasItem into a rectangle; the same visual always gives the same picture) but a much richer picture:
##   - spline-built heads (forehead, cheek, jaw and chin vary), vertex-lit with a key light from the upper left and soft shadows,
##   - almond, round or hooded eyes with iris colour, lids and lashes; tapered arched brows; nose wings and nostrils; shaped lips,
##   - 8 hair styles x 3 variants with a real hairline (it recedes and greys with age), ears, stubble, goatee and beard,
##   - skin undertones, age marks, tattoos, shooting sleeves, chains and studs (FcPlayerTraits: hash-derived, never stored),
##   - shaped shoulders, neck and arms, a jersey with straps, trim, side panels and a number with an outline; a full body with shorts,
##     legs, hands and shoes.
## It reads ONLY the visual that FcPlayerVisual.resolve returns (plus an optional "age"), so identity, saves and the golden test are
## untouched. It is switched on with FcPlayerFigure.hd_enabled (off by default until approved).
## Detail by size (px of the figure's width): 0 below 30 (silhouette, hair, jersey), 1 below 56 (eyes, soft shading), 2 below 90
## (all features), 3 below 150 (fine shading, age marks, trim), 4 above (hero: pores of light, lashes, crease lines).

## Large portraits stack more layers in a soft shadow so it has no visible bands (set per draw from the detail level).
static var steps_multiplier: int = 1
const LIGHT_DIR := Vector2(-0.55, -0.83)
const SHADOW := Color(0.05, 0.05, 0.1)
const WHITE := Color(1, 1, 1)


# --- entry points ---------------------------------------------------------------------------------------------------------

## Head and shoulders filling `rect` (the same layout contract as FcPlayerFigure._bust).
static func bust(ci: CanvasItem, rect: Rect2, visual: Dictionary) -> void:
	var px := minf(rect.size.x, rect.size.y * 0.9)
	var u := px / 100.0
	var c := _ctx(visual, px)
	var cx := rect.position.x + rect.size.x / 2.0
	_character(ci, cx, rect.end.y - 34.0 * u, u, 34.0 * u, 0.0, c)


## The whole player standing, filling `rect`.
static func full(ci: CanvasItem, rect: Rect2, visual: Dictionary) -> void:
	var u := minf(rect.size.y / 264.0, rect.size.x / 108.0)
	var c := _ctx(visual, u * 100.0)
	var cx := rect.position.x + rect.size.x / 2.0
	var chest_top := rect.position.y + rect.size.y - (264.0 - 65.0) * u
	_legs(ci, cx, chest_top, u, c)
	_character(ci, cx, chest_top, u, 62.0 * u, 36.0 * u, c)


## A soft spotlight behind a figure in the team colour (for hero shots; the small portraits keep their flat well).
static func backdrop(ci: CanvasItem, rect: Rect2, visual: Dictionary) -> void:
	var col: Color = visual["uniform"]["primary"]
	ci.draw_rect(rect, col.darkened(0.7))
	var centre := rect.position + rect.size * Vector2(0.5, 0.42)
	for i in 8:
		var f := 1.0 - float(i) / 8.0
		ci.draw_circle(centre, rect.size.x * 0.62 * f, Color(col.lightened(0.1), 0.07))


# --- context ----------------------------------------------------------------------------------------------------------------

static func _ctx(visual: Dictionary, px: float) -> Dictionary:
	var id: Dictionary = visual["identity"]
	var prop: Dictionary = id.get("proportions", FcPlayerFigure.DEFAULTS)
	var key := str(visual.get("key", ""))
	var t := FcPlayerTraits.of(key, int(visual.get("age", 0)))
	steps_multiplier = 3 if px >= 150.0 else (2 if px >= 90.0 else 1)
	return {
		"key": key, "id": id, "prop": prop, "t": t, "u": px / 100.0,
		"detail": 0 if px < 30.0 else (1 if px < 56.0 else (2 if px < 90.0 else (3 if px < 150.0 else 4))),
		"skin": FcPlayerTraits.skin(id["skin_color"], int(prop.get("warmth", 0)), int(t["undertone"])),
		"hair": FcPlayerTraits.greyed(id["hair_color"], int(t["grey"])),
		"uniform": visual["uniform"],
	}


static func _rnd(key: String, i: int) -> float:
	return float(FcPlayerVisual.fnv1a("%s|r%d" % [key, i]) % 10000) / 10000.0


# --- geometry helpers -------------------------------------------------------------------------------------------------------

static func _spline(pts: Array, sub: int = 4, closed: bool = false) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	var segs := n if closed else n - 1
	for i in segs:
		var p0: Vector2 = pts[(i - 1 + n) % n] if closed else pts[maxi(i - 1, 0)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[(i + 1) % n]
		var p3: Vector2 = pts[(i + 2) % n] if closed else pts[mini(i + 2, n - 1)]
		for s in sub:
			var t := float(s) / float(sub)
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	if not closed:
		out.append(pts[n - 1])
	return out


## Mirrors a right-side list of (x, y) pairs (x >= 0) into a closed ring: down the right, back up the left.
static func _ring(right: Array) -> Array:
	var ring: Array = []
	for p in right:
		ring.append(p)
	for i in range(right.size() - 1, -1, -1):
		var p: Vector2 = right[i]
		if absf(p.x) > 0.001:
			ring.append(Vector2(-p.x, p.y))
	return ring


static func _map(pts: Variant, origin: Vector2, sx: float, sy: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(origin + Vector2(p.x * sx, p.y * sy))
	return out


static func _ellipse_pts(c: Vector2, rx: float, ry: float, n: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, color: Color, n: int = 20) -> void:
	ci.draw_colored_polygon(_ellipse_pts(c, rx, ry, n), color)


## A soft blob: stacked ellipses whose combined opacity at the middle is color.a (cheap shading, no textures).
static func _soft(ci: CanvasItem, c: Vector2, rx: float, ry: float, color: Color, base_steps: int = 4) -> void:
	var steps := base_steps * steps_multiplier
	var layer := 1.0 - pow(1.0 - color.a, 1.0 / float(steps))
	for i in steps:
		var f := lerpf(1.0, 0.3, float(i) / float(maxi(steps - 1, 1)))
		_ellipse(ci, c, rx * f, ry * f, Color(color.r, color.g, color.b, layer), 16)


## Fills a polygon with a LINEAR light-to-dark gradient along LIGHT_DIR (exact, because the colour is linear in position).
static func _lit(ci: CanvasItem, pts: PackedVector2Array, base: Color, lighten: float = 0.12, darken: float = 0.24) -> void:
	if pts.size() < 3:
		return
	var lo := 1.0e9
	var hi := -1.0e9
	for p in pts:
		var d := p.dot(LIGHT_DIR)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	var colors := PackedColorArray()
	var bright := base.lightened(lighten)
	var dark := _shadow_of(base, darken)
	for p in pts:
		var f := 0.5 if hi - lo < 0.001 else 1.0 - (p.dot(LIGHT_DIR) - lo) / (hi - lo)   # 1 at the lit side
		colors.append(dark.lerp(bright, f))
	ci.draw_polygon(pts, colors)


static func _shadow_of(base: Color, amount: float) -> Color:
	return Color(base.r * (1.0 - amount), base.g * (1.0 - amount * 1.18), base.b * (1.0 - amount * 1.1))


## Fills a polygon only if it can be triangulated (tiny or degenerate shapes, like lips at 24 px, are skipped instead of logging an error).
static func _fill(ci: CanvasItem, pts: PackedVector2Array, color: Color) -> void:
	if pts.size() >= 3 and not Geometry2D.triangulate_polygon(pts).is_empty():
		ci.draw_colored_polygon(pts, color)


static func _poly_line(ci: CanvasItem, pts: PackedVector2Array, color: Color, width: float) -> void:
	if pts.size() >= 2:
		ci.draw_polyline(pts, color, maxf(1.0, width), true)


## A tapered stroke along `pts`: width goes from w0 to w1 (brows, lashes, locs).
static func _taper(ci: CanvasItem, pts: PackedVector2Array, w0: float, w1: float, color: Color) -> void:
	var n := pts.size()
	if n < 2:
		return
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in n:
		var dir := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var w := lerpf(w0, w1, float(i) / float(n - 1)) * 0.5
		left.append(pts[i] + nrm * w)
		right.append(pts[i] - nrm * w)
	right.reverse()
	left.append_array(right)
	_fill(ci, left, color)


# --- the character ----------------------------------------------------------------------------------------------------------

## Body then head. (cx, top) is the base of the neck's shoulder line; torso_len is how far the jersey hangs; arm_len extra arm below it.
static func _character(ci: CanvasItem, cx: float, top: float, u: float, torso_len: float, arm_len: float, c: Dictionary) -> void:
	var t: Dictionary = c["t"]
	var detail: int = c["detail"]
	var skin: Color = c["skin"]
	var o := Vector2(cx, top)
	var build := float(c["id"]["build"])
	var sw := 0.93 + 0.07 * build
	var so := (1.0 - float(t["slope"])) * 1.6   # square shoulders sit higher
	var nw := 8.3 + 1.5 * float(t["neck"]) + 0.5 * build
	var tlen := torso_len / u
	var alen := arm_len / u
	# neck (in shadow under the head) and the yoke of skin around it
	var neck := _map([Vector2(-nw, -26), Vector2(nw, -26), Vector2(nw + 1.5, -6), Vector2(nw + 6.0, 2), Vector2(-nw - 6.0, 2), Vector2(-nw - 1.5, -6)], o, u, u)
	_lit(ci, neck, skin.darkened(0.1), 0.04, 0.2)
	# arms: skin from the shoulder; a tattoo, a shooting sleeve; hands for the full body
	for side in [-1.0, 1.0]:
		_arm(ci, o, u, side, sw, so, tlen, alen, c)
	# the jersey
	_jersey(ci, o, u, sw, so, tlen, c)
	# a chain sits on the jersey collar
	if int(t["chain"]) == 1 and detail >= 2:
		var chain := PackedVector2Array()
		for i in 9:
			var a := float(i) / 8.0
			chain.append(o + Vector2(lerpf(-11.0, 11.0, a), -5.0 + 17.0 * (1.0 - pow(2.0 * a - 1.0, 2.0))) * u)
		_poly_line(ci, chain, Color("D8C079"), 1.3 * u)
	# the shadow the chin throws on the neck and collar
	if detail >= 2:
		_soft(ci, o + Vector2(0, -8) * u, 13 * u, 6 * u, Color(SHADOW, 0.35), 4)
	_head(ci, o + Vector2(0, -38) * u, 26.0 * u, c)


static func _arm(ci: CanvasItem, o: Vector2, u: float, side: float, sw: float, so: float, tlen: float, alen: float, c: Dictionary) -> void:
	var t: Dictionary = c["t"]
	var detail: int = c["detail"]
	var skin: Color = c["skin"]
	var uni: Dictionary = c["uniform"]
	var a_end := maxf(tlen, 34.0) + alen
	var pts: Array = [Vector2(24 * sw, -8 + so), Vector2(36 * sw, -3 + so), Vector2(43.5 * sw, 5 + so), Vector2(45.5 * sw, 18), Vector2(44.5 * sw, a_end * 0.55 + 6), Vector2(41 * sw, a_end), Vector2(32 * sw, a_end), Vector2(31 * sw, 24), Vector2(27 * sw, 4)]
	var poly := PackedVector2Array()
	for p in _spline(pts, 3, true):
		poly.append(o + Vector2(p.x * side, p.y) * u)
	if side > 0.0:
		poly.reverse()
	_lit(ci, poly, skin.darkened(0.04) if side < 0.0 else skin.darkened(0.1), 0.1, 0.22)
	if detail >= 3:   # deltoid highlight and the crease where the arm meets the body
		_soft(ci, o + Vector2(side * 39.0 * sw, 9 + so) * u, 3.6 * u, 6.5 * u, Color(WHITE, 0.1), 3)
	if (int(t["tattoo"]) == 0 and side < 0.0) or (int(t["tattoo"]) == 1 and side > 0.0):
		if detail >= 2:
			var ink := Color(0.12, 0.16, 0.3, 0.55)
			for j in 3:
				var y0 := 8.0 + float(j) * 5.5
				var band := PackedVector2Array()
				for k in 7:
					var xx := lerpf(36.0, 45.0, float(k) / 6.0) * sw
					band.append(o + Vector2(xx * side, y0 + sin(float(k) * 1.2 + float(j)) * 1.4) * u)
				_poly_line(ci, band, ink, 1.6 * u)
	if int(t["sleeve"]) == 1 and ((FcPlayerVisual.fnv1a(str(c["key"]) + "|sleeve_side") & 1) == 0) == (side < 0.0):
		var sleeve := PackedVector2Array()
		for p in [Vector2(35 * sw, -2 + so), Vector2(44 * sw, 4 + so), Vector2(46.5 * sw, 18), Vector2(45.5 * sw, a_end * 0.62 + 8), Vector2(34 * sw, a_end * 0.62 + 8), Vector2(31 * sw, 20)]:
			sleeve.append(o + Vector2(p.x * side, p.y) * u)
		if side > 0.0:
			sleeve.reverse()
		_lit(ci, sleeve, uni["secondary"], 0.06, 0.2)
		ci.draw_line(o + Vector2(side * 34.0 * sw, a_end * 0.62 + 8) * u, o + Vector2(side * 45.5 * sw, a_end * 0.62 + 8) * u, Color(uni["primary"], 0.9), maxf(1.0, 1.8 * u), true)
	if alen > 0.0:   # a hand
		_lit(ci, _ellipse_pts(o + Vector2(side * 36.5 * sw, a_end + 6) * u, 5.6 * u, 8.2 * u, 14), skin.darkened(0.06), 0.08, 0.2)


static func _jersey(ci: CanvasItem, o: Vector2, u: float, sw: float, so: float, tlen: float, c: Dictionary) -> void:
	var detail: int = c["detail"]
	var uni: Dictionary = c["uniform"]
	var primary: Color = uni["primary"]
	var secondary: Color = uni["secondary"]
	var right: Array = [Vector2(0, 12.5), Vector2(6.5, 3.5), Vector2(12.5, -7), Vector2(20 * sw, -5.5 + so), Vector2(28 * sw, -3 + so), Vector2(29 * sw, 7), Vector2(26.5 * sw, 17), Vector2(25.2 * sw, 27), Vector2(25.6 * sw, minf(34.0, tlen)), Vector2(26.4 * sw, tlen)]
	# the polygon runs: V bottom, right neck, strap, armhole, hem right, hem left, armhole left, strap left, neck left
	var ring := PackedVector2Array()
	for p in right:
		ring.append(o + p * u)
	for i in range(right.size() - 1, -1, -1):
		var p: Vector2 = right[i]
		if absf(p.x) > 0.001:
			ring.append(o + Vector2(-p.x, p.y) * u)
	_lit(ci, ring, primary, 0.1, 0.26)
	if detail >= 1:   # darker toward the right and the bottom: the same key light as the face
		_soft(ci, o + Vector2(14, tlen * 0.8) * u, 18 * u, tlen * 0.35 * u, Color(SHADOW, 0.16), 3)
	if detail >= 2:
		# side panels in the trim colour, a darker band at the hem
		for side in [-1.0, 1.0]:
			var s: float = side
			ci.draw_line(o + Vector2(s * 25.2 * sw, 24) * u, o + Vector2(s * 26.2 * sw, tlen) * u, Color(secondary, 0.92), maxf(1.0, 2.2 * u), true)
		# armhole trim
		var arm_trim := PackedVector2Array()
		for p in [Vector2(28 * sw, -3 + so), Vector2(29 * sw, 7), Vector2(26.5 * sw, 17), Vector2(25.2 * sw, 27)]:
			arm_trim.append(o + p * u)
		_poly_line(ci, arm_trim, secondary, 1.7 * u)
		var arm_trim_l := PackedVector2Array()
		for p in [Vector2(-28 * sw, -3 + so), Vector2(-29 * sw, 7), Vector2(-26.5 * sw, 17), Vector2(-25.2 * sw, 27)]:
			arm_trim_l.append(o + p * u)
		_poly_line(ci, arm_trim_l, secondary, 1.7 * u)
	# neckline trim: a double V, trim colour outside and a dark line inside
	var neck_r := PackedVector2Array([o + Vector2(12.5, -7) * u, o + Vector2(6.5, 3.5) * u, o + Vector2(0, 12.5) * u, o + Vector2(-6.5, 3.5) * u, o + Vector2(-12.5, -7) * u])
	_poly_line(ci, neck_r, secondary, (3.0 if detail >= 2 else 2.2) * u)
	if detail >= 3:
		_poly_line(ci, neck_r, Color(SHADOW, 0.35), 0.9 * u)
		for i in 3:   # a few soft folds across the chest
			var fy := 14.0 + float(i) * 8.0 + _rnd(c["key"], i) * 3.0
			ci.draw_line(o + Vector2(-17 + i * 3, fy) * u, o + Vector2(-5 + i * 5, fy + 3) * u, Color(SHADOW, 0.1), maxf(1.0, 1.3 * u), true)
	# the number
	if int(uni["number"]) > 0 or str(uni["abbreviation"]) != "":
		var font := FcUiFonts.display(700)
		if font == null:
			font = ThemeDB.fallback_font
		var text := str(uni["number"]) if int(uni["number"]) > 0 else str(uni["abbreviation"]).substr(0, 3)
		var fs := int(16 * u)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := o + Vector2(0, 29.5 * u) - Vector2(w / 2.0, 0)
		if detail >= 2:
			ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(2.4 * u)), Color(primary.darkened(0.5), 0.9))
		ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, secondary)


static func _legs(ci: CanvasItem, cx: float, top: float, u: float, c: Dictionary) -> void:
	var skin: Color = c["skin"]
	var uni: Dictionary = c["uniform"]
	var primary: Color = uni["primary"]
	var secondary: Color = uni["secondary"]
	var detail: int = c["detail"]
	var hip := top + 58.0 * u
	var shorts_end := top + 104.0 * u
	var floor_y := top + 199.0 * u
	for side in [-1.0, 1.0]:
		var s: float = side
		var thigh_x := cx + s * 10.0 * u
		# a leg: thigh, knee, calf, ankle as a smooth outline
		var outer: Array = [Vector2(22, 100), Vector2(22.5, 126), Vector2(19.5, 150), Vector2(20.5, 170), Vector2(18.5, 196), Vector2(15.5, 220)]
		var inner: Array = [Vector2(4, 220), Vector2(2.5, 196), Vector2(1.8, 170), Vector2(1.5, 150), Vector2(1.5, 126), Vector2(2, 100)]
		var poly := PackedVector2Array()
		for side_list in [outer, inner]:
			var mapped: Array = []
			for p in side_list:
				mapped.append(Vector2(p.x * s * 1.08, 100.0 + (p.y - 100.0) * 0.82))
			for p in _spline(mapped, 3, false):
				poly.append(Vector2(cx + p.x * u, top + p.y * u))
		_lit(ci, poly, skin.darkened(0.03 if s < 0.0 else 0.08), 0.04, 0.14)
		if detail >= 3:   # kneecap and calf highlights
			_soft(ci, Vector2(thigh_x - s * 1.5 * u, top + 123 * u), 4.5 * u, 4 * u, Color(WHITE, 0.08), 3)
			_soft(ci, Vector2(thigh_x + s * 1.5 * u, top + 148 * u), 3.8 * u, 8 * u, Color(WHITE, 0.07), 3)
		# sock and shoe
		var sock_top := top + 179.0 * u
		ci.draw_rect(Rect2(thigh_x - 9.5 * u, sock_top, 19 * u, 18 * u), Color(0.95, 0.96, 0.98))
		ci.draw_rect(Rect2(thigh_x - 9.5 * u, sock_top + 3 * u, 19 * u, 2.4 * u), secondary)
		var shoe := PackedVector2Array([Vector2(thigh_x - 9 * u, floor_y - 3 * u), Vector2(thigh_x + 9 * u, floor_y - 3 * u), Vector2(thigh_x + 12 * u, floor_y + 2 * u), Vector2(thigh_x + 12.5 * u, floor_y + 7 * u), Vector2(thigh_x - 12.5 * u, floor_y + 7 * u), Vector2(thigh_x - 12 * u, floor_y + 2 * u)])
		_lit(ci, shoe, Color(0.95, 0.96, 0.99), 0.0, 0.2)
		ci.draw_rect(Rect2(thigh_x - 10.5 * u, floor_y + 5.2 * u, 24 * u, 3.4 * u), secondary)
		if detail >= 3:
			ci.draw_line(Vector2(thigh_x - 4 * u, floor_y), Vector2(thigh_x + 6 * u, floor_y + 2 * u), primary, maxf(1.0, 2.0 * u), true)
	# shorts: wide, hanging past the knee line a little, with a waistband and a side stripe
	var shorts := PackedVector2Array([Vector2(cx - 27 * u, hip - 4 * u), Vector2(cx + 27 * u, hip - 4 * u), Vector2(cx + 31 * u, shorts_end + 4 * u), Vector2(cx + 3 * u, shorts_end + 7 * u), Vector2(cx, shorts_end - 6 * u), Vector2(cx - 3 * u, shorts_end + 7 * u), Vector2(cx - 31 * u, shorts_end + 4 * u)])
	_lit(ci, shorts, primary.darkened(0.06), 0.1, 0.26)
	ci.draw_rect(Rect2(cx - 27 * u, hip - 4 * u, 54 * u, 4.2 * u), secondary)
	if detail >= 2:
		for side in [-1.0, 1.0]:
			var s2: float = side
			ci.draw_line(Vector2(cx + s2 * 29 * u, hip), Vector2(cx + s2 * 31 * u, shorts_end + 4 * u), secondary, maxf(1.0, 3.0 * u), true)
		ci.draw_line(Vector2(cx - 31 * u, shorts_end + 3.2 * u), Vector2(cx - 4 * u, shorts_end + 6 * u), Color(secondary, 0.85), maxf(1.0, 1.4 * u), true)
		ci.draw_line(Vector2(cx + 4 * u, shorts_end + 6 * u), Vector2(cx + 31 * u, shorts_end + 3.2 * u), Color(secondary, 0.85), maxf(1.0, 1.4 * u), true)


# --- the head ---------------------------------------------------------------------------------------------------------------

static func _head(ci: CanvasItem, hc: Vector2, ry: float, c: Dictionary) -> void:
	var t: Dictionary = c["t"]
	var prop: Dictionary = c["prop"]
	var id: Dictionary = c["id"]
	var detail: int = c["detail"]
	var u: float = c["u"]
	var skin: Color = c["skin"]
	var rx := ry * (float(prop.get("face_w", 86)) + 1.5 * float(t["cheek"])) / 100.0
	var jaw := int(prop.get("jaw", 0))
	var jaw_x: float = [0.82, 0.93, 0.66][jaw] + 0.02 * float(t["cheek"])
	var chin_x: float = [0.42, 0.58, 0.26][jaw] + 0.07 * float(int(t["chin"]) - 1)
	var cheek_x := 0.93 + 0.035 * float(t["cheek"])
	var chin_y := 0.985 if jaw == 1 else 1.0
	var ring := _ring([Vector2(0, -1.0), Vector2(0.52, -0.97), Vector2(0.86, -0.8), Vector2(0.985, -0.45), Vector2(1.0, -0.05), Vector2(cheek_x, 0.34), Vector2(jaw_x, 0.70), Vector2(chin_x, 0.94 * chin_y), Vector2(0.0, chin_y)])
	var outline := _map(_spline(ring, 4, true), hc, rx, ry)
	var style := str(id["hair"])
	var hair: Color = c["hair"]
	# back hair first (it frames the head from behind)
	_hair_back(ci, hc, rx, ry, style, int(t["hair_variant"]), hair, u, detail, c)
	# ears
	if detail >= 1:
		var ear_r := ry * (0.19 + 0.025 * float(t["ear"]))
		for side in [-1.0, 1.0]:
			var s: float = side
			var ec := hc + Vector2(s * rx * 0.985, ry * 0.08)
			_ellipse(ci, ec, ear_r * 0.62, ear_r, skin.darkened(0.12), 14)
			if detail >= 2:
				_ellipse(ci, ec + Vector2(s * ear_r * 0.06, 0), ear_r * 0.32, ear_r * 0.62, _shadow_of(skin, 0.3), 12)
			if int(t["earring"]) == 1 and detail >= 2:
				ci.draw_circle(ec + Vector2(0, ear_r * 0.95), maxf(1.0, ry * 0.045), Color("E8E4D8"))
	_lit(ci, outline, skin, 0.1, 0.2)
	if detail >= 2:
		_shade_face(ci, hc, rx, ry, skin, t)
	# facial hair (the beard sits under the mouth and nose)
	_facial_hair_back(ci, hc, rx, ry, str(id["facial_hair"]), hair, outline, detail)
	if detail >= 1:
		_features(ci, hc, rx, ry, skin, prop, t, hair, u, detail)
	_facial_hair_front(ci, hc, rx, ry, str(id["facial_hair"]), hair, detail)
	_hair_front(ci, hc, rx, ry, style, int(t["hair_variant"]), hair, u, detail, c)
	if int(prop.get("accessory", 0)) == 1 and detail >= 1:
		_headband(ci, hc, rx, ry, c["uniform"]["secondary"], c["uniform"]["primary"])


static func _shade_face(ci: CanvasItem, hc: Vector2, rx: float, ry: float, skin: Color, t: Dictionary) -> void:
	var shadow := _shadow_of(skin, 0.32)
	# the lower right of the face turns away from the light
	_soft(ci, hc + Vector2(rx * 0.62, ry * 0.5), rx * 0.5, ry * 0.62, Color(shadow, 0.3), 4)
	# a highlight on the forehead and the upper cheek on the lit side
	_soft(ci, hc + Vector2(-rx * 0.28, -ry * 0.55), rx * 0.42, ry * 0.2, Color(WHITE, 0.16), 3)
	_soft(ci, hc + Vector2(-rx * 0.5, ry * 0.2), rx * 0.2, ry * 0.14, Color(WHITE, 0.1), 3)
	# warm cheeks
	for side in [-1.0, 1.0]:
		var s: float = side
		_soft(ci, hc + Vector2(s * rx * 0.55, ry * 0.3), rx * 0.24, ry * 0.15, Color(0.9, 0.38, 0.32, 0.1), 3)
	# the jaw line and under the chin
	_soft(ci, hc + Vector2(0, ry * 1.0), rx * 0.6, ry * 0.12, Color(shadow, 0.3), 3)


static func _features(ci: CanvasItem, hc: Vector2, rx: float, ry: float, skin: Color, prop: Dictionary, t: Dictionary, hair: Color, u: float, detail: int) -> void:
	var ink := skin.darkened(0.8)
	var gap := rx * (float(prop.get("eye_gap", 34)) / 100.0 + 0.012)
	var ey := hc.y - ry * 0.03
	var esize := float(prop.get("eye_size", 100)) / 100.0
	var ew := ry * 0.2 * esize
	var eh: float = ry * [0.082, 0.1, 0.07][int(t["eye_shape"])] * (0.9 + 0.1 * esize)
	var tilt := float(t["eye_tilt"])
	for side in [-1.0, 1.0]:
		var s: float = side
		var ex := hc.x + s * gap
		if detail == 1:
			ci.draw_circle(Vector2(ex, ey), maxf(1.0, ry * 0.07), ink)
			continue
		# the eye shape: an upper and a lower lid curve between two corners
		var inner := Vector2(ex - s * ew, ey + ew * 0.1 * tilt)
		var outer := Vector2(ex + s * ew, ey - ew * 0.16 * tilt - ew * 0.05)
		var upper := PackedVector2Array()
		var lower := PackedVector2Array()
		for i in 9:
			var f := float(i) / 8.0
			var base := inner.lerp(outer, f)
			var arc := sin(f * PI)
			upper.append(base + Vector2(0, -eh * 1.25 * arc * (1.0 + 0.2 * (1.0 - f))))
			lower.append(base + Vector2(0, eh * 0.85 * arc))
		var shape := PackedVector2Array(upper)
		var lower_rev := PackedVector2Array(lower)
		lower_rev.reverse()
		shape.append_array(lower_rev)
		_fill(ci, shape, Color(0.96, 0.95, 0.94).lerp(skin, 0.08))
		# the iris, clipped to the eye shape
		var iris_center := Vector2(ex - s * ew * 0.04, ey - eh * 0.05)
		var iris_color: Color = FcPlayerTraits.IRIS_COLORS[int(t["iris"])]
		var iris_r: float = eh * 1.28
		for poly in Geometry2D.intersect_polygons(_ellipse_pts(iris_center, iris_r, iris_r, 14), shape):
			ci.draw_colored_polygon(poly, iris_color)
			if detail >= 3:
				ci.draw_colored_polygon(poly, Color(WHITE, 0.0))
		for poly in Geometry2D.intersect_polygons(_ellipse_pts(iris_center, iris_r * 0.5, iris_r * 0.5, 10), shape):
			ci.draw_colored_polygon(poly, Color(0.02, 0.02, 0.03))
		ci.draw_circle(iris_center + Vector2(-iris_r * 0.32, -iris_r * 0.38), maxf(0.7, iris_r * 0.24), Color(WHITE, 0.9))
		# upper lid line (heavy), lash flick at the outer corner, lower lid (faint)
		_poly_line(ci, upper, ink, maxf(1.0, ry * (0.05 if int(t["eye_shape"]) != 2 else 0.062)))
		ci.draw_line(upper[8], upper[8] + Vector2(s * ew * 0.22, -ew * 0.12), ink, maxf(1.0, ry * 0.04), true)
		_poly_line(ci, lower, Color(ink, 0.3), maxf(1.0, ry * 0.02))
		if detail >= 3:   # the lid crease and the shadow of the socket
			var crease := PackedVector2Array()
			for i in 9:
				var f2 := float(i) / 8.0
				crease.append(inner.lerp(outer, f2) + Vector2(0, -eh * (1.8 if int(t["eye_shape"]) != 2 else 1.4) * sin(f2 * PI) - eh * 0.2))
			_poly_line(ci, crease, Color(skin.darkened(0.45), 0.26), maxf(1.0, ry * 0.014))
			_soft(ci, Vector2(ex, ey - eh * 1.5), ew * 1.2, eh * 1.1, Color(_shadow_of(skin, 0.4), 0.18), 3)
			if int(t["lines"]) >= 2:   # under-eye bags and crow's feet
				_poly_line(ci, PackedVector2Array([Vector2(ex - s * ew * 0.6, ey + eh * 2.0), Vector2(ex, ey + eh * 2.5), Vector2(ex + s * ew * 0.8, ey + eh * 2.0)]), Color(ink, 0.12), maxf(1.0, ry * 0.02))
			if int(t["lines"]) >= 3:
				for k in 2:
					ci.draw_line(outer + Vector2(s * ew * 0.2, 0), outer + Vector2(s * ew * 0.7, (float(k) - 0.5) * ew * 0.6), Color(ink, 0.15), maxf(1.0, ry * 0.015), true)
		# the brow: a tapered, arched stroke
		var thick := ry * (0.034 + 0.026 * float(prop.get("brow", 1)))
		var arch := float(t["brow_arch"])
		var by := ey - ry * 0.2
		var peak := by - ry * (0.04 + 0.025 * arch)
		var brow := _spline([Vector2(ex - s * ew * 1.15, by + ry * 0.015), Vector2(ex - s * ew * 0.3, peak + ry * 0.01), Vector2(ex + s * ew * 0.55, peak), Vector2(ex + s * ew * 1.4, by + ry * 0.04)], 4)
		_taper(ci, brow, thick * 1.1, thick * 0.35, Color(hair.darkened(0.12), 0.92))
	if detail < 2:
		return
	# nose: bridge shadow, wings, nostrils and a tip highlight
	var nw := ry * (0.105 + 0.032 * float(t["nose_w"]) + 0.012 * float(prop.get("nose", 1)))
	var nbase := hc.y + ry * 0.245
	_soft(ci, Vector2(hc.x + rx * 0.1, hc.y + ry * 0.05), rx * 0.07, ry * 0.2, Color(_shadow_of(skin, 0.35), 0.22), 3)
	_soft(ci, Vector2(hc.x, nbase + ry * 0.05), nw * 1.2, ry * 0.05, Color(_shadow_of(skin, 0.4), 0.2), 3)
	for side in [-1.0, 1.0]:
		var s2: float = side
		var wing := PackedVector2Array()
		for i in 6:
			var a := lerpf(-0.4, 1.3, float(i) / 5.0)
			wing.append(Vector2(hc.x + s2 * (nw * 0.62 + cos(a * 2.0) * nw * 0.38), nbase + sin(a) * ry * 0.06 - ry * 0.03))
		_poly_line(ci, wing, Color(ink, 0.34), maxf(1.0, ry * 0.032))
		_ellipse(ci, Vector2(hc.x + s2 * nw * 0.42, nbase + ry * 0.035), nw * 0.2, ry * 0.022, Color(ink, 0.55), 8)
	_soft(ci, Vector2(hc.x - rx * 0.03, nbase - ry * 0.1), nw * 0.4, ry * 0.07, Color(WHITE, 0.16), 3)
	# mouth: lips and a line whose corners are lifted for a smile
	var my := hc.y + ry * 0.5
	var mw := rx * (0.26 + 0.03 * float(t["lips"]))
	var up := ry * (0.036 + 0.017 * float(t["lips"]))
	var low := ry * (0.05 + 0.024 * float(t["lips"]))
	var expr := int(prop.get("mouth", 0))
	var lift: float = ry * [0.05, 0.0, 0.0][expr]
	var lip_color := skin.lerp(Color(0.6, 0.28, 0.3), 0.38).darkened(0.06)
	var line := PackedVector2Array()
	var top_edge := PackedVector2Array()
	var bottom_edge := PackedVector2Array()
	for i in 11:
		var f := float(i) / 10.0 * 2.0 - 1.0
		var tilt_m := (ry * 0.045 * f) if expr == 2 else 0.0   # a smirk lifts the right corner
		var yy: float = my - lift * f * f - tilt_m
		line.append(Vector2(hc.x + f * mw, yy))
		var body := pow(maxf(0.0, 1.0 - f * f), 0.7)
		top_edge.append(Vector2(hc.x + f * mw, yy - up * body + (up * 0.55 * exp(-f * f * 18.0))))
		bottom_edge.append(Vector2(hc.x + f * mw, yy + low * pow(maxf(0.0, 1.0 - f * f), 0.8)))
	var upper_lip := PackedVector2Array(top_edge)
	var line_rev := PackedVector2Array(line)
	line_rev.reverse()
	upper_lip.append_array(line_rev)
	_fill(ci, upper_lip, lip_color.darkened(0.06))
	var lower_lip := PackedVector2Array(line)
	var bottom_rev := PackedVector2Array(bottom_edge)
	bottom_rev.reverse()
	lower_lip.append_array(bottom_rev)
	_fill(ci, lower_lip, lip_color.lightened(0.04))
	_poly_line(ci, line, Color(ink, 0.85), maxf(1.0, ry * 0.03))
	_soft(ci, Vector2(hc.x - mw * 0.1, line[5].y + low * 0.45), mw * 0.35, low * 0.22, Color(WHITE, 0.18), 3)
	_soft(ci, Vector2(hc.x, my + ry * 0.2), mw * 0.7, ry * 0.07, Color(_shadow_of(skin, 0.3), 0.14), 3)
	if detail >= 3:
		if int(t["cleft"]) == 1:
			ci.draw_line(Vector2(hc.x, my + ry * 0.32), Vector2(hc.x, my + ry * 0.45), Color(ink, 0.12), maxf(1.0, ry * 0.03), true)
		if int(t["lines"]) >= 1:   # nasolabial folds
			for side in [-1.0, 1.0]:
				var s3: float = side
				_poly_line(ci, PackedVector2Array([Vector2(hc.x + s3 * nw * 1.1, nbase + ry * 0.04), Vector2(hc.x + s3 * mw * 1.25, my - ry * 0.02)]), Color(ink, 0.07 + 0.03 * float(t["lines"])), maxf(1.0, ry * 0.02))
		if int(t["lines"]) >= 2:   # forehead lines
			for k in 2 + int(t["lines"]) - 2:
				var fy := hc.y - ry * (0.66 - 0.07 * float(k))
				_poly_line(ci, PackedVector2Array([Vector2(hc.x - rx * 0.4, fy), Vector2(hc.x, fy - ry * 0.015), Vector2(hc.x + rx * 0.4, fy)]), Color(ink, 0.1), maxf(1.0, ry * 0.016))


# --- facial hair ------------------------------------------------------------------------------------------------------------

static func _beard_polygon(hc: Vector2, rx: float, ry: float, outline: PackedVector2Array, inner: Array) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for p in outline:
		if p.y >= hc.y + ry * 0.08:
			poly.append(p)
	for q in inner:
		poly.append(hc + Vector2(q.x * rx, q.y * ry))
	return poly


static func _facial_hair_back(ci: CanvasItem, hc: Vector2, rx: float, ry: float, style: String, hair: Color, outline: PackedVector2Array, detail: int) -> void:
	if style == "none" or detail == 0:
		return
	var col := hair.darkened(0.05)
	match style:
		"stubble":
			var poly := _beard_polygon(hc, rx, ry, outline, [Vector2(-0.92, 0.04), Vector2(-0.66, 0.34), Vector2(-0.4, 0.45), Vector2(-0.22, 0.62), Vector2(0, 0.6), Vector2(0.22, 0.62), Vector2(0.4, 0.45), Vector2(0.66, 0.34), Vector2(0.92, 0.04)])
			ci.draw_colored_polygon(poly, Color(col, 0.3))
			if detail >= 3:
				for i in 26:
					var a := 0.3 + float(i) * (PI - 0.6) / 25.0
					ci.draw_circle(hc + Vector2(cos(a) * rx * (0.55 + 0.25 * _rnd("st", i)), sin(a) * ry * (0.6 + 0.25 * _rnd("sy", i))), maxf(0.6, ry * 0.014), Color(col, 0.35))
		"beard":
			var poly2 := _beard_polygon(hc, rx, ry, outline, [Vector2(-0.93, 0.02), Vector2(-0.66, 0.3), Vector2(-0.42, 0.4), Vector2(-0.3, 0.46), Vector2(-0.24, 0.64), Vector2(0, 0.6), Vector2(0.24, 0.64), Vector2(0.3, 0.46), Vector2(0.42, 0.4), Vector2(0.66, 0.3), Vector2(0.93, 0.02)])
			_lit(ci, poly2, col, 0.08, 0.2)
			if detail >= 3:
				for i in 5:
					ci.draw_line(hc + Vector2((float(i) - 2.0) * rx * 0.28, ry * 0.8), hc + Vector2((float(i) - 2.0) * rx * 0.34, ry * 0.97), Color(WHITE, 0.07), maxf(1.0, ry * 0.02), true)
		"goatee":
			var chin := PackedVector2Array([hc + Vector2(-rx * 0.3, ry * 0.58), hc + Vector2(-rx * 0.2, ry * 0.66), hc + Vector2(0, ry * 0.62), hc + Vector2(rx * 0.2, ry * 0.66), hc + Vector2(rx * 0.3, ry * 0.58), hc + Vector2(rx * 0.2, ry * 0.95), hc + Vector2(0, ry * 1.01), hc + Vector2(-rx * 0.2, ry * 0.95)])
			_lit(ci, chin, col, 0.06, 0.2)


static func _facial_hair_front(ci: CanvasItem, hc: Vector2, rx: float, ry: float, style: String, hair: Color, detail: int) -> void:
	if detail < 2 or not (style == "goatee" or style == "beard"):
		return
	var col := hair.darkened(0.05)
	var my := hc.y + ry * 0.5
	# the moustache over the upper lip
	var pts := PackedVector2Array([Vector2(hc.x - rx * 0.34, my - ry * 0.02), Vector2(hc.x - rx * 0.18, my - ry * 0.13), Vector2(hc.x, my - ry * 0.09), Vector2(hc.x + rx * 0.18, my - ry * 0.13), Vector2(hc.x + rx * 0.34, my - ry * 0.02), Vector2(hc.x + rx * 0.16, my - ry * 0.045), Vector2(hc.x, my - ry * 0.04), Vector2(hc.x - rx * 0.16, my - ry * 0.045)])
	ci.draw_colored_polygon(pts, col)


# --- hair -------------------------------------------------------------------------------------------------------------------

## The hairline: a curve across the forehead that rises with the forehead trait and recedes with age.
static func _hairline(hc: Vector2, rx: float, ry: float, c: Dictionary) -> PackedVector2Array:
	var t: Dictionary = c["t"]
	var age_push := clampf(float(int(t["age"]) - 26) / 14.0, 0.0, 1.0) * 0.045 * float(int(t["recession"]))
	var hl := -0.56 + 0.035 * float(int(t["forehead"]) - 1) + age_push
	var side_up := -0.28 + age_push * 1.8
	var pts: Array = [Vector2(0.99, -0.02), Vector2(0.96, side_up), Vector2(0.78, hl - 0.04), Vector2(0.42, hl - 0.015), Vector2(0.0, hl)]
	var ring: Array = []
	for p in pts:
		ring.append(p)
	for i in range(pts.size() - 2, -1, -1):
		var p: Vector2 = pts[i]
		ring.append(Vector2(-p.x, p.y))
	# ring runs right-bottom, ..., center, ..., left-bottom
	return _map(_spline(ring, 3, false), hc, rx, ry)


## The hair cap: the skull top (outer arc) over the hairline. `grow` makes it thicker; `lift` raises the crown (a pompadour, a high top).
static func _cap(hc: Vector2, rx: float, ry: float, c: Dictionary, grow: float = 0.04, lift: float = 0.0) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var steps := 20
	for i in steps + 1:
		var a := lerpf(PI * 1.0, PI * 2.0, float(i) / float(steps))
		var k := 1.0 + grow
		var lifted := lift * pow(sin(a - PI), 2.0)
		poly.append(hc + Vector2(cos(a) * rx * (1.03 + grow), sin(a) * ry * (1.02 + grow + lifted) - ry * 0.0 * k))
	var line := _hairline(hc, rx, ry, c)
	for i in range(0, line.size()):
		poly.append(line[i])
	return poly


static func _strands(ci: CanvasItem, hc: Vector2, rx: float, ry: float, hair: Color, key: String, count: int, spread: float, u: float) -> void:
	for i in count:
		var a := PI * 1.12 + _rnd(key, 40 + i) * PI * 0.76
		var r0 := 0.55 + _rnd(key, 80 + i) * 0.25
		var from := hc + Vector2(cos(a) * rx * r0, sin(a) * ry * r0)
		var to := hc + Vector2(cos(a + spread * (_rnd(key, 120 + i) - 0.5)) * rx * 1.0, sin(a + spread * (_rnd(key, 120 + i) - 0.5)) * ry * 1.0)
		ci.draw_line(from, to, Color(hair.lightened(0.18) if i % 2 == 0 else hair.darkened(0.25), 0.28), maxf(1.0, 0.9 * u), true)


static func _hair_back(ci: CanvasItem, hc: Vector2, rx: float, ry: float, style: String, variant: int, hair: Color, u: float, detail: int, c: Dictionary) -> void:
	match style:
		"afro":
			var s: float = [1.0, 1.14, 0.82][variant]
			var centre := hc + Vector2(0, -ry * 0.3)
			var ring := PackedVector2Array()
			for i in 40:
				var a := TAU * float(i) / 40.0
				var bump := 1.0 + (0.045 * sin(a * 11.0 + float(variant)) if detail >= 2 else 0.0)
				ring.append(centre + Vector2(cos(a) * rx * 1.5 * s * bump, sin(a) * ry * 1.28 * s * bump))
			_lit(ci, ring, hair, 0.12, 0.2)
			if detail >= 2:
				for i in 9:
					var a2 := PI * 1.05 + float(i) * 0.46
					_soft(ci, centre + Vector2(cos(a2) * rx * 1.05 * s, sin(a2) * ry * 0.95 * s), ry * 0.14, ry * 0.1, Color(hair.lightened(0.25), 0.25), 2)
		"long":
			var back := PackedVector2Array([hc + Vector2(-rx * 1.12, -ry * 0.1), hc + Vector2(-rx * 1.15, ry * 1.2), hc + Vector2(-rx * 0.95, ry * 1.85), hc + Vector2(rx * 0.95, ry * 1.85), hc + Vector2(rx * 1.15, ry * 1.2), hc + Vector2(rx * 1.12, -ry * 0.1), hc + Vector2(0, -ry * 1.08)])
			if variant == 2:   # a ponytail: only a short fall behind the neck
				back = PackedVector2Array([hc + Vector2(-rx * 0.5, -ry * 0.6), hc + Vector2(-rx * 0.7, ry * 1.0), hc + Vector2(0, ry * 1.35), hc + Vector2(rx * 0.7, ry * 1.0), hc + Vector2(rx * 0.5, -ry * 0.6)])
			_lit(ci, back, hair.darkened(0.08), 0.08, 0.2)
		"locs":
			var count := 5 if variant != 2 else 3
			for side in [-1.0, 1.0]:
				var s: float = side
				for j in count:
					var x0 := hc.x + s * rx * (0.62 + 0.14 * float(j))
					var len := ry * (1.15 + 0.2 * _rnd(c["key"], j + 3) + (0.45 if variant == 1 else 0.0))
					var p := PackedVector2Array([Vector2(x0, hc.y - ry * 0.35), Vector2(x0 + s * rx * 0.05, hc.y + len * 0.3), Vector2(x0 + s * rx * 0.1, hc.y + len)])
					_taper(ci, _spline(p, 4), 3.4 * u, 2.6 * u, hair.lightened(0.04 * float(j % 2)))
		"braids":
			if variant == 1:   # box braids hang behind the ears
				for side in [-1.0, 1.0]:
					var s2: float = side
					for j in 6:
						var x1 := hc.x + s2 * rx * (0.7 + 0.1 * float(j))
						var p2 := PackedVector2Array([Vector2(x1, hc.y - ry * 0.4), Vector2(x1 + s2 * rx * 0.04, hc.y + ry * 0.6), Vector2(x1 + s2 * rx * 0.06, hc.y + ry * (1.4 + 0.12 * float(j % 3)))])
						_taper(ci, _spline(p2, 4), 2.5 * u, 2.0 * u, hair)
		"curly":
			pass


static func _hair_front(ci: CanvasItem, hc: Vector2, rx: float, ry: float, style: String, variant: int, hair: Color, u: float, detail: int, c: Dictionary) -> void:
	var key: String = c["key"]
	var t: Dictionary = c["t"]
	match style:
		"bald":
			if detail >= 2:
				_soft(ci, hc + Vector2(-rx * 0.3, -ry * 0.78), rx * 0.3, ry * 0.1, Color(WHITE, 0.2), 3)
				if variant == 0:   # a shaved shadow at the temples and crown
					var cap0 := _cap(hc, rx, ry, c, 0.0)
					ci.draw_colored_polygon(cap0, Color(hair, 0.3))
		"short", "fade":
			var lift := 0.0
			if style == "short" and variant == 2:
				lift = 0.1
			var thick := 0.0 if (style == "short" and variant == 0) else (0.035 if style == "short" else 0.0)
			var cap := _cap(hc, rx, ry, c, thick, lift)
			ci.draw_colored_polygon(cap, Color(hair, 0.62 if (style == "short" and variant == 0) else 1.0))
			if style == "fade":
				# a faded side: the hair thins toward the ears (skin showing through), a hard line at the top
				for side in [-1.0, 1.0]:
					var s: float = side
					var strip := PackedVector2Array([hc + Vector2(s * rx * 0.97, -ry * 0.3), hc + Vector2(s * rx * 0.76, -ry * 0.5), hc + Vector2(s * rx * 0.9, ry * 0.02), hc + Vector2(s * rx * 1.0, ry * 0.0)])
					ci.draw_colored_polygon(strip, Color(hair, 0.0))
				if variant == 0:   # a high top
					var top := PackedVector2Array([hc + Vector2(-rx * 0.76, -ry * 0.92), hc + Vector2(-rx * 0.7, -ry * 1.42), hc + Vector2(-rx * 0.4, -ry * 1.5), hc + Vector2(rx * 0.4, -ry * 1.5), hc + Vector2(rx * 0.7, -ry * 1.42), hc + Vector2(rx * 0.76, -ry * 0.92)])
					_lit(ci, top, hair, 0.12, 0.18)
				elif variant == 1:   # curls on top
					for i in 7:
						ci.draw_circle(hc + Vector2((float(i) - 3.0) * rx * 0.24, -ry * (1.0 + 0.06 * sin(float(i) * 2.0))), ry * 0.15, hair)
			if detail >= 2:
				ci.draw_arc(hc, ry * 0.97, PI * 1.15, PI * 1.45, 8, Color(WHITE, 0.2), maxf(1.0, 1.5 * u), true)
				if style == "short" and variant == 2:   # a side part
					ci.draw_line(hc + Vector2(-rx * 0.28, -ry * 1.0), hc + Vector2(-rx * 0.3, -ry * 0.62), Color(SHADOW, 0.35), maxf(1.0, 1.2 * u), true)
		"afro":
			var fringe := _cap(hc, rx, ry, c, 0.07)
			ci.draw_colored_polygon(fringe, hair)
		"curly":
			var cap_c := _cap(hc, rx, ry, c, 0.08)
			ci.draw_colored_polygon(cap_c, hair)
			var n := 11 if detail >= 1 else 7
			for i in n:
				var a := PI * 1.02 + float(i) * PI * 0.96 / float(n - 1)
				ci.draw_circle(hc + Vector2(cos(a) * rx * 1.06, sin(a) * ry * 1.08), ry * (0.2 + 0.04 * float(i % 2)), hair)
			for i in 6:
				var a2 := PI * 1.15 + float(i) * PI * 0.7 / 5.0
				ci.draw_circle(hc + Vector2(cos(a2) * rx * 0.74, sin(a2) * ry * 0.86), ry * 0.17, hair.lightened(0.05))
		"braids":
			var cap_b := _cap(hc, rx, ry, c, 0.03, 0.0)
			ci.draw_colored_polygon(cap_b, hair)
			if variant == 0 and detail >= 1:   # cornrows: lines running from the hairline back over the skull
				for i in 7:
					var f := (float(i) - 3.0) / 3.0
					var rows := PackedVector2Array()
					for k in 5:
						var kk := float(k) / 4.0
						rows.append(hc + Vector2(f * rx * (0.7 - 0.45 * kk), -ry * (0.52 + 0.5 * kk)))
					for piece in Geometry2D.intersect_polyline_with_polygon(rows, cap_b):
						_poly_line(ci, piece, Color(hair.lightened(0.2), 0.55), maxf(1.0, 1.0 * u))
			elif variant == 2:   # a top bun
				ci.draw_circle(hc + Vector2(0, -ry * 1.18), ry * 0.3, hair)
				ci.draw_circle(hc + Vector2(-ry * 0.07, -ry * 1.22), ry * 0.1, Color(WHITE, 0.12))
		"locs":
			var cap_l := _cap(hc, rx, ry, c, 0.05, 0.03)
			ci.draw_colored_polygon(cap_l, hair)
			if detail >= 1:
				for i in 7:   # twists across the crown
					var a3 := PI * 1.1 + float(i) * PI * 0.8 / 6.0
					_taper(ci, PackedVector2Array([hc + Vector2(cos(a3) * rx * 0.7, sin(a3) * ry * 0.7), hc + Vector2(cos(a3) * rx * 1.08, sin(a3) * ry * 1.12 - ry * 0.05)]), 3.6 * u, 3.0 * u, hair.lightened(0.05))
		"long":
			var cap_h := _cap(hc, rx, ry, c, 0.05, 0.02)
			ci.draw_colored_polygon(cap_h, hair)
			# the front falls past the ears on both sides; a side part
			for side in [-1.0, 1.0]:
				var s2: float = side
				var lock := PackedVector2Array([hc + Vector2(s2 * rx * 0.9, -ry * 0.4), hc + Vector2(s2 * rx * 1.14, -ry * 0.1), hc + Vector2(s2 * rx * 1.16, ry * 1.2), hc + Vector2(s2 * rx * 0.96, ry * 1.2), hc + Vector2(s2 * rx * 0.98, ry * 0.1)])
				if variant != 2:
					_lit(ci, lock, hair, 0.08, 0.18)
			if detail >= 2:
				ci.draw_line(hc + Vector2(rx * 0.22, -ry * 1.0), hc + Vector2(rx * 0.4, -ry * 0.58), Color(SHADOW, 0.3), maxf(1.0, 1.2 * u), true)
				_strands(ci, hc, rx, ry, hair, key, 7, 0.25, u)
	# grey at the temples with age, over any styled hair that has a visible hairline
	if int(t["grey"]) >= 1 and style in ["short", "fade", "braids", "locs", "long"] and detail >= 2:
		var cap_g := _cap(hc, rx, ry, c, 0.05)
		for side in [-1.0, 1.0]:
			var s3: float = side
			var patch := _ellipse_pts(hc + Vector2(s3 * rx * 0.86, -ry * 0.3), rx * 0.24, ry * (0.2 + 0.1 * float(t["grey"])), 12)
			for poly in Geometry2D.intersect_polygons(cap_g, patch):
				ci.draw_colored_polygon(poly, Color(0.74, 0.74, 0.76, 0.28 + 0.14 * float(t["grey"])))
	if style in ["short", "fade", "curly", "afro", "braids", "locs"] and detail >= 3:
		_strands(ci, hc, rx, ry, hair, key, 6, 0.2, u)


static func _headband(ci: CanvasItem, hc: Vector2, rx: float, ry: float, color: Color, edge: Color) -> void:
	var y := hc.y - ry * 0.5
	var half := rx * 0.99 * sqrt(maxf(0.0, 1.0 - pow(0.5, 2.0)))
	var band := PackedVector2Array([Vector2(hc.x - half, y - ry * 0.08), Vector2(hc.x, y - ry * 0.1), Vector2(hc.x + half, y - ry * 0.08), Vector2(hc.x + half, y + ry * 0.06), Vector2(hc.x, y + ry * 0.08), Vector2(hc.x - half, y + ry * 0.06)])
	_lit(ci, band, color, 0.06, 0.18)
	ci.draw_line(Vector2(hc.x - half, y + ry * 0.065), Vector2(hc.x + half, y + ry * 0.085), edge, maxf(1.0, ry * 0.03), true)
