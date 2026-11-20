class_name FcCardFace
extends Control
## A collectible player card, drawn in ONE node (so hundreds fit on screen cheaply). It shows the overall rating, position, portrait
## (card art, or a monogram when there is none or it cannot be read), name, edition, rarity, badge count, copies, a NEW or other tag, and
## the mastery frame. Rarity changes the whole treatment (frame, background pattern, effects: see FcRarityStyle), not just the colour.
## States, each with its own look: hover (lift and a light sweep on rare and up), focus (a white ring: keyboard and controller), selected
## (an accent frame and a check: lineup and compare picks) and inspected (a gold glow: the card being examined). A card can be face down
## (the back of a card) and flip over (`flip_to`). Everything scales with the size, so one design serves mini to hero cards.
## Card ratings and content are never changed here: this only draws a card view (a row from FcCollectionQuery or the catalog).

signal activated

const SIZE_MINI := Vector2(75, 107)
const SIZE_SMALL := Vector2(112, 160)
const SIZE_STANDARD := Vector2(150, 214)
const SIZE_DETAIL := Vector2(225, 321)
const SIZE_HERO := Vector2(300, 428)
const SWEEP_SHADER := "res://assets/shaders/card_sweep.gdshader"

var row: Dictionary = {}
var tag: String = ""
var caption: String = ""
var face_down: bool = false
var selected: bool = false:
	set(v):
		selected = v
		queue_redraw()
var inspected: bool = false:
	set(v):
		inspected = v
		queue_redraw()
## 0 to 1: how far the pointer or focus lift has progressed (animated).
var lift: float = 0.0:
	set(v):
		lift = v
		queue_redraw()
var on_click: Callable = Callable()
var _sweep: ColorRect = null
var _hover_tween: Tween = null


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = SIZE_STANDARD
	mouse_entered.connect(func() -> void: _lift_to(1.0))
	mouse_exited.connect(func() -> void: _lift_to(1.0 if has_focus() else 0.0))
	focus_entered.connect(func() -> void:
		_lift_to(1.0)
		queue_redraw())
	focus_exited.connect(func() -> void:
		_lift_to(0.0)
		queue_redraw())


## Shows a card. `options`: size (Vector2), tag, caption, face_down, on_click (Callable), selected, inspected.
func setup(card_row: Dictionary, options: Dictionary = {}) -> FcCardFace:
	row = card_row
	custom_minimum_size = options.get("size", SIZE_STANDARD)
	tag = str(options.get("tag", ""))
	caption = str(options.get("caption", ""))
	face_down = bool(options.get("face_down", false))
	selected = bool(options.get("selected", false))
	inspected = bool(options.get("inspected", false))
	on_click = options.get("on_click", Callable())
	var owned: bool = bool(row.get("owned", true))
	var available: bool = bool(row.get("available", true))
	modulate = Color(1, 1, 1, 1) if (owned and available) or face_down else Color(1, 1, 1, 0.55)
	tooltip_text = "" if face_down else accessible_text()
	_ensure_sweep()
	queue_redraw()
	return self


static func size_for(kind: String) -> Vector2:
	return {"mini": SIZE_MINI, "small": SIZE_SMALL, "standard": SIZE_STANDARD, "detail": SIZE_DETAIL, "hero": SIZE_HERO}.get(kind, SIZE_STANDARD)


## The card in words (tooltip and screen readers): "Test Echo (Base Edition), Legendary, 87 overall, C".
func accessible_text() -> String:
	if face_down:
		return "A card, face down"
	var parts := ["%s (%s)" % [row.get("name", "?"), row.get("edition", "")], FcRarityStyle.label(str(row.get("rarity", "common"))), "%d overall" % int(row.get("overall", 0)), str(row.get("position", ""))]
	if not bool(row.get("available", true)):
		parts.append("unavailable")
	if not bool(row.get("owned", true)):
		parts.append("not owned")
	if tag != "":
		parts.append(tag.to_lower())
	return ", ".join(parts)


