class_name FcRadar
extends Control
## A radar (spider) chart of one player's attribute groups: a ring grid, a spoke and a label for every group, a filled shape for the value now
## and an outline for what the player can reach. It draws only the numbers it is given (3 or more groups); every value is also in the
## tooltip as text ("Shooting 72 (can reach 80)"), so the shape is never the only carrier of meaning.

var labels: Array = []
var values: Array = []
var ceilings: Array = []
var color: Color = FcUiTokens.INFO


func _init(axis_labels: Array = [], now_values: Array = [], reach_values: Array = [], shape_color: Color = FcUiTokens.INFO) -> void:
	custom_minimum_size = Vector2(240, 240)
	color = shape_color
	set_axes(axis_labels, now_values, reach_values)


func set_axes(axis_labels: Array, now_values: Array, reach_values: Array = []) -> void:
	labels = axis_labels
	values = now_values
	ceilings = reach_values
	tooltip_text = summary()
	queue_redraw()


func has_shape() -> bool:
	return labels.size() >= 3 and values.size() == labels.size()


func summary() -> String:
	if not has_shape():
		return ""
	var parts: Array = []
	for i in labels.size():
		var text := "%s %d" % [str(labels[i]), roundi(float(values[i]))]
		if i < ceilings.size():
			text += " (can reach %d)" % roundi(float(ceilings[i]))
		parts.append(text)
	return ", ".join(parts)


func _point(i: int, fraction: float, center: Vector2, radius: float) -> Vector2:
	var a := -PI / 2.0 + TAU * float(i) / float(labels.size())
	return center + Vector2(cos(a), sin(a)) * radius * clampf(fraction, 0.0, 1.0)


func _draw() -> void:
	if not has_shape():
		return
	var font := ThemeDB.fallback_font
	var fs := FcUiTokens.fs(FcUiTokens.TYPE_SMALL)
	var margin := float(fs) * 3.2
	var center := size / 2.0
	var radius := maxf(10.0, minf(size.x, size.y) / 2.0 - margin)
	var n := labels.size()
	for ring in [0.25, 0.5, 0.75, 1.0]:
		var pts := PackedVector2Array()
		for i in n:
			pts.append(_point(i, ring, center, radius))
		pts.append(pts[0])
		draw_polyline(pts, FcUiTokens.BORDER, 1.0, true)
	for i in n:
		draw_line(center, _point(i, 1.0, center, radius), FcUiTokens.BORDER, 1.0)
	if ceilings.size() == n:
		var reach := PackedVector2Array()
		for i in n:
			reach.append(_point(i, float(ceilings[i]) / 99.0, center, radius))
		reach.append(reach[0])
		draw_polyline(reach, FcUiTokens.GOLD, 1.5, true)
	var shape := PackedVector2Array()
	for i in n:
		shape.append(_point(i, float(values[i]) / 99.0, center, radius))
	draw_colored_polygon(shape, Color(color, 0.25))
	var outline := PackedVector2Array(shape)
	outline.append(shape[0])
	draw_polyline(outline, color, 2.0, true)
	for p in shape:
		draw_circle(p, 3.0, color)
	for i in n:
		var text := str(labels[i])
		var p := _point(i, 1.0, center, radius + float(fs) * 1.1)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(p.x - w / 2.0, p.y + float(fs) * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, FcUiTokens.TEXT_MUTED)
