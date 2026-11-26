class_name FcRaceTable
extends VBoxContainer
## A ranked race (the MVP race, Rookie of the Year, a playoff race, power rankings): one row per entry with its rank, movement since the
## last update (▲ 2, ▼ 1, –), a crest or a portrait, the name and a secondary line, the score on the right and the gap to the leader. The
## leader's row is accented. It shows the ranking it is given; the league code computes it from real statistics.

signal entry_activated(entry_id: int)

const ROW_HEIGHT := 48

var entries: Array = []


func _init() -> void:
	add_theme_constant_override("separation", 2)


## `rows`: [{"id": int, "name": String, "detail": String, "value": String, "gap": String, "move": int (positive = up),
##   "team_look": Dictionary (optional), "player": Dictionary (portrait subject, optional), "mark": String (e.g. "x" clinched)}].
func set_entries(rows: Array, empty_text: String = "Nothing to rank yet") -> FcRaceTable:
	entries = rows
	for c in get_children():
		remove_child(c)
		c.queue_free()
	if rows.is_empty():
		var l := Label.new()
		l.text = empty_text
		l.theme_type_variation = "MutedLabel"
		add_child(l)
		return self
	for i in rows.size():
		add_child(_row(i + 1, rows[i]))
	return self


static func move_text(move: int) -> String:
	if move > 0:
		return "▲ %d" % move
	if move < 0:
		return "▼ %d" % -move
	return "–"


func _row(rank: int, e: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = FcUiTokens.SURFACE_RAISED if rank > 1 else Color(FcUiTokens.GOLD, 0.14)
	style.set_corner_radius_all(FcUiTokens.RADIUS_CONTROL)
	style.content_margin_left = FcUiTokens.SPACE_2
	style.content_margin_right = FcUiTokens.SPACE_3
	if rank == 1:
		style.border_color = FcUiTokens.GOLD
		style.border_width_left = 3
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.y = ROW_HEIGHT
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			entry_activated.emit(int(e.get("id", 0))))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	panel.add_child(row)
	var rank_label := Label.new()
	rank_label.text = str(rank)
	rank_label.theme_type_variation = "DisplayLabel"
	rank_label.custom_minimum_size.x = 34
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rank_label)
	var move := int(e.get("move", 0))
	var move_label := Label.new()
	move_label.text = move_text(move)
	move_label.theme_type_variation = "CaptionLabel"
	move_label.custom_minimum_size.x = 36
	move_label.add_theme_color_override("font_color", FcUiTokens.SUCCESS if move > 0 else (FcUiTokens.DANGER if move < 0 else FcUiTokens.TEXT_MUTED))
	move_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(move_label)
	var player: Dictionary = e.get("player", {})
	var look: Dictionary = e.get("team_look", {})
	if not player.is_empty():
		var portrait := FcPlayerPortrait.new().setup(player, 40)
		portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(portrait)
	elif not look.is_empty():
		var crest := FcTeamCrest.new().setup(look, 32, false)
		crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(crest)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name := Label.new()
	name.text = str(e.get("name", "")) + (("  " + str(e["mark"])) if str(e.get("mark", "")) != "" else "")
	name.clip_text = true
	text.add_child(name)
	if str(e.get("detail", "")) != "":
		var detail := Label.new()
		detail.text = str(e["detail"])
		detail.theme_type_variation = "CaptionLabel"
		detail.clip_text = true
		text.add_child(detail)
	row.add_child(text)
	var value := Label.new()
	value.text = str(e.get("value", ""))
	value.theme_type_variation = "NumericLabel"
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(value)
	if str(e.get("gap", "")) != "":
		var gap := Label.new()
		gap.text = str(e["gap"])
		gap.theme_type_variation = "CaptionLabel"
		gap.custom_minimum_size.x = 56
		gap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		gap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(gap)
	panel.tooltip_text = "%d. %s %s %s" % [rank, e.get("name", ""), e.get("value", ""), e.get("detail", "")]
	return panel
