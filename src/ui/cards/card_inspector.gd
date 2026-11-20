class_name FcCardInspector
extends FcModal
## Examines one card: a large card you can zoom (the + and - buttons or the mouse wheel over it) and turn over, its rating, rarity, team,
## badges with their descriptions, every attribute with a bar coloured by its rating tier, the player's results in your games, and the
## actions for duplicates (convert to shards, raise mastery: the same controller calls as before) plus Compare. Previous and Next (and the
## left and right keys) move through the cards the collection screen was showing. Opening a card marks it as seen (it loses its NEW marker).
## Escape closes it. The card is read from the Dynasty controller; the inspector never changes a card's data.

const ZOOM_SIZES := [FcCardFace.SIZE_STANDARD, FcCardFace.SIZE_DETAIL, FcCardFace.SIZE_HERO]

var _ui: FcDynastyUi
var _ids: Array = []
var _pos: int = 0
var _zoom: int = 1
var _body: Control
var _hero: FcCardFace = null


func _init(ui: FcDynastyUi = null, card_ids: Array = [], start_card: String = "") -> void:
	super("", "", Kind.INFO, "Close")
	_ui = ui
	_ids = card_ids
	_pos = maxi(0, card_ids.find(start_card))
	if ui == null:
		return
	panel.custom_minimum_size.x = 760
	_body = VBoxContainer.new()
	content.add_child(_body)
	_fill()


## Opens the inspector on `card_id`; `ids` is the list Previous and Next walk through (the collection's current view).
static func open_for(ui: FcDynastyUi, card_id: String, ids: Array = []) -> FcCardInspector:
	var list := ids if ids.has(card_id) else [card_id]
	var modal := FcCardInspector.new(ui, list, card_id)
	ui.app.host.modals.open(modal)
	return modal


func current_id() -> String:
	return str(_ids[_pos]) if _pos >= 0 and _pos < _ids.size() else ""


func step(delta: int) -> void:
	if _ids.is_empty():
		return
	_pos = clampi(_pos + delta, 0, _ids.size() - 1)
	_fill()


func zoom(delta: int) -> void:
	_zoom = clampi(_zoom + delta, 0, ZOOM_SIZES.size() - 1)
	if _hero != null:
		_hero.custom_minimum_size = ZOOM_SIZES[_zoom]
		_hero.size = ZOOM_SIZES[_zoom]
		_hero.queue_redraw()


func zoom_level() -> int:
	return _zoom


## Left and right walk through the cards. They are read before the buttons see them (a focused button would otherwise use the arrows to move focus).
func _input(event: InputEvent) -> void:
	if _ui == null or _ids.size() < 2 or not is_inside_tree():
		return
	if event.is_action_pressed("ui_left"):
		step(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		step(1)
		get_viewport().set_input_as_handled()


func _fill() -> void:
	var ctl := _ui.ctl
	var card_id := current_id()
	var row := ctl.card_detail(card_id)
	if row.is_empty():
		return
	_ui.app.ui_state.mark_seen(ctl.profile().profile_id, [card_id])
	panel.set_title("%s: %s" % [row["name"], row["edition"]])
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var compact := _ui.app.layout.is_mobile()
	var layout: BoxContainer = VBoxContainer.new() if compact else HBoxContainer.new()
	layout.add_theme_constant_override("separation", FcUiTokens.SPACE_5)
	_body.add_child(layout)
	layout.add_child(_left_column(row))
	layout.add_child(_right_column(row))


func _left_column(row: Dictionary) -> Control:
	var ctl := _ui.ctl
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	_hero = FcCardFace.new().setup(row, {"size": ZOOM_SIZES[_zoom], "inspected": true})
	_hero.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(1)
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(-1))
	_hero.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_hero)
	var tools := HBoxContainer.new()
	tools.alignment = BoxContainer.ALIGNMENT_CENTER
	tools.add_child(FcButton.icon_only("chevron-left", "Previous card", func() -> void: step(-1)))
	tools.add_child(FcButton.icon_only("minus", "Smaller", func() -> void: zoom(-1)))
	tools.add_child(FcButton.icon_only("refresh-cw", "Turn the card over", func() -> void: _hero.flip_to(not _hero.face_down)))
	tools.add_child(FcButton.icon_only("plus", "Larger", func() -> void: zoom(1)))
	tools.add_child(FcButton.icon_only("chevron-right", "Next card", func() -> void: step(1)))
	column.add_child(tools)
	if bool(row["owned"]):
		column.add_child(FcStatLine.make("Copies owned", str(row["quantity"])))
		column.add_child(FcStatLine.make("Mastery (cosmetic)", "level %d, frame %s" % [row["mastery"], ctl.catalog.config.mastery_frame(row["mastery"])]))
		if bool(row["available"]):
			column.add_child(_duplicate_actions(row))
	column.add_child(FcButton.make("Compare with another card", FcButton.Variant.SECONDARY, func() -> void: FcCardCompare.open_for(_ui, str(row["card_id"])), "arrow-up-down"))
	return column