## Turns the card over: shrinks to the middle, swaps the face, grows back (a fade swap when motion is reduced). Returns the tween.
func flip_to(show_back: bool, seconds: float = FcUiTokens.DUR_SLOW) -> Tween:
	if face_down == show_back:
		return null
	pivot_offset = size / 2.0
	var d := FcMotion.duration(seconds)
	if d <= 0.0 or not is_inside_tree():
		face_down = show_back
		scale = Vector2.ONE
		queue_redraw()
		return null
	var tw := create_tween()
	tw.tween_property(self, "scale:x", 0.0, d / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		face_down = show_back
		queue_redraw())
	tw.tween_property(self, "scale:x", 1.0, d / 2.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tw


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or event.is_action_pressed("ui_accept"):
		activated.emit()
		if on_click.is_valid():
			on_click.call()
		accept_event()


# --- hover, lift and the light sweep ---------------------------------------------------------------------------------

func _lift_to(target: float) -> void:
	if face_down:
		return
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	pivot_offset = size / 2.0
	z_index = 1 if target > 0.0 else 0
	var d := FcMotion.duration(FcUiTokens.DUR_FAST + 0.05)
	if d <= 0.0 or not is_inside_tree():
		lift = target
		scale = Vector2.ONE * (1.0 + 0.04 * target)
		return
	_hover_tween = create_tween().set_parallel(true)
	_hover_tween.tween_property(self, "lift", target, d)
	_hover_tween.tween_property(self, "scale", Vector2.ONE * (1.0 + 0.04 * target), d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if target > 0.0 and _sweep != null and not FcMotion.reduced:
		var mat := _sweep.material as ShaderMaterial
		mat.set_shader_parameter("progress", -0.3)
		_hover_tween.tween_property(mat, "shader_parameter/progress", 1.3, 0.55)


func _ensure_sweep() -> void:
	var style := FcRarityStyle.of(str(row.get("rarity", "common")))
	if not bool(style["sweep"]) or face_down:
		if _sweep != null:
			_sweep.queue_free()
			_sweep = null
		return
	if _sweep != null or not ResourceLoader.exists(SWEEP_SHADER):
		return
	_sweep = ColorRect.new()
	_sweep.color = Color.WHITE
	_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sweep.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sweep.offset_left = 4
	_sweep.offset_top = 4
	_sweep.offset_right = -4
	_sweep.offset_bottom = -4
	var mat := ShaderMaterial.new()
	mat.shader = load(SWEEP_SHADER)
	mat.set_shader_parameter("tint", FcRarityStyle.color(str(row.get("rarity", "common"))).lightened(0.5))
	_sweep.material = mat
	add_child(_sweep)


# --- drawing ---------------------------------------------------------------------------------------------------------

func _draw() -> void:
	var s := size.x / 150.0
	if face_down:
		_draw_back(s)
		return
	var rarity := str(row.get("rarity", "common"))
	var style := FcRarityStyle.of(rarity)
	var color: Color = style["color"]
	var dark: Color = style["dark"]
	var radius := int(10 * s)
	var rect := Rect2(Vector2.ZERO, size)
	# shadow and glow
	if lift > 0.0:
		_outline(rect.grow(2 * s), int(12 * s), Color(color, 0.35 * lift), 3.0 * s)
	if inspected:
		for i in 3:
			_outline(rect.grow((3 + i * 3) * s), int((12 + i * 3) * s), Color(FcUiTokens.GOLD, 0.34 - i * 0.1), 2.0 * s)
	# body
	var body := StyleBoxFlat.new()
	body.bg_color = dark.lerp(FcUiTokens.SURFACE_RAISED, 0.35)
	body.set_corner_radius_all(radius)
	draw_style_box(body, rect)
	var art := Rect2(8 * s, 36 * s, 134 * s, 100 * s)
	_draw_pattern(str(style["pattern"]), art, color, dark, s)
	_draw_portrait(art, color, s)
	_draw_frame(str(style["frame"]), rect, color, radius, s)
	var mastery := int(row.get("mastery", 0))
	if mastery > 0:
		_outline(rect.grow(-1.5 * s), radius, FcRarityStyle.mastery_color(mastery), 2.5 * s)
	_draw_text(rect, color, s)
	if str(style["pattern"]) == "holo":
		_draw_holo_wash(rect, s)
	if selected:
		_outline(rect.grow(-1 * s), radius, FcUiTheme.accent, 4.0 * s)
		draw_circle(Vector2(size.x - 14 * s, 14 * s), 11 * s, FcUiTheme.accent)
		var check := FcUiIcons.texture("check")
		if check != null:
			draw_texture_rect(check, Rect2(size.x - 22 * s, 6 * s, 16 * s, 16 * s), false, FcUiContrast.readable_on(FcUiTheme.accent))
	if has_focus():
		_outline(rect.grow(3), radius + 2, FcUiTokens.TEXT, 2.0)


func _outline(rect: Rect2, radius: int, color: Color, width: float) -> void:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = color
	box.set_border_width_all(maxi(1, roundi(width)))
	box.set_corner_radius_all(radius)
	draw_style_box(box, rect)


func _draw_pattern(pattern: String, art: Rect2, color: Color, dark: Color, s: float) -> void:
	var top := dark.lightened(0.12)
	var bottom := dark.darkened(0.25)
	# the portrait well: a vertical gradient (stronger on rare and up)
	var strong := pattern in ["gradient", "rays", "holo"]
	var colors := PackedColorArray([top.lerp(color, 0.22 if strong else 0.08), top.lerp(color, 0.22 if strong else 0.08), bottom, bottom])
	draw_polygon(PackedVector2Array([art.position, art.position + Vector2(art.size.x, 0), art.end, art.position + Vector2(0, art.size.y)]), colors)
	match pattern:
		"diagonal":
			var x := -art.size.y
			while x < art.size.x:
				# a line rising to the right from (x, bottom) to (x + height, top), clipped to the portrait well
				var from := Vector2(x, art.size.y)
				var to := Vector2(x + art.size.y, 0.0)
				if from.x < 0.0:
					from = Vector2(0.0, art.size.y + from.x)
				if to.x > art.size.x:
					to = Vector2(art.size.x, to.x - art.size.x)
				draw_line(art.position + from, art.position + to, Color(color, 0.10), maxf(1.0, s))
				x += 12 * s
		"rays":
			var origin := art.position + Vector2(art.size.x / 2.0, art.size.y * 0.55)
			for i in 12:
				var angle := -PI + i * PI / 11.0
				var tip := origin + Vector2(cos(angle), sin(angle)) * _ray_length(origin, angle, art)
				var edge := origin + Vector2(cos(angle + 0.07), sin(angle + 0.07)) * _ray_length(origin, angle + 0.07, art)
				draw_polygon(PackedVector2Array([origin, tip, edge]), PackedColorArray([Color(color, 0.0), Color(color, 0.16), Color(color, 0.16)]))
		"holo":
			var bands := [Color("FF6EC7"), Color("FFD166"), Color("6EE7B7"), Color("6EC6FF"), Color("B8A1FF")]
			for i in bands.size():
				var x0 := art.position.x + art.size.x * i / bands.size()
				var x1 := art.position.x + art.size.x * (i + 1) / bands.size()
				draw_polygon(PackedVector2Array([Vector2(x0, art.position.y), Vector2(x1, art.position.y), Vector2(x1 - 14 * s, art.end.y), Vector2(x0 - 14 * s, art.end.y)]), PackedColorArray([Color(bands[i], 0.16), Color(bands[i], 0.16), Color(bands[i], 0.05), Color(bands[i], 0.05)]))


## How far a ray from `origin` at `angle` runs before it meets the edge of the portrait well (so light never spills out of the card).
func _ray_length(origin: Vector2, angle: float, art: Rect2) -> float:
	var dir := Vector2(cos(angle), sin(angle))
	var best := art.size.x
	if dir.y < -0.001:
		best = minf(best, (origin.y - art.position.y) / -dir.y)
	elif dir.y > 0.001:
		best = minf(best, (art.end.y - origin.y) / dir.y)
	if dir.x > 0.001:
		best = minf(best, (art.end.x - origin.x) / dir.x)
	elif dir.x < -0.001:
		best = minf(best, (origin.x - art.position.x) / -dir.x)
	return best


func _draw_portrait(art: Rect2, color: Color, s: float) -> void:
	var tex := FcDynastyStyle.art_texture(str(row.get("art_path", "")))
	if tex != null:
		var tw := float(tex.get_width())
		var th := float(tex.get_height())
		var scale_fit := maxf(art.size.x / tw, art.size.y / th)
		var src_size := art.size / scale_fit
		var src := Rect2((Vector2(tw, th) - src_size) / 2.0, src_size)
		draw_texture_rect_region(tex, art, src)
		return
	var font := _font(FcUiFonts.display(700))
	var initials := FcDynastyStyle.initials(str(row.get("name", "?")))
	var fs := int(46 * s)
	var width := font.get_string_size(initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(art.position.x + (art.size.x - width) / 2.0, art.position.y + art.size.y * 0.66), initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(color, 0.85))


func _draw_frame(frame: String, rect: Rect2, color: Color, radius: int, s: float) -> void:
	match frame:
		"plain":
			_outline(rect, radius, color, 2.0 * s)
		"double":
			_outline(rect, radius, color, 2.0 * s)
			_outline(rect.grow(-5 * s), maxi(2, radius - 4), Color(color, 0.55), maxf(1.0, s))
		"bevel":
			_outline(rect, radius, color.darkened(0.15), 3.0 * s)
			draw_line(Vector2(radius, 3.5 * s), Vector2(size.x - radius, 3.5 * s), color.lightened(0.55), maxf(1.0, s))
			draw_line(Vector2(3.5 * s, radius), Vector2(3.5 * s, size.y - radius), color.lightened(0.4), maxf(1.0, s))
			draw_line(Vector2(radius, size.y - 3.5 * s), Vector2(size.x - radius, size.y - 3.5 * s), color.darkened(0.45), maxf(1.0, s))
		"ornate":
			_outline(rect, radius, color, 3.0 * s)
			var arm := 14 * s
			for corner: Vector2 in [Vector2(0, 0), Vector2(size.x, 0), Vector2(0, size.y), Vector2(size.x, size.y)]:
				var dx := 1.0 if corner.x == 0.0 else -1.0
				var dy := 1.0 if corner.y == 0.0 else -1.0
				var p := corner + Vector2(7 * s * dx, 7 * s * dy)
				draw_line(p, p + Vector2(arm * dx, 0), color.lightened(0.4), 1.5 * s)
				draw_line(p, p + Vector2(0, arm * dy), color.lightened(0.4), 1.5 * s)
			var top := Vector2(size.x / 2.0, 2 * s)
			draw_polygon(PackedVector2Array([top + Vector2(0, -1), top + Vector2(6 * s, 5 * s), top + Vector2(0, 11 * s), top + Vector2(-6 * s, 5 * s)]), PackedColorArray([color.lightened(0.5)]))
		"foil":
			_outline(rect, radius, color, 4.0 * s)
			_outline(rect.grow(-4 * s), maxi(2, radius - 3), color.lightened(0.6), maxf(1.0, s))
			_outline(rect.grow(-7 * s), maxi(2, radius - 6), Color(color, 0.5), maxf(1.0, s))


func _draw_text(rect: Rect2, color: Color, s: float) -> void:
	var display := _font(FcUiFonts.display(700))
	var name_font := _font(FcUiFonts.display(600))
	var body := _font(FcUiFonts.body(500))
	# top: overall and position
	var overall := int(row.get("overall", 0))
	var show_overall := bool(row.get("available", true)) or overall > 0
	draw_string(display, Vector2(10 * s, 31 * s), str(overall) if show_overall else "--", HORIZONTAL_ALIGNMENT_LEFT, -1, int(31 * s), color)
	var pos := str(row.get("position", ""))
	if str(row.get("secondary", "")) != "":
		pos += "/" + str(row["secondary"])
	var pos_w := body.get_string_size(pos, HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * s)).x
	draw_string(body, Vector2(size.x - 10 * s - pos_w, 24 * s), pos, HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * s), FcUiTokens.TEXT_MUTED)
	var team := str(row.get("team", ""))
	if team != "":
		draw_string(body, Vector2(size.x - 10 * s - minf(body.get_string_size(team, HORIZONTAL_ALIGNMENT_LEFT, -1, int(9 * s)).x, 60 * s), 33 * s), _fit(team, body, int(9 * s), 60 * s), HORIZONTAL_ALIGNMENT_LEFT, -1, int(9 * s), Color(FcUiTokens.TEXT_MUTED, 0.8))
	# name plate
	draw_string(name_font, Vector2(10 * s, 157 * s), _fit(str(row.get("name", "?")), name_font, int(16 * s), size.x - 20 * s), HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * s), FcUiTokens.TEXT)
	draw_string(body, Vector2(10 * s, 171 * s), _fit(str(row.get("edition", "")), body, int(10 * s), size.x - 20 * s), HORIZONTAL_ALIGNMENT_LEFT, -1, int(10 * s), FcUiTokens.TEXT_MUTED)
	# footer: caption (price) or the rarity on the left; badges, copies and the tag on the right
	var footer_y := 192 * s
	var left_text := caption if caption != "" else FcRarityStyle.label(str(row.get("rarity", "common")))
	draw_string(body, Vector2(10 * s, footer_y), _fit(left_text, body, int(11 * s), size.x * (0.66 if caption != "" else 0.5)), HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * s), FcUiTokens.GOLD if caption != "" else color)
	var bits: Array[String] = []
	var badges: Array = row.get("badges", [])
	if not badges.is_empty() and caption == "":   # a caption (a price, what a duplicate is worth) needs the room
		bits.append("%d badge%s" % [badges.size(), "" if badges.size() == 1 else "s"])
	if int(row.get("quantity", 0)) > 1:
		bits.append("x%d" % int(row["quantity"]))
	if not bits.is_empty():
		var text := "  ".join(bits)
		draw_string(body, Vector2(size.x - 10 * s - body.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * s)).x, footer_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * s), FcUiTokens.TEXT_MUTED)
	# the tag: NEW is a pill over the portrait; the others sit at the very bottom
	var shown_tag := tag
	if not bool(row.get("available", true)):
		shown_tag = "UNAVAILABLE"
	elif not bool(row.get("owned", true)) and shown_tag == "":
		shown_tag = "NOT OWNED"
	if shown_tag == "NEW":
		var pill := Rect2(12 * s, 42 * s, 34 * s, 16 * s)
		var box := StyleBoxFlat.new()
		box.bg_color = FcUiTokens.SUCCESS
		box.set_corner_radius_all(int(8 * s))
		draw_style_box(box, pill)
		draw_string(body, pill.position + Vector2(7 * s, 12 * s), "NEW", HORIZONTAL_ALIGNMENT_LEFT, -1, int(10 * s), FcUiTokens.BG)
	elif shown_tag != "":
		var tag_color := FcUiTokens.DANGER if shown_tag == "UNAVAILABLE" else FcUiTokens.TEXT_MUTED
		var tag_w := body.get_string_size(shown_tag, HORIZONTAL_ALIGNMENT_LEFT, -1, int(10 * s)).x
		draw_string(body, Vector2((size.x - tag_w) / 2.0, 208 * s), shown_tag, HORIZONTAL_ALIGNMENT_LEFT, -1, int(10 * s), tag_color)


