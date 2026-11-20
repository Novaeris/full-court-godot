class_name FcCardCompare
extends FcModal
## Two cards side by side: both card faces, a bar for every attribute (the leader's number is bright, fewer is never "better" here), and which
## badges each card has alone and which they share. The second card is chosen in a dropdown. It reads card details from the Dynasty
## controller and changes nothing. Escape closes it.

var _ui: FcDynastyUi
var _left_id: String
var _right_id: String
var _body: VBoxContainer
var _picker: FcDropdown


func _init(ui: FcDynastyUi = null, left_card: String = "", right_card: String = "") -> void:
	super("Compare cards", "", Kind.INFO, "Close")
	_ui = ui
	_left_id = left_card
	_right_id = right_card
	if ui == null:
		return
	panel.custom_minimum_size.x = 620
	_picker = FcDropdown.new()
	var items: Array = []
	for row in ui.ctl.collection_rows({"ownership": "owned"}, "overall_desc"):
		if row["card_id"] != left_card:
			items.append(["%s (%d)" % [row["name"], row["overall"]], row["card_id"]])
	if items.is_empty():
		for row in ui.ctl.collection_rows({}, "overall_desc"):
			if row["card_id"] != left_card:
				items.append(["%s (%d)" % [row["name"], row["overall"]], row["card_id"]])
	_picker.set_items(items, right_card if right_card != "" else (items[0][1] if not items.is_empty() else null))
	_picker.chosen.connect(func(id) -> void:
		_right_id = str(id)
		_fill())
	content.add_child(FcUiTables.label("Compare with", FcUiTokens.TYPE_SMALL))
	content.add_child(_picker)
	_body = VBoxContainer.new()
	content.add_child(_body)
	if _right_id == "" and _picker.value() != null:
		_right_id = str(_picker.value())
	_fill()


static func open_for(ui: FcDynastyUi, card_id: String, other_id: String = "") -> FcCardCompare:
	var modal := FcCardCompare.new(ui, card_id, other_id)
	ui.app.host.modals.open(modal)
	return modal


func _fill() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	if _right_id == "":
		_body.add_child(FcEmptyState.new("Nothing to compare with", "Collect another card first."))
		return
	var a := _ui.ctl.card_detail(_left_id)
	var b := _ui.ctl.card_detail(_right_id)
	if a.is_empty() or b.is_empty():
		return
	var faces := HBoxContainer.new()
	faces.alignment = BoxContainer.ALIGNMENT_CENTER
	faces.add_theme_constant_override("separation", FcUiTokens.SPACE_5)
	faces.add_child(FcCardFace.new().setup(a, {"size": FcCardFace.SIZE_STANDARD}))
	faces.add_child(FcUiTables.label("VS", FcUiTokens.TYPE_H1, true))
	faces.add_child(FcCardFace.new().setup(b, {"size": FcCardFace.SIZE_STANDARD}))
	_body.add_child(faces)
	_body.add_child(FcStatBar.new("Overall", float(a["overall"]), float(b["overall"])))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	var attrs_a: Dictionary = a.get("attributes", {})
	var attrs_b: Dictionary = b.get("attributes", {})
	var diffs: Array = []
	for key in _ui.ctl.defs.attributes.keys():
		var va := int(attrs_a.get(key, 0))
		var vb := int(attrs_b.get(key, 0))
		diffs.append({"key": key, "a": va, "b": vb})
	for d in compare_rows(diffs):
		var bar := FcStatBar.new(_ui.ctl.defs.attributes.get_def(d["key"]).display_name, float(d["a"]), float(d["b"]))
		rows.add_child(bar)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 240
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	_body.add_child(scroll)
	var split := badge_split(a.get("badges", []), b.get("badges", []))
	for entry in [["Only %s" % a["name"], split["only_a"]], ["Only %s" % b["name"], split["only_b"]], ["Both", split["both"]]]:
		if not (entry[1] as Array).is_empty():
			var names: Array[String] = []
			for badge in entry[1]:
				names.append(str(FcBadges.get_badge(str(badge)).get("name", badge)))
			_body.add_child(FcStatLine.make(entry[0], ", ".join(names)))


## Attribute rows ordered by how different they are (biggest gap first), ties by key: what to look at first.
static func compare_rows(diffs: Array) -> Array:
	var out := diffs.duplicate()
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		var gx := absi(int(x["a"]) - int(x["b"]))
		var gy := absi(int(y["a"]) - int(y["b"]))
		return gx > gy or (gx == gy and str(x["key"]) < str(y["key"])))
	return out


## Which badges only the first card has, only the second has, and both have.
static func badge_split(a_badges: Array, b_badges: Array) -> Dictionary:
	var only_a: Array = []
	var only_b: Array = []
	var both: Array = []
	for badge in a_badges:
		(both if b_badges.has(badge) else only_a).append(badge)
	for badge in b_badges:
		if not a_badges.has(badge):
			only_b.append(badge)
	return {"only_a": only_a, "only_b": only_b, "both": both}
