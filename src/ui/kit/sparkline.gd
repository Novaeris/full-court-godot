class_name FcSparkline
extends Control
## A small line chart of one series (profit by season, a rating by year): a soft area under the line, the line, a dot on the last value and
## an optional label. It draws ONLY the numbers it is given (a series of at least two points), so it can never show invented data; with fewer
## points it shows a quiet "Not enough seasons yet" instead of a line. Colour is never the only carrier of meaning: the last value is always
## available as text (`summary()`, the tooltip). The same chart serves the Owner overview, the player profile and the Career hub.

var values: Array = []
var labels: Array = []
var color: Color = FcUiTokens.INFO
var show_empty_text: bool = true
var _formatter: Callable = Callable()


func _init(series: Array = [], line_color: Color = FcUiTokens.INFO, point_labels: Array = [], format: Callable = Callable()) -> void:
	custom_minimum_size = Vector2(120, 44)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_series(series, point_labels, format)
	color = line_color


## Replaces the data. `point_labels` (optional, same length) name each point ("2026"); `format` turns a value into text (money, ratings).
func set_series(series: Array, point_labels: Array = [], format: Callable = Callable()) -> void:
	values = series
	labels = point_labels
	_formatter = format
	tooltip_text = summary()
	queue_redraw()


## The series in words: "2024: $4.1M, 2025: $5.0M, 2026: $6.3M" (the tooltip and the accessible text).
func summary() -> String:
	if values.size() < 2:
		return ""
	var parts: Array = []
	for i in values.size():
		var text := _format(values[i])
		parts.append("%s: %s" % [str(labels[i]), text] if i < labels.size() else text)
	return ", ".join(parts)


func has_line() -> bool:
	return values.size() >= 2


func _format(v) -> String:
	return str(_formatter.call(v)) if _formatter.is_valid() else str(v)


func _draw() -> void:
	if values.size() < 2:
		if show_empty_text:
			var font := ThemeDB.fallback_font
			draw_string(font, Vector2(0, size.y * 0.6), "Not enough seasons yet", HORIZONTAL_ALIGNMENT_LEFT, size.x, FcUiTokens.fs(FcUiTokens.TYPE_SMALL), FcUiTokens.TEXT_MUTED)
		return
	var lo := float(values[0])
	var hi := lo
	for v in values:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	var span := maxf(hi - lo, 0.000001)
	var pad := 4.0
	var w := size.x - pad * 2.0
	var h := size.y - pad * 2.0
	var pts := PackedVector2Array()
	for i in values.size():
		var x := pad + w * float(i) / float(values.size() - 1)
		var y := pad + h * (1.0 - (float(values[i]) - lo) / span) if hi > lo else pad + h * 0.5
		pts.append(Vector2(x, y))
	var area := PackedVector2Array(pts)
	area.append(Vector2(pts[-1].x, size.y - pad))
	area.append(Vector2(pts[0].x, size.y - pad))
	draw_colored_polygon(area, Color(color, 0.14))
	draw_polyline(pts, color, 2.0, true)
	draw_circle(pts[-1], 3.5, color)
	draw_circle(pts[-1], 1.6, FcUiTokens.BG)
