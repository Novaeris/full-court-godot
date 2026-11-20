class_name FcUniformPreview
extends Control
## The player's uniform: a jersey and shorts in the team's colours with the jersey number (or the team letters). Built from the resolved
## visual's `uniform` (team branding colours; a palette colour when a team has none), so it matches the figure's jersey exactly.
## Equipment (shoes, accessories) has no data anywhere in the game and is not shown.

var uniform: Dictionary = {}


func _init() -> void:
	custom_minimum_size = Vector2(72, 96)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(visual: Dictionary, pixels_wide: int = 72) -> FcUniformPreview:
	uniform = visual["uniform"]
	custom_minimum_size = Vector2(pixels_wide, pixels_wide * 1.33)
	queue_redraw()
	return self


func _draw() -> void:
	if uniform.is_empty():
		return
	var w := size.x
	var primary: Color = uniform["primary"]
	var secondary: Color = uniform["secondary"]
	var cx := w / 2.0
	var jersey_h := size.y * 0.62
	# jersey: shoulders, armholes and a neckline
	draw_polygon(PackedVector2Array([Vector2(cx - w * 0.32, 0), Vector2(cx - w * 0.14, 0), Vector2(cx, w * 0.16), Vector2(cx + w * 0.14, 0), Vector2(cx + w * 0.32, 0),
		Vector2(cx + w * 0.4, w * 0.18), Vector2(cx + w * 0.3, w * 0.22), Vector2(cx + w * 0.34, jersey_h), Vector2(cx - w * 0.34, jersey_h), Vector2(cx - w * 0.3, w * 0.22), Vector2(cx - w * 0.4, w * 0.18)]), PackedColorArray([primary]))
	draw_line(Vector2(cx - w * 0.14, 0), Vector2(cx, w * 0.16), secondary, maxf(2.0, w * 0.04))
	draw_line(Vector2(cx + w * 0.14, 0), Vector2(cx, w * 0.16), secondary, maxf(2.0, w * 0.04))
	var font := FcUiFonts.display(700)
	if font == null:
		font = ThemeDB.fallback_font
	var text := str(uniform["number"]) if int(uniform["number"]) > 0 else str(uniform["abbreviation"]).substr(0, 3)
	if text != "":
		var fs := int(w * 0.34)
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(cx - tw / 2.0, w * 0.2 + fs), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, secondary)
	# shorts
	var shorts_top := jersey_h + w * 0.04
	draw_polygon(PackedVector2Array([Vector2(cx - w * 0.3, shorts_top), Vector2(cx + w * 0.3, shorts_top), Vector2(cx + w * 0.36, size.y), Vector2(cx + w * 0.04, size.y), Vector2(cx, shorts_top + w * 0.2),
		Vector2(cx - w * 0.04, size.y), Vector2(cx - w * 0.36, size.y)]), PackedColorArray([primary.darkened(0.12)]))
	draw_line(Vector2(cx - w * 0.3, shorts_top), Vector2(cx + w * 0.3, shorts_top), secondary, maxf(2.0, w * 0.04))
