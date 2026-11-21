class_name FcModeArt
extends Control
## The picture on a main-menu mode card. Each mode has its own COMPOSITION, not just its own colour (all drawn from shapes, no image
## files, so it stays sharp at any size and carries no licensing question):
##   owner    a city skyline with lit windows under a blueprint of a basketball court: the front office, the whole franchise
##   career   a player figure in a spotlight on a lit floor with a broadcast lower-third stripe: one athlete, centre stage
##   dynasty  three face-down collectible cards fanned out in rarity colours with a glint: the collection
## Nothing here is data: it never shows numbers, names or records, so it cannot be mistaken for real game information.

const KINDS := ["owner", "career", "dynasty"]

var kind: String = "owner"
var accent: Color = FcUiTokens.PRIMARY
var _visual: Dictionary = {}


func _init(art_kind: String = "owner", art_accent: Color = FcUiTokens.PRIMARY) -> void:
	kind = art_kind
	accent = art_accent
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	custom_minimum_size = Vector2(120, 120)
	if kind == "career":
		var team := {"name": "Full Court", "abbreviation": "FC", "primary": "#C2410C", "secondary": "#F8FAFC"}
		_visual = FcPlayerVisual.resolve(FcPlayerPresentation.subject("menu_career_hero", "Player", team, 23))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	match kind:
		"owner":
			_owner(r)
		"career":
			_career(r)
		_:
			_dynasty(r)


# --- owner: skyline and court blueprint ------------------------------------------------------------------------------

func _owner(r: Rect2) -> void:
	var w := r.size.x
	var h := r.size.y
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Color(FcUiTokens.STEEL, 0.30), Color(FcUiTokens.STEEL, 0.30), Color(FcUiTokens.SURFACE, 1.0), Color(FcUiTokens.SURFACE, 1.0)]))
	var grid := Color(FcUiTokens.INFO, 0.07)
	var step := maxf(16.0, h / 9.0)
	var gx := 0.0
	while gx < w:
		draw_line(Vector2(gx, 0), Vector2(gx, h), grid, 1.0)
		gx += step
	var gy := 0.0
	while gy < h:
		draw_line(Vector2(0, gy), Vector2(w, gy), grid, 1.0)
		gy += step
	# the court blueprint, upper right
	var cw := minf(w * 0.52, h * 0.95)
	var ch := cw * 0.55
	var origin := Vector2(w - cw - w * 0.06, h * 0.08)
	var ink := Color(FcUiTokens.INFO, 0.55)
	var lw := maxf(1.2, h * 0.006)
	draw_rect(Rect2(origin, Vector2(cw, ch)), ink, false, lw)
	draw_line(origin + Vector2(cw / 2.0, 0), origin + Vector2(cw / 2.0, ch), ink, lw)
	draw_arc(origin + Vector2(cw / 2.0, ch / 2.0), ch * 0.17, 0.0, TAU, 32, ink, lw, true)
	for side in [0.0, 1.0]:
		var kx := origin.x + (0.0 if side == 0.0 else cw - cw * 0.17)
		draw_rect(Rect2(Vector2(kx, origin.y + ch * 0.33), Vector2(cw * 0.17, ch * 0.34)), ink, false, lw)
		var arc_center := Vector2(origin.x + (cw * 0.06 if side == 0.0 else cw * 0.94), origin.y + ch / 2.0)
		var from_angle := -1.15 if side == 0.0 else PI - 1.15
		draw_arc(arc_center, ch * 0.44, from_angle, from_angle + 2.3, 24, ink, lw, true)
	# the skyline along the bottom
	var base := h * 0.96
	var x := -4.0
	var i := 0
	while x < w:
		var bw := h * (0.10 + 0.05 * float((i * 7) % 4))
		var bh := h * (0.22 + 0.11 * float((i * 5 + 3) % 6))
		var tone := Color(FcUiTokens.BG, 0.92 if i % 2 == 0 else 0.78)
		draw_rect(Rect2(Vector2(x, base - bh), Vector2(bw, bh)), tone)
		var wy := base - bh + bw * 0.18
		while wy < base - bw * 0.3:
			var wx := x + bw * 0.16
			var col := 0
			while wx < x + bw * 0.8:
				if (i * 31 + col * 17 + int(wy / 6.0) * 13) % 5 < 2:
					draw_rect(Rect2(Vector2(wx, wy), Vector2(maxf(2.0, bw * 0.1), maxf(2.0, bw * 0.12))), Color(FcUiTokens.GOLD, 0.6))
				wx += bw * 0.22
				col += 1
			wy += bw * 0.25
		if i % 5 == 2:   # an antenna on some roofs
			draw_line(Vector2(x + bw / 2.0, base - bh), Vector2(x + bw / 2.0, base - bh - h * 0.07), tone, 2.0)
		x += bw + h * 0.015
		i += 1
	draw_rect(Rect2(Vector2(0, base), Vector2(w, h - base)), Color(accent, 0.9))


