class_name FcCardView
extends RefCounted
## The player card: the visual centre of Dynasty Mode. Rarity colours the frame; the overall rating, position, name and edition
## are readable at a glance; artwork fills the middle (a polished initials fallback when there is none or it cannot be read).
## A card row from FcCollectionQuery (or a plain card view) goes in; a clickable, keyboard-focusable Control comes out.

const SIZE := Vector2(150, 214)
const SMALL := Vector2(112, 160)


## `row` is a card view, optionally with owned/quantity/mastery (collection rows). `options`: size (Vector2),
## on_click (Callable), caption (extra line under the name, e.g. a price), tag (a small badge such as NEW or DUPLICATE),
## face_down (draw the back of a card for pack reveals).
static func build(row: Dictionary, options: Dictionary = {}) -> Control:
	var size: Vector2 = options.get("size", SIZE)
	var rarity := str(row.get("rarity", "common"))
	var color := FcDynastyStyle.rarity_color(rarity)
	var owned: bool = bool(row.get("owned", true))
	var available: bool = bool(row.get("available", true))
	var mastery := int(row.get("mastery", 0))
	var frame_color := color
	if mastery > 0:
		frame_color = FcDynastyStyle.FRAME_COLORS.get(_frame_name(mastery), color)
	var card := PanelContainer.new()
	card.custom_minimum_size = size
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("panel", FcDynastyStyle.box(FcUiTheme.SURFACE_RAISED, frame_color, 3 if mastery > 0 else 2, 10, 6))
	if options.get("face_down", false):
		var back := Label.new()
		back.text = "?"
		back.add_theme_font_size_override("font_size", 56)
		back.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		back.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		card.add_child(back)
		card.add_theme_stylebox_override("panel", FcDynastyStyle.box(FcUiTheme.SURFACE, FcUiTheme.BORDER, 2, 10, 6))
		return card
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ovr := Label.new()
	ovr.text = str(int(row.get("overall", 0))) if available or int(row.get("overall", 0)) > 0 else "--"
	ovr.add_theme_font_size_override("font_size", 26)
	ovr.add_theme_color_override("font_color", color)
	top.add_child(ovr)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var pos := Label.new()
	var pos_text := str(row.get("position", ""))
	if str(row.get("secondary", "")) != "":
		pos_text += "/" + str(row["secondary"])
	pos.text = pos_text
	pos.add_theme_font_size_override("font_size", 13)
	pos.add_theme_color_override("font_color", FcUiTheme.TEXT_MUTED)
	top.add_child(pos)
	v.add_child(top)
	v.add_child(_art(row, color, size))
	var name := Label.new()
	name.text = str(row.get("name", "?"))
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.add_theme_font_size_override("font_size", 14)
	v.add_child(name)
	var edition := Label.new()
	edition.text = str(row.get("edition", ""))
	edition.clip_text = true
	edition.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	edition.add_theme_font_size_override("font_size", 11)
	edition.add_theme_color_override("font_color", FcUiTheme.TEXT_MUTED)
	v.add_child(edition)
	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rare := Label.new()
	rare.text = FcDynastyStyle.rarity_label(rarity)
	rare.add_theme_font_size_override("font_size", 11)
	rare.add_theme_color_override("font_color", color)
	bottom.add_child(rare)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp2)
	var extra := Label.new()
	extra.add_theme_font_size_override("font_size", 11)
	var badges: Array = row.get("badges", [])
	var bits: Array[String] = []
	if not badges.is_empty():
		bits.append("%d badge%s" % [badges.size(), "" if badges.size() == 1 else "s"])
	if int(row.get("quantity", 0)) > 1:
		bits.append("x%d" % int(row["quantity"]))
	extra.text = "  ".join(bits)
	bottom.add_child(extra)
	v.add_child(bottom)
	var caption := str(options.get("caption", ""))
	if caption != "":
		var cap := Label.new()
		cap.text = caption
		cap.add_theme_font_size_override("font_size", 12)
		cap.add_theme_color_override("font_color", FcUiTheme.HEADING)
		v.add_child(cap)
	var tag := str(options.get("tag", ""))
	if not available:
		tag = "UNAVAILABLE"
	elif not owned and tag == "":
		tag = "NOT OWNED"
	if tag != "":
		var t := Label.new()
		t.text = tag
		t.add_theme_font_size_override("font_size", 11)
		t.add_theme_color_override("font_color", FcUiTheme.GOOD if tag in ["NEW"] else (FcUiTheme.BAD if tag == "UNAVAILABLE" else FcUiTheme.TEXT_MUTED))
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(t)
	if not owned or not available:
		card.modulate = Color(1, 1, 1, 0.55)
	if options.has("on_click"):
		var cb: Callable = options["on_click"]
		card.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				cb.call()
			elif event.is_action_pressed("ui_accept"):
				cb.call())
	card.tooltip_text = "%s (%s), %d overall" % [row.get("name", ""), row.get("edition", ""), int(row.get("overall", 0))]
	return card


static func _frame_name(level: int) -> String:
	return ["none", "bronze", "silver", "gold", "platinum", "diamond"][clampi(level, 0, 5)]


static func _art(row: Dictionary, color: Color, size: Vector2) -> Control:
	var holder := PanelContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.custom_minimum_size = Vector2(0, size.y * 0.42)
	holder.add_theme_stylebox_override("panel", FcDynastyStyle.box(color.darkened(0.7), color.darkened(0.3), 1, 6, 2))
	var tex := FcDynastyStyle.art_texture(str(row.get("art_path", "")))
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(rect)
	else:
		var initials := Label.new()
		initials.text = FcDynastyStyle.initials(str(row.get("name", "?")))
		initials.add_theme_font_size_override("font_size", int(size.y * 0.2))
		initials.add_theme_color_override("font_color", color)
		initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initials.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(initials)
	return holder