func _draw_holo_wash(rect: Rect2, s: float) -> void:
	var colors := PackedColorArray([Color(1, 0.5, 0.8, 0.07), Color(1, 0.85, 0.4, 0.07), Color(0.4, 0.9, 0.8, 0.07), Color(0.5, 0.7, 1, 0.07)])
	draw_polygon(PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)]), colors)


func _draw_back(s: float) -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var body := StyleBoxFlat.new()
	body.bg_color = FcUiTokens.SURFACE
	body.set_corner_radius_all(int(10 * s))
	draw_style_box(body, rect)
	_outline(rect, int(10 * s), FcUiTokens.BORDER, 2.0 * s)
	_outline(rect.grow(-6 * s), int(7 * s), Color(FcUiTheme.accent, 0.55), maxf(1.0, s))
	# court lines: a centre circle, the keys and a half-court line
	var c := size / 2.0
	var line := Color(FcUiTokens.BORDER, 0.9)
	draw_arc(c, 30 * s, 0.0, TAU, 40, line, 1.5 * s, true)
	draw_line(Vector2(12 * s, c.y), Vector2(size.x - 12 * s, c.y), line, 1.5 * s)
	draw_rect(Rect2(c.x - 24 * s, 12 * s, 48 * s, 40 * s), line, false, 1.5 * s)
	draw_rect(Rect2(c.x - 24 * s, size.y - 52 * s, 48 * s, 40 * s), line, false, 1.5 * s)
	var font := _font(FcUiFonts.display(700))
	var fs := int(34 * s)
	var w := font.get_string_size("FC", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(c.x - w / 2.0, c.y + 12 * s), "FC", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, FcUiTheme.accent)
	if has_focus():
		_outline(rect.grow(3), int(12 * s), FcUiTokens.TEXT, 2.0)


func _font(f: Font) -> Font:
	return f if f != null else ThemeDB.fallback_font


## Trims text with an ellipsis so it fits `max_width` pixels.
func _fit(text: String, font: Font, font_size: int, max_width: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return text
	var out := text
	while out.length() > 1 and font.get_string_size(out + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
		out = out.substr(0, out.length() - 1)
	return out + "..."
