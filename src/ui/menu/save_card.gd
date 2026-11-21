class_name FcSaveCard
extends PanelContainer
## A saved game as a card (replacing the old table row): a tile in the mode's colour and icon, the save's name, "team, season, mode",
## when it was saved, a status chip (Ready, Backup only, Damaged) and its Load and Delete buttons. Selecting a card (click or focus)
## marks it; the main menu's Load/Delete/Continue act on the selected save. Built from the save's metadata only (FcSaveMetadata), so
## it needs no save to be loaded to be drawn.

signal selected(slot_id: String)
signal load_requested(slot_id: String)
signal delete_requested(slot_id: String)

const MODE_ICONS := {"owner": "house", "career": "user", "dynasty": "layers"}
const MODE_SKINS := {"owner": FcModeSkin.FRANCHISE, "career": FcModeSkin.BROADCAST, "dynasty": FcModeSkin.COLLECTIBLE}

var slot_id: String = ""
var is_selected: bool = false:
	set(value):
		is_selected = value
		_apply_style()
var load_button: FcButton
var delete_button: FcButton
var title_label: Label
var detail_label: Label
var saved_label: Label
var status_chip: FcStatusChip
var _accent: Color = FcUiTokens.PRIMARY


func _init(meta: FcSaveMetadata = null) -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_ALL
	if meta != null:
		_build(meta)


static func status_text(meta: FcSaveMetadata) -> String:
	if not meta.readable:
		return "Damaged"
	return "Ready"


static func detail_text(meta: FcSaveMetadata) -> String:
	var parts: Array = []
	if meta.team_name != "":
		parts.append(meta.team_name)
	if meta.season > 0:
		parts.append("Season %d-%02d" % [meta.season, (meta.season + 1) % 100])
	parts.append(str(meta.mode).capitalize())
	return "  ·  ".join(parts)


func _build(meta: FcSaveMetadata) -> void:
	slot_id = meta.slot_id
	var mode := str(meta.mode).to_lower()
	_accent = FcModeSkin.resolve(str(MODE_SKINS.get(mode, FcModeSkin.NEUTRAL)))["accent"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	add_child(row)
	var tile := PanelContainer.new()
	var tile_box := StyleBoxFlat.new()
	tile_box.bg_color = FcUiTokens.SURFACE_HIGH
	tile_box.border_color = _accent
	tile_box.set_border_width_all(1)
	tile_box.set_corner_radius_all(FcUiTokens.RADIUS_PANEL)
	tile_box.set_content_margin_all(10)
	tile.add_theme_stylebox_override("panel", tile_box)
	var icon := FcUiIcons.rect(str(MODE_ICONS.get(mode, "layers")), _accent, 26)
	tile.add_child(icon)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tile)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 1)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	title_label = FcUiTables.label(meta.label if meta.label != "" else meta.slot_id, FcUiTokens.TYPE_H3, true)
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(title_label)
	detail_label = FcUiTables.label(detail_text(meta), FcUiTokens.TYPE_SMALL)
	detail_label.theme_type_variation = "MutedLabel"
	detail_label.clip_text = true
	detail_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(detail_label)
	saved_label = FcUiTables.label("Saved %s" % str(meta.saved_at).replace("T", " "), FcUiTokens.TYPE_MICRO + 1)
	saved_label.theme_type_variation = "CaptionLabel"
	saved_label.clip_text = true
	saved_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(saved_label)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", FcUiTokens.SPACE_1)
	row.add_child(side)
	var ok := meta.readable
	status_chip = FcStatusChip.make(status_text(meta) + (" (backup kept)" if ok and meta.has_backup else ""), FcStatusChip.Tone.SUCCESS if ok else FcStatusChip.Tone.DANGER)
	side.add_child(status_chip)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", FcUiTokens.SPACE_1)
	load_button = FcButton.make("Load", FcButton.Variant.SECONDARY, func() -> void: load_requested.emit(slot_id))
	load_button.disabled = not ok
	buttons.add_child(load_button)
	delete_button = FcButton.make("", FcButton.Variant.ICON, func() -> void: delete_requested.emit(slot_id), "trash-2")
	delete_button.tooltip_text = "Delete this save"
	buttons.add_child(delete_button)
	side.add_child(buttons)
	tooltip_text = "%s: %s" % [title_label.text, detail_label.text]
	focus_entered.connect(func() -> void: selected.emit(slot_id))
	_apply_style()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		selected.emit(slot_id)
		if event.double_click and load_button != null and not load_button.disabled:
			load_requested.emit(slot_id)
	elif event.is_action_pressed("ui_accept") and has_focus() and load_button != null and not load_button.disabled:
		accept_event()
		load_requested.emit(slot_id)


func _apply_style() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = FcUiTokens.SURFACE_HIGH if is_selected else FcUiTokens.SURFACE_RAISED
	box.border_color = _accent if is_selected else FcUiTokens.BORDER
	box.set_border_width_all(2 if is_selected else 1)
	box.set_corner_radius_all(FcUiTokens.RADIUS_PANEL)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	add_theme_stylebox_override("panel", box)