# --- career: a player in the spotlight ------------------------------------------------------------------------------

func _career(r: Rect2) -> void:
	var w := r.size.x
	var h := r.size.y
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Color(FcUiTokens.BG, 1.0), Color(FcUiTokens.BG, 1.0), Color(accent, 0.28), Color(accent, 0.28)]))
	# the spotlight cone
	draw_polygon(PackedVector2Array([Vector2(w * 0.46, 0), Vector2(w * 0.54, 0), Vector2(w * 0.92, h * 0.92), Vector2(w * 0.08, h * 0.92)]),
		PackedColorArray([Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.03)]))
	# the lit floor under the player
	draw_set_transform(Vector2(w * 0.5, h * 0.9), 0.0, Vector2(1.0, 0.22))
	draw_circle(Vector2.ZERO, w * 0.36, Color(accent, 0.34))
	draw_circle(Vector2.ZERO, w * 0.22, Color(1, 1, 1, 0.10))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the athlete
	if not _visual.is_empty():
		var fh := h * 0.8
		var fw := minf(w * 0.7, fh * 0.9)
		FcPlayerFigure.draw(self, Rect2(Vector2((w - fw) / 2.0, h * 0.06), Vector2(fw, fh)), _visual)
	# the broadcast lower-third stripe
	var bar_h := h * 0.07
	var y := h * 0.89
	draw_colored_polygon(PackedVector2Array([Vector2(0, y), Vector2(w * 0.72, y), Vector2(w * 0.68, y + bar_h), Vector2(0, y + bar_h)]), Color(accent, 0.95))
	draw_colored_polygon(PackedVector2Array([Vector2(w * 0.74, y), Vector2(w * 0.78, y), Vector2(w * 0.74, y + bar_h), Vector2(w * 0.70, y + bar_h)]), Color(1, 1, 1, 0.8))
	draw_line(Vector2(0, y + bar_h + 3), Vector2(w * 0.6, y + bar_h + 3), Color(1, 1, 1, 0.35), 2.0)


# --- dynasty: three cards in a fan ---------------------------------------------------------------------------------

func _dynasty(r: Rect2) -> void:
	var w := r.size.x
	var h := r.size.y
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Color(FcRarityStyle.dark("epic"), 1.0), Color(FcRarityStyle.dark("epic"), 1.0), Color(FcUiTokens.BG, 1.0), Color(FcUiTokens.BG, 1.0)]))
	# rays behind the cards
	var pivot := Vector2(w * 0.5, h * 1.02)
	for i in 9:
		var a := -PI / 2.0 + (float(i) - 4.0) * 0.17
		var spread := 0.045
		draw_colored_polygon(PackedVector2Array([pivot, pivot + Vector2(cos(a - spread), sin(a - spread)) * h * 1.4, pivot + Vector2(cos(a + spread), sin(a + spread)) * h * 1.4]), Color(accent, 0.07))
	var card_w := minf(w * 0.34, h * 0.4)
	var card_h := card_w * 1.4
	var order := [["rare", -17.0], ["epic", 17.0], ["legendary", 0.0]]
	for entry in order:
		draw_set_transform(pivot, deg_to_rad(float(entry[1])), Vector2.ONE)
		_card_back(Rect2(Vector2(-card_w / 2.0, -card_h * 1.12 - h * 0.0), Vector2(card_w, card_h)), str(entry[0]))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# a glint on the top card
	var glint := Vector2(w * 0.5 + card_w * 0.32, h * 1.02 - card_h * 1.12 + card_h * 0.12)
	draw_colored_polygon(_star_points(glint, card_w * 0.14, card_w * 0.03), Color(1, 1, 1, 0.9))


func _card_back(rect: Rect2, rarity: String) -> void:
	var color := FcRarityStyle.color(rarity)
	var body := StyleBoxFlat.new()
	body.bg_color = FcRarityStyle.dark(rarity)
	body.border_color = color
	body.set_border_width_all(maxi(2, int(rect.size.x * 0.03)))
	body.set_corner_radius_all(int(rect.size.x * 0.09))
	body.shadow_color = Color(0, 0, 0, 0.45)
	body.shadow_size = int(rect.size.x * 0.08)
	draw_style_box(body, rect)
	var c := rect.get_center()
	var d := rect.size.x * 0.3
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d * 0.7, 0), c + Vector2(0, d), c + Vector2(-d * 0.7, 0)]), Color(color, 0.28))
	draw_polyline(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d * 0.7, 0), c + Vector2(0, d), c + Vector2(-d * 0.7, 0), c + Vector2(0, -d)]), Color(color, 0.9), maxf(1.5, rect.size.x * 0.018), true)
	draw_colored_polygon(_star_points(c, d * 0.42, d * 0.12), Color(color, 0.95))


static func _star_points(c: Vector2, outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 8:
		var radius := outer if i % 2 == 0 else inner
		var a := -PI / 2.0 + PI * float(i) / 4.0
		pts.append(c + Vector2(cos(a), sin(a)) * radius)
	return pts
