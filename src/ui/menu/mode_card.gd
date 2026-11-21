class_name FcModeCard
extends PanelContainer
## One of the three big cards on the main menu: the mode's own picture (FcModeArt), a status chip, the mode name, a sentence about it and
## the button that opens it. The whole card is a click target as well (and shows its edge in the mode colour on hover and focus), the
## button inside keeps the keyboard and screen-reader path. Each mode has its own composition and accent; nothing here is game data.

signal chosen

var mode_name: String
var art: FcModeArt
var button: FcButton
var _accent: Color
var _hover := false


## `kind` is "owner", "career" or "dynasty"; `skin_id` an FcModeSkin id (its accent colours the card).
func _init(kind: String = "owner", title: String = "", blurb: String = "", status: String = "", tone: FcStatusChip.Tone = FcStatusChip.Tone.INFO, skin_id: String = FcModeSkin.NEUTRAL,
		art_height: int = 200) -> void:
	mode_name = title
	_accent = FcModeSkin.resolve(skin_id)["accent"]
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	add_child(column)
	art = FcModeArt.new(kind, _accent)
	art.custom_minimum_size.y = art_height
	column.add_child(art)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	var margin := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, FcUiTokens.SPACE_4)
	margin.add_child(text)
	column.add_child(margin)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	var name_label := FcUiTables.label(title, FcUiTokens.TYPE_H1, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	head.add_child(FcStatusChip.make(status, tone))
	text.add_child(head)
	var blurb_label := FcUiTables.label(blurb, FcUiTokens.TYPE_SMALL + 1)
	blurb_label.theme_type_variation = "MutedLabel"
	blurb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb_label.custom_minimum_size.y = FcUiTokens.fs(FcUiTokens.TYPE_SMALL + 1) * 4.3   # room for three lines, so the three cards are one height
	text.add_child(blurb_label)
	button = FcButton.make(title, FcButton.Variant.PRIMARY, func() -> void: chosen.emit())
	text.add_child(button)
	_apply_style()
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	button.focus_entered.connect(_apply_style)
	button.focus_exited.connect(_apply_style)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		chosen.emit()


func _on_hover(inside: bool) -> void:
	_hover = inside
	_apply_style()


func _apply_style() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = FcUiTokens.SURFACE_RAISED
	var lit := _hover or (button != null and button.has_focus())
	box.border_color = _accent if lit else FcUiTokens.BORDER
	box.set_border_width_all(2 if lit else 1)
	box.set_corner_radius_all(FcUiTokens.RADIUS_MODAL)
	box.set_content_margin_all(0)
	box.set_expand_margin_all(0)
	FcUiTokens.elevate(box, 2 if lit else 1)
	add_theme_stylebox_override("panel", box)