func _duplicate_actions(row: Dictionary) -> Control:
	var ctl := _ui.ctl
	var card_id := str(row["card_id"])
	var box := VBoxContainer.new()
	var convert := FcButton.make("Convert a duplicate to %d shards" % ctl.catalog.config.shards_for(str(row["rarity"])), FcButton.Variant.SECONDARY, func() -> void:
		var r := ctl.convert_duplicate(card_id)
		_ui.report(r, "Converted a duplicate.")
		_after_action())
	convert.disabled = row["spare"] < 1
	box.add_child(convert)
	var level := int(row["mastery"])
	var cost := ctl.catalog.config.mastery_cost(level)
	var mastery := FcButton.make("Raise mastery (1 duplicate + %d shards)" % cost, FcButton.Variant.SECONDARY, func() -> void:
		var r := ctl.apply_mastery(card_id)
		_ui.report(r, "Mastery raised. This changes how the card looks, never how it plays.")
		_after_action())
	mastery.disabled = row["spare"] < 1 or level >= ctl.catalog.config.mastery_max() or ctl.profile().balance("shards") < cost
	box.add_child(mastery)
	var hint := FcUiTables.label("Duplicates become shards or cosmetic mastery. Ratings, attributes and badges never change.", FcUiTokens.TYPE_SMALL)
	hint.theme_type_variation = "MutedLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 220
	box.add_child(hint)
	return box


func _after_action() -> void:
	_ui.refresh()
	_fill()


func _right_column(row: Dictionary) -> Control:
	var ctl := _ui.ctl
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	var head := HBoxContainer.new()
	head.add_child(FcRatingBadge.new(int(row["overall"]), FcRatingBadge.Size.LARGE))
	var words := VBoxContainer.new()
	var rarity_line := FcUiTables.label("%s   %s" % [FcRarityStyle.label(str(row["rarity"])), row["position"]], FcUiTokens.TYPE_H3, true)
	rarity_line.add_theme_color_override("font_color", FcRarityStyle.color(str(row["rarity"])))
	words.add_child(rarity_line)
	if str(row["team"]) != "":
		var team := FcUiTables.label("Team: %s" % row["team"], FcUiTokens.TYPE_SMALL)
		team.theme_type_variation = "MutedLabel"
		words.add_child(team)
	head.add_child(words)
	column.add_child(head)
	if not bool(row["available"]):
		column.add_child(_note("The loaded content release does not include this card. You still own it; it returns when a release brings it back."))
		return column
	if bool(row["revision_changed"]):
		column.add_child(_note("The card's definition was updated by a newer release (revision %d)." % row["revision"]))
	var badges: Array = row["badges"]
	if not badges.is_empty():
		column.add_child(FcUiTables.label("Badges", FcUiTokens.TYPE_H3, true))
		for b in badges:
			var def := FcBadges.get_badge(str(b))
			column.add_child(_note("%s: %s" % [def.get("name", b), def.get("description", "")]))
	column.add_child(FcUiTables.label("Attributes", FcUiTokens.TYPE_H3, true))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	var attrs: Dictionary = row["attributes"]
	var tiers := FcRatingBadge.tiers()
	for key in ctl.defs.attributes.keys():
		var def_a := ctl.defs.attributes.get_def(key)
		var value := int(attrs.get(key, 0))
		list.add_child(_attribute_row(def_a.display_name, value, tiers.color_for(value)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	column.add_child(scroll)
	var stats: Dictionary = ctl.profile().card_stats.get(str(row["card_id"]), {})
	if not stats.is_empty() and int(stats["games"]) > 0:
		column.add_child(FcStatLine.make("In your games", "%d played, %.1f pts, %.1f reb, %.1f ast" % [stats["games"], float(stats["points"]) / stats["games"], float(stats["rebounds"]) / stats["games"], float(stats["assists"]) / stats["games"]]))
	return column


func _note(text: String) -> Label:
	var l := FcUiTables.label(text, FcUiTokens.TYPE_SMALL)
	l.theme_type_variation = "MutedLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 260
	return l


## One attribute: its name, a bar filled to its rating in the tier colour, and the number.
func _attribute_row(display_name: String, value: int, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	var name := Label.new()
	name.text = display_name
	name.custom_minimum_size.x = 150
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = value
	bar.custom_minimum_size = Vector2(90, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	var number := Label.new()
	number.text = str(value)
	number.theme_type_variation = "NumericLabel"
	number.custom_minimum_size.x = 28
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(number)
	return row
