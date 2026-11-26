class_name FcLineChart
extends Control
## A trend chart for one or more series over the same points (revenue and profit by season, a player's overall by year, wins over a
## season): horizontal guide lines with values on the left, labels along the bottom, one coloured line per series, a legend, and a hover
## readout of the nearest point. It draws ONLY the numbers it is given: with fewer than two points it shows a quiet note instead of a line,
## so it can never invent a trend. Colour is never the only carrier of meaning: every value is in the tooltip and `summary()`.

## Each series: {"name": String, "values": Array (numbers), "color": Color (optional; the chart palette otherwise)}.
var series: Array = []
var x_labels: Array = []
var empty_text: String = "Not enough data yet"
## Draw the area under the first series (a single trend reads better with it).
var fill_first: bool = true
var _formatter: Callable = Callable()
var _hover_index: int = -1

const PAD_LEFT := 56.0
const PAD_RIGHT := 12.0
const PAD_TOP := 26.0
const PAD_BOTTOM := 24.0
const GUIDES := 4


func _init(series_list: Array = [], labels: Array = [], format: Callable = Callable()) -> void:
	custom_minimum_size = Vector2(260, 160)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_data(series_list, labels, format)
	mouse_exited.connect(func() -> void:
		_hover_index = -1
		queue_redraw())


## Replaces the data. `format` turns a value into text (money, ratings, percentages); plain numbers otherwise.
func set_data(series_list: Array, labels: Array = [], format: Callable = Callable()) -> void:
	series = series_list
	x_labels = labels
	_formatter = format
	tooltip_text = summary()
	queue_redraw()


func point_count() -> int:
	var n := 0
	for s in series:
		n = maxi(n, (s.get("values", []) as Array).size())
	return n


func has_lines() -> bool:
	return point_count() >= 2


## Every series in words, for the tooltip and screen readers: "Revenue: 2026 $210M, 2027 $230M; Profit: ...".
func summary() -> String:
	if not has_lines():
		return ""
	var parts: Array = []
	for s in series:
		var values: Array = s.get("values", [])
		var items: Array = []
		for i in values.size():
			items.append(("%s %s" % [str(x_labels[i]), _format(values[i])]) if i < x_labels.size() else _format(values[i]))
		parts.append("%s: %s" % [str(s.get("name", "")), ", ".join(items)])
	return "; ".join(parts)


func _format(v) -> String:
	return str(_formatter.call(v)) if _formatter.is_valid() else (str(roundi(float(v))) if absf(float(v) - roundf(float(v))) < 0.001 else "%.1f" % float(v))


func _color_of(index: int) -> Color:
	var s: Dictionary = series[index]
	return s["color"] if s.get("color") is Color else FcUiTokens.CHART[index % FcUiTokens.CHART.size()]


## The value range over every series, padded a little and never zero-height.
func _range() -> Vector2:
	var lo := INF
	var hi := -INF
	for s in series:
		for v in s.get("values", []):
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
	if lo == INF:
		return Vector2(0, 1)
	if is_equal_approx(lo, hi):
		return Vector2(lo - 1.0, hi + 1.0)
	var pad := (hi - lo) * 0.08
	return Vector2(lo - pad, hi + pad)


func _plot_rect() -> Rect2:
	return Rect2(Vector2(PAD_LEFT, PAD_TOP), Vector2(maxf(10.0, size.x - PAD_LEFT - PAD_RIGHT), maxf(10.0, size.y - PAD_TOP - PAD_BOTTOM)))


func _point(i: int, v: float, n: int, plot: Rect2, r: Vector2) -> Vector2:
	var x := plot.position.x + (plot.size.x * float(i) / float(maxi(1, n - 1)))
	var y := plot.position.y + plot.size.y * (1.0 - (v - r.x) / (r.y - r.x))
	return Vector2(x, y)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and has_lines():
		var plot := _plot_rect()
		var n := point_count()
		var t := clampf((event.position.x - plot.position.x) / plot.size.x, 0.0, 1.0)
		var index := roundi(t * float(n - 1))
		if index != _hover_index:
			_hover_index = index
			queue_redraw()


