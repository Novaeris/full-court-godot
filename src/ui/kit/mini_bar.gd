class_name FcMiniBar
extends Control
## A thin horizontal bar for a table cell (a contract's years used, a health or confidence meter). 0 to 1 filled, in a tone colour.
## The number it shows is always also readable as text by the caller (tooltip), so the bar is never the only carrier of meaning.

var ratio: float = 0.0
var color: Color = FcUiTokens.INFO


func _init() -> void:
	custom_minimum_size = Vector2(40, 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_ratio(value: float, tone: Color = FcUiTokens.INFO) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, ratio) and tone == color:
		return
	ratio = clamped
	color = tone
	queue_redraw()


func _draw() -> void:
	var h := minf(size.y, 8.0)
	var y := (size.y - h) / 2.0
	var track := StyleBoxFlat.new()
	track.bg_color = FcUiTokens.BORDER
	track.set_corner_radius_all(int(h / 2.0))
	draw_style_box(track, Rect2(0, y, size.x, h))
	if ratio > 0.0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = color
		fill.set_corner_radius_all(int(h / 2.0))
		draw_style_box(fill, Rect2(0, y, maxf(h, size.x * ratio), h))
