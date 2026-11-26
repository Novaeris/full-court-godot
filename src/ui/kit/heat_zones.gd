class_name FcHeatZones
extends Control
## A shot chart on a half court: each zone of FcShotZones is shaded by how well the player (or team) shoots there compared with the
## league, with attempts and percentage written in the zone; recorded shot spots can be drawn on top as made (filled) and missed (ring)
## marks. It shows only the numbers it is given: a zone with no attempts stays unshaded, and with no data at all the court is drawn with a
## note. The comparison is spelled out in the tooltip and `summary()`, so colour never carries the meaning alone.

## zone id -> {"made": int, "att": int}
var zones: Dictionary = {}
## zone id -> league field-goal percentage there (0..1); zones without one are shaded by volume only.
var league_pct: Dictionary = {}
## Optional recorded spots: [{"x": metres, "y": metres, "made": bool}].
var spots: Array = []
var empty_text: String = "No shots recorded yet"

## Each zone is sampled on this grid to fill its area (cheap: drawn only when the data or size changes).
const CELL := 0.25


func _init() -> void:
	custom_minimum_size = Vector2(300, 282)
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_data(zone_counts: Dictionary, league: Dictionary = {}, shot_spots: Array = []) -> FcHeatZones:
	zones = zone_counts
	league_pct = league
	spots = shot_spots
	tooltip_text = summary()
	queue_redraw()
	return self


func total_attempts() -> int:
	var n := 0
	for z in zones.values():
		n += int(z.get("att", 0))
	return n


## "At the rim 24/40 (60%, league 58%); ..." for every zone with attempts.
func summary() -> String:
	var parts: Array = []
	for id in FcShotZones.ids():
		var z: Dictionary = zones.get(id, {})
		var att := int(z.get("att", 0))
		if att <= 0:
			continue
		var pct := float(z.get("made", 0)) / float(att)
		var text := "%s %d/%d (%d%%" % [FcShotZones.display_name(id), int(z.get("made", 0)), att, roundi(pct * 100.0)]
		if league_pct.has(id):
			text += ", league %d%%" % roundi(float(league_pct[id]) * 100.0)
		parts.append(text + ")")
	return "; ".join(parts)


## The shade of a zone: hotter (orange) above the league, cooler (blue) below, grey without a comparison. Alpha grows with attempts.
func zone_color(zone_id: String) -> Color:
	var z: Dictionary = zones.get(zone_id, {})
	var att := int(z.get("att", 0))
	if att <= 0:
		return FcUiTokens.TRANSPARENT
	var pct := float(z.get("made", 0)) / float(att)
	var weight := clampf(float(att) / 12.0, 0.35, 1.0)
	if not league_pct.has(zone_id):
		return Color(FcUiTokens.STEEL, 0.30 * weight)
	var diff := clampf((pct - float(league_pct[zone_id])) / 0.12, -1.0, 1.0)
	var c := FcUiTokens.PRIMARY if diff >= 0.0 else FcUiTokens.INFO
	return Color(c, (0.18 + 0.45 * absf(diff)) * weight)


func _court_rect() -> Rect2:
	var scale := minf(size.x / FcShotZones.WIDTH, size.y / FcShotZones.DEPTH)
	var w := FcShotZones.WIDTH * scale
	var h := FcShotZones.DEPTH * scale
	return Rect2(Vector2((size.x - w) / 2.0, (size.y - h) / 2.0), Vector2(w, h))


## Court metres to pixels: the basket at the top of the chart, the half-court line at the bottom.
func to_px(m: Vector2) -> Vector2:
	var r := _court_rect()
	return r.position + Vector2(m.x / FcShotZones.WIDTH * r.size.x, m.y / FcShotZones.DEPTH * r.size.y)