func _draw() -> void:
	var font := FcUiFonts.body(500, true)
	if font == null:
		font = ThemeDB.fallback_font
	var small := FcUiTokens.fs(FcUiTokens.TYPE_MICRO)
	if not has_lines():
		draw_string(font, Vector2(0, size.y * 0.5), empty_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, FcUiTokens.fs(FcUiTokens.TYPE_SMALL), FcUiTokens.TEXT_MUTED)
		return
	var plot := _plot_rect()
	var r := _range()
	var n := point_count()
	# guide lines with their values
	for g in GUIDES + 1:
		var v := r.x + (r.y - r.x) * float(g) / float(GUIDES)
		var y := plot.position.y + plot.size.y * (1.0 - float(g) / float(GUIDES))
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(FcUiTokens.BORDER, 0.55 if g == 0 else 0.3), 1.0)
		draw_string(font, Vector2(0, y + small * 0.35), _format(v), HORIZONTAL_ALIGNMENT_RIGHT, PAD_LEFT - 8.0, small, FcUiTokens.TEXT_MUTED)
	# x labels (thinned so they never collide)
	var step := maxi(1, ceili(float(n) * 64.0 / maxf(plot.size.x, 1.0)))
	for i in range(0, n, step):
		if i < x_labels.size():
			var p := _point(i, r.x, n, plot, r)
			draw_string(font, Vector2(p.x - 40.0, size.y - 6.0), str(x_labels[i]), HORIZONTAL_ALIGNMENT_CENTER, 80.0, small, FcUiTokens.TEXT_MUTED)
	# the lines
	for si in series.size():
		var values: Array = series[si].get("values", [])
		if values.size() < 2:
			continue
		var pts := PackedVector2Array()
		for i in values.size():
			pts.append(_point(i, float(values[i]), n, plot, r))
		var c := _color_of(si)
		if si == 0 and fill_first:
			var area := PackedVector2Array(pts)
			area.append(Vector2(pts[-1].x, plot.end.y))
			area.append(Vector2(pts[0].x, plot.end.y))
			draw_colored_polygon(area, Color(c, 0.12))
		draw_polyline(pts, c, 2.0, true)
		draw_circle(pts[-1], 3.5, c)
	# legend along the top
	var lx := plot.position.x
	for si in series.size():
		var name := str(series[si].get("name", ""))
		if name == "":
			continue
		draw_rect(Rect2(Vector2(lx, 8.0), Vector2(10, 10)), _color_of(si))
		draw_string(font, Vector2(lx + 14.0, 17.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, small, FcUiTokens.TEXT)
		lx += 24.0 + font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	# hover readout
	if _hover_index >= 0 and _hover_index < n:
		var hx := _point(_hover_index, r.x, n, plot, r).x
		draw_line(Vector2(hx, plot.position.y), Vector2(hx, plot.end.y), Color(FcUiTokens.TEXT, 0.35), 1.0)
		var lines: Array = []
		if _hover_index < x_labels.size():
			lines.append(str(x_labels[_hover_index]))
		for si in series.size():
			var values: Array = series[si].get("values", [])
			if _hover_index < values.size():
				draw_circle(_point(_hover_index, float(values[_hover_index]), n, plot, r), 4.0, _color_of(si))
				lines.append("%s %s" % [str(series[si].get("name", "")), _format(values[_hover_index])])
		var text_w := 0.0
		for l in lines:
			text_w = maxf(text_w, font.get_string_size(str(l), HORIZONTAL_ALIGNMENT_LEFT, -1, small).x)
		var box := Rect2(Vector2(minf(hx + 8.0, size.x - text_w - 20.0), plot.position.y), Vector2(text_w + 12.0, 6.0 + lines.size() * (small + 4.0)))
		var bg := StyleBoxFlat.new()
		bg.bg_color = FcUiTokens.SURFACE_HIGH
		bg.set_corner_radius_all(FcUiTokens.RADIUS_CONTROL)
		draw_style_box(bg, box)
		for li in lines.size():
			draw_string(font, box.position + Vector2(6.0, 4.0 + (li + 1) * (small + 4.0) - 4.0), str(lines[li]), HORIZONTAL_ALIGNMENT_LEFT, -1, small, FcUiTokens.TEXT)
