class_name FcStackedBar
extends VBoxContainer
## A part-of-a-whole chart for money (where revenue comes from, where it goes): one horizontal bar cut into segments, and under it a legend with
## a colour swatch, the name, the amount and the share of every part. The numbers are always written out, so the colours never carry meaning
## alone. It draws only the parts it is given (zero parts are left out of the bar but listed); with no positive total it shows nothing.

var parts: Array = []
var total: float = 0.0
var _bar := _Bar.new()
var _legend := VBoxContainer.new()
var _format: Callable = Callable()


func _init(format: Callable = Callable()) -> void:
	_format = format
	add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	_bar.custom_minimum_size = Vector2(160, 22)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_bar)
	_legend.add_theme_constant_override("separation", 2)
	add_child(_legend)


## `part_list`: [{"label": String, "value": number}]. Sorted largest first; the bar and the legend are rebuilt.
func set_parts(part_list: Array) -> void:
	parts = part_list.duplicate()
	parts.sort_custom(func(a, b): return float(a["value"]) > float(b["value"]))
	total = 0.0
	for p in parts:
		total += maxf(0.0, float(p["value"]))
	_bar.segments = []
	for c in _legend.get_children():
		_legend.remove_child(c)
		c.queue_free()
	for i in parts.size():
		var value := float(parts[i]["value"])
		var color: Color = FcUiTokens.CHART[i % FcUiTokens.CHART.size()]
		if value > 0.0 and total > 0.0:
			_bar.segments.append({"color": color, "share": value / total, "text": "%s: %s" % [parts[i]["label"], _text(value)]})
		_legend.add_child(_legend_row(color, str(parts[i]["label"]), value))
	_bar.tooltip_text = ", ".join(_bar.segments.map(func(s: Dictionary) -> String: return str(s["text"])))
	_bar.queue_redraw()


func segment_count() -> int:
	return _bar.segments.size()


func legend_texts() -> Array:
	var out: Array = []
	for row in _legend.get_children():
		out.append((row.get_child(1) as Label).text + " " + (row.get_child(2) as Label).text)
	return out


func _text(value: float) -> String:
	return str(_format.call(value)) if _format.is_valid() else str(value)


func _legend_row(color: Color, label: String, value: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	var swatch := ColorRect.new()
	swatch.color = color
	swatch.custom_minimum_size = Vector2(12, 12)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(swatch)
	var name_label := FcUiTables.label(label, FcUiTokens.TYPE_SMALL)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var share := (" (%d%%)" % roundi(value / total * 100.0)) if total > 0.0 and value > 0.0 else ""
	var amount := FcUiTables.label("%s%s" % [_text(value), share], FcUiTokens.TYPE_SMALL)
	amount.theme_type_variation = "NumericLabel"
	row.add_child(amount)
	return row


## The bar itself.
class _Bar extends Control:
	var segments: Array = []

	func _draw() -> void:
		var track := StyleBoxFlat.new()
		track.bg_color = FcUiTokens.BORDER
		track.set_corner_radius_all(4)
		draw_style_box(track, Rect2(Vector2.ZERO, size))
		var x := 0.0
		for i in segments.size():
			var seg: Dictionary = segments[i]
			var w := size.x * float(seg["share"])
			var rect := Rect2(x, 0, maxf(1.0, w - 1.0), size.y)
			var box := StyleBoxFlat.new()
			box.bg_color = seg["color"]
			box.corner_radius_top_left = 4 if i == 0 else 0
			box.corner_radius_bottom_left = 4 if i == 0 else 0
			box.corner_radius_top_right = 4 if i == segments.size() - 1 else 0
			box.corner_radius_bottom_right = 4 if i == segments.size() - 1 else 0
			draw_style_box(box, rect)
			x += w