func _draw() -> void:
	var r := _court_rect()
	var px := r.size.x / FcShotZones.WIDTH
	draw_rect(r, FcUiTokens.SURFACE_RAISED)
	# zone shading, sampled on a grid
	if total_attempts() > 0:
		var y := 0.0
		while y < FcShotZones.DEPTH:
			var x := 0.0
			while x < FcShotZones.WIDTH:
				var c := zone_color(FcShotZones.zone_of(Vector2(x + CELL * 0.5, y + CELL * 0.5)))
				if c.a > 0.0:   # pixel-aligned cells that share edges exactly, so translucent shading never doubles up into grid lines
					var a := to_px(Vector2(x, y)).round()
					var b := to_px(Vector2(minf(x + CELL, FcShotZones.WIDTH), minf(y + CELL, FcShotZones.DEPTH))).round()
					draw_rect(Rect2(a, b - a), c)
				x += CELL
			y += CELL
	_draw_lines(px)
	var font := FcUiFonts.body(600, true)
	if font == null:
		font = ThemeDB.fallback_font
	var fs := FcUiTokens.fs(FcUiTokens.TYPE_MICRO)
	if total_attempts() <= 0 and spots.is_empty():
		draw_string(font, Vector2(r.position.x, r.get_center().y + r.size.y * 0.2), empty_text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, FcUiTokens.fs(FcUiTokens.TYPE_SMALL), FcUiTokens.TEXT_MUTED)
	# the spots
	for s in spots:
		var p := to_px(Vector2(float(s.get("x", 0.0)), float(s.get("y", 0.0))))
		if bool(s.get("made", false)):
			draw_circle(p, 3.2, FcUiTokens.SUCCESS)
		else:
			draw_arc(p, 3.2, 0.0, TAU, 12, FcUiTokens.DANGER, 1.4, true)
	# numbers in each zone
	for id in FcShotZones.ids():
		var z: Dictionary = zones.get(id, {})
		var att := int(z.get("att", 0))
		if att <= 0:
			continue
		var anchor := to_px(_label_spot(id))
		var pct := "%d%%" % roundi(float(z.get("made", 0)) * 100.0 / float(att))
		var count := "%d/%d" % [int(z.get("made", 0)), att]
		draw_string(font, anchor + Vector2(-40, 0), pct, HORIZONTAL_ALIGNMENT_CENTER, 80, fs + 2, FcUiTokens.TEXT)
		draw_string(font, anchor + Vector2(-40, fs + 2), count, HORIZONTAL_ALIGNMENT_CENTER, 80, fs, FcUiTokens.TEXT_MUTED)


## Where a zone's numbers are written (metres).
static func _label_spot(zone_id: String) -> Vector2:
	match zone_id:
		FcShotZones.RIM: return Vector2(7.5, 2.2)
		FcShotZones.PAINT: return Vector2(7.5, 4.6)
		FcShotZones.MID_LEFT: return Vector2(3.6, 3.4)
		FcShotZones.MID_RIGHT: return Vector2(11.4, 3.4)
		FcShotZones.MID_CENTER: return Vector2(7.5, 6.9)
		FcShotZones.CORNER3_LEFT: return Vector2(0.45, 1.3)
		FcShotZones.CORNER3_RIGHT: return Vector2(14.55, 1.3)
		FcShotZones.WING3_LEFT: return Vector2(1.9, 8.6)
		FcShotZones.WING3_RIGHT: return Vector2(13.1, 8.6)
	return Vector2(7.5, 10.4)


func _draw_lines(px: float) -> void:
	var line := Color(FcUiTokens.TEXT, 0.45)
	var r := _court_rect()
	draw_rect(r, line, false, 1.5)
	# paint
	var paint := Rect2(to_px(Vector2(FcShotZones.HOOP.x - FcShotZones.PAINT_HALF_WIDTH, 0)), Vector2(FcShotZones.PAINT_HALF_WIDTH * 2.0 * px, FcShotZones.PAINT_DEPTH * px))
	draw_rect(paint, line, false, 1.5)
	draw_arc(to_px(Vector2(FcShotZones.HOOP.x, FcShotZones.PAINT_DEPTH)), 1.8 * px, 0.0, PI, 24, line, 1.5, true)
	# three-point line: corners and arc
	var corner_depth := FcShotZones.HOOP.y + sqrt(FcShotZones.THREE_RADIUS * FcShotZones.THREE_RADIUS - pow(FcShotZones.HOOP.x - FcShotZones.CORNER_X, 2))
	for x in [FcShotZones.CORNER_X, FcShotZones.WIDTH - FcShotZones.CORNER_X]:
		draw_line(to_px(Vector2(x, 0)), to_px(Vector2(x, corner_depth)), line, 1.5)
	var start := atan2(corner_depth - FcShotZones.HOOP.y, FcShotZones.WIDTH - FcShotZones.CORNER_X - FcShotZones.HOOP.x)
	var end := atan2(corner_depth - FcShotZones.HOOP.y, FcShotZones.CORNER_X - FcShotZones.HOOP.x)
	draw_arc(to_px(FcShotZones.HOOP), FcShotZones.THREE_RADIUS * px, start, end, 48, line, 1.5, true)
	# rim, restricted arc, backboard
	draw_arc(to_px(FcShotZones.HOOP), 0.23 * px, 0.0, TAU, 16, FcUiTokens.PRIMARY, 1.5, true)
	draw_arc(to_px(FcShotZones.HOOP), FcShotZones.RIM_RADIUS * px, 0.0, PI, 24, line, 1.0, true)
	draw_line(to_px(Vector2(6.6, 1.2)), to_px(Vector2(8.4, 1.2)), line, 2.0)
	# half-court circle at the bottom edge
	draw_arc(to_px(Vector2(7.5, FcShotZones.DEPTH)), 1.8 * px, PI, TAU, 24, line, 1.5, true)
