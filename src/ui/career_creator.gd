class_name FcCareerCreator
extends VBoxContainer
## The Career Mode player creator: name, country, position, body, hand, jersey, archetype, potential, appearance and the 28
## attributes, with the points left and every rule explained as plain text. It only edits a build ("spec", see FcPlayerBuild)
## and asks FcPlayerBuild to validate it; it decides nothing itself. When the build is valid the "create" signal carries it.

signal create_requested(spec: Dictionary)

var _defs: FcDefinitionSet
var _spec: Dictionary = {}
var _inputs: Dictionary = {}   # field name -> Control
var _attribute_inputs: Dictionary = {}   # attribute key -> SpinBox
var _points_label: Label
var _messages: Label
var _potential: SpinBox
var _archetype_note: Label
var _updating := false


func _init(defs: FcDefinitionSet = null) -> void:
	_defs = defs if defs != null else FcDefinitionSet.load_default()


func _ready() -> void:
	build()


## The steps, in order: [id, label]. One page at a time, with a live preview of the player beside (or above, on a phone) the form.
const STEPS := [["identity", "Identity"], ["body", "Body"], ["look", "Look"], ["skills", "Skills"], ["review", "Review"]]

var _steps := FcTabBar.new()
var _pages: Dictionary = {}   # step id -> VBoxContainer
var _step: String = "identity"
var _back_button: Button
var _next_button: Button
var _stage: FcShowcaseStage
var _preview_words: Label
var _review: Label
var _create_button: Button


## Builds the form (called automatically; tests may call it directly).
func build() -> void:
	if not _inputs.is_empty():
		return
	_spec = FcPlayerBuild.default_spec("floor_general", FcPosition.Id.PG, _defs)
	add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	add_child(FcUiTables.label("Create your player", FcUiTokens.TYPE_H1, true))
	var intro := FcUiTables.label("Choose who your player is, then spend your points. An archetype is only a starting point: change any attribute to build a hybrid. Taller and longer players can reach higher in some skills and lower in others.", FcUiTokens.TYPE_SMALL)
	intro.theme_type_variation = "MutedLabel"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = 160
	add_child(intro)
	_steps.set_tabs(STEPS, "identity")
	_steps.tab_selected.connect(show_step)
	add_child(_steps)
	# the preview sits beside the page on a wide screen and above it on a phone (the flow wraps)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", FcUiTokens.SPACE_5)
	flow.add_theme_constant_override("v_separation", FcUiTokens.SPACE_3)
	add_child(flow)
	flow.add_child(_build_preview())
	var page_area := VBoxContainer.new()
	page_area.custom_minimum_size.x = 300
	page_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_child(page_area)
	for entry in STEPS:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
		_pages[entry[0]] = page
		page_area.add_child(page)
	_build_identity(_pages["identity"])
	_build_body(_pages["body"])
	_build_look(_pages["look"])
	_build_skills(_pages["skills"])
	_build_review(_pages["review"])
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	_back_button = FcUiTables.button("Previous step", func() -> void: _move(-1))
	_next_button = FcUiTables.button("Next step", func() -> void: _move(1))
	nav.add_child(_back_button)
	nav.add_child(_next_button)
	page_area.add_child(nav)
	_refresh_all()
	show_step("identity")


## Shows one step (the tabs and the Previous/Next buttons call this).
func show_step(id: String) -> void:
	_step = id
	for key in _pages:
		(_pages[key] as Control).visible = key == id
	_steps.select(id)
	var index := step_ids().find(id)
	_back_button.disabled = index <= 0
	_next_button.disabled = index >= STEPS.size() - 1
	if id == "review":
		check()
	_refresh_preview()


func current_step() -> String:
	return _step


func step_ids() -> Array:
	return STEPS.map(func(e: Array) -> String: return e[0])


func _move(delta: int) -> void:
	var ids := step_ids()
	show_step(ids[clampi(ids.find(_step) + delta, 0, ids.size() - 1)])


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", FcUiTokens.SPACE_3)
	grid.add_theme_constant_override("v_separation", FcUiTokens.SPACE_2)
	return grid


func _muted(text: String) -> Label:
	var l := FcUiTables.label(text, FcUiTokens.TYPE_SMALL)
	l.theme_type_variation = "MutedLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 160
	return l


func _build_identity(page: VBoxContainer) -> void:
	var grid := _grid()
	page.add_child(grid)
	_text(grid, "first_name", "First name")
	_text(grid, "last_name", "Last name")
	_text(grid, "country", "Country")
	_number(grid, "jersey_number", "Jersey number", 0, 99, 1)
	_choice(grid, "position", "Position", [["Point guard", 1], ["Shooting guard", 2], ["Small forward", 3], ["Power forward", 4], ["Center", 5]])
	_choice(grid, "secondary_position", "Secondary position", [["None", 0], ["Point guard", 1], ["Shooting guard", 2], ["Small forward", 3], ["Power forward", 4], ["Center", 5]])
	_choice(grid, "handedness", "Dominant hand", [["Right", 0], ["Left", 1], ["Both", 2]])
	var archetype_options: Array = []
	for a in FcArchetypes.all():
		archetype_options.append([a["name"], a["key"]])
	_choice(grid, "archetype", "Archetype", archetype_options)
	_archetype_note = _muted("")
	page.add_child(_archetype_note)


func _build_body(page: VBoxContainer) -> void:
	var grid := _grid()
	page.add_child(grid)
	_number(grid, "height_cm", "Height (cm)", 165, 232, 1)
	_number(grid, "weight_kg", "Weight (kg)", 60, 180, 1)
	_number(grid, "wingspan_cm", "Wingspan (cm)", 165, 250, 1)
	_potential = _number(grid, "potential", "Potential", 40, 99, 1)
	page.add_child(_muted("Your body sets how high your potential can go and how far each skill can grow later."))


func _build_look(page: VBoxContainer) -> void:
	var look := _grid()
	page.add_child(look)
	var appearance: Dictionary = FcBuildRules.rules()["appearance"]
	for part in appearance:
		var picker := OptionButton.new()
		for option in appearance[part]:
			picker.add_item(str(option).replace("_", " "))
		picker.tooltip_text = "Your %s." % str(part).replace("_", " ")
		picker.item_selected.connect(func(i):
			_spec["appearance"][part] = appearance[part][i]
			_refresh_preview())
		look.add_child(FcUiTables.label(str(part).replace("_", " ").capitalize()))
		look.add_child(picker)
		_inputs["appearance_" + part] = picker


func _build_skills(page: VBoxContainer) -> void:
	_points_label = FcUiTables.label("", FcUiTokens.TYPE_H3, true)
	page.add_child(_points_label)
	var categories: Array = []
	for key in _defs.attributes.keys():
		var category: String = _defs.attributes.get_def(key).category
		if not categories.has(category):
			categories.append(category)
	for category in categories:
		page.add_child(FcUiTables.label(category.capitalize(), FcUiTokens.TYPE_H3, true))
		var grid := GridContainer.new()
		grid.columns = 2   # name and box: one column of skills, so it fits a phone
		grid.add_theme_constant_override("h_separation", FcUiTokens.SPACE_3)
		page.add_child(grid)
		for key in _defs.attributes.keys_in_category(category):
			var def: FcAttributeDef = _defs.attributes.get_def(key)
			var box := SpinBox.new()
			box.min_value = int(FcBuildRules.rules()["attribute_floor"])
			box.max_value = int(FcBuildRules.rules()["start_attribute_cap"])
			box.step = 1
			box.tooltip_text = "%s. Starts between %d and %d; your body and potential set how far it can grow later." % [def.description, int(FcBuildRules.rules()["attribute_floor"]), int(FcBuildRules.rules()["start_attribute_cap"])]
			box.value_changed.connect(func(v): _on_attribute(key, int(v)))
			var name_label := FcUiTables.label(def.display_name)
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(name_label)
			grid.add_child(box)
			_attribute_inputs[key] = box


func _build_review(page: VBoxContainer) -> void:
	_review = FcUiTables.label("", FcUiTokens.TYPE_BODY)
	_review.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_review.custom_minimum_size.x = 160
	page.add_child(_review)
	_messages = FcUiTables.label("", FcUiTokens.TYPE_BODY)
	_messages.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_messages.custom_minimum_size.x = 160
	page.add_child(_messages)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	buttons.add_child(FcUiTables.button("Check my build", check))
	_create_button = FcUiTables.button("Create my player", request_create)
	buttons.add_child(_create_button)
	page.add_child(buttons)


## The live preview: the player standing on the showcase stage (the same figure the career hub and profile show), with the numbers that
## matter while building. It reads the spec and changes nothing.
func _build_preview() -> Control:
	var panel := FcPanel.new("Your player", FcPanel.Variant.RAISED)
	panel.custom_minimum_size.x = 220
	_stage = FcShowcaseStage.new().setup(_preview_subject(), 150)
	_stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.body.add_child(_stage)
	_preview_words = FcUiTables.label("", FcUiTokens.TYPE_SMALL)
	_preview_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_words.custom_minimum_size.x = 160
	_preview_words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.body.add_child(_preview_words)
	return panel


func _preview_subject() -> Dictionary:
	var full_name := ("%s %s" % [_spec.get("first_name", ""), _spec.get("last_name", "")]).strip_edges()
	return FcPlayerPresentation.subject("career_creator_preview", full_name if full_name != "" else "Your player", {}, int(_spec.get("jersey_number", 0)), (_spec.get("appearance", {}) as Dictionary).duplicate())


func _refresh_preview() -> void:
	if _stage == null or _preview_words == null:
		return
	_stage.setup(_preview_subject(), 150)
	var sum := 0
	for key in _spec["attributes"]:
		sum += int(_spec["attributes"][key])
	var average := roundi(float(sum) / maxi(1, (_spec["attributes"] as Dictionary).size()))
	var archetype := FcArchetypes.get_archetype(str(_spec["archetype"]))
	var left := int(FcBuildRules.rules()["budget_points"]) - FcPlayerBuild.budget_used(_spec["attributes"])
	_preview_words.text = "%s\n%s, %d cm  #%d\nSkill average %d  |  Potential %d\nPoints left: %d" % [
		archetype.get("name", ""), FcPosition.abbreviation(int(_spec["position"])), int(_spec["height_cm"]), int(_spec["jersey_number"]), average, int(_spec["potential"]), left]
	if _review != null:
		_review.text = "%s\n%s" % [_preview_subject()["name"], _preview_words.text]


# --- building the form -----------------------------------------------------------------------------------

func _text(grid: GridContainer, field: String, title: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(140, 0)
	edit.text_changed.connect(func(_t): _refresh_preview())
	edit.text_changed.connect(func(t): _spec[field] = t)
	grid.add_child(FcUiTables.label(title))
	grid.add_child(edit)
	_inputs[field] = edit
	return edit


func _number(grid: GridContainer, field: String, title: String, low: int, high: int, step: int) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = low
	box.max_value = high
	box.step = step
	box.value_changed.connect(func(v): _on_number(field, int(v)))
	box.tooltip_text = {
		"height_cm": "Your height. Height and wingspan set your potential cap and bend what each skill can become.",
		"weight_kg": "Your weight. It must fit your height. Heavier builds are stronger but slower.",
		"wingspan_cm": "Your arm span. Longer arms help blocks and steals.",
		"potential": "How good you can eventually become. Your body allows a maximum; leaving room below it is not required.",
		"jersey_number": "Your jersey number, 0 to 99."}.get(field, "")
	grid.add_child(FcUiTables.label(title))
	grid.add_child(box)
	_inputs[field] = box
	return box


func _choice(grid: GridContainer, field: String, title: String, options: Array) -> OptionButton:
	var picker := OptionButton.new()
	for option in options:
		picker.add_item(option[0])
		picker.set_item_metadata(picker.item_count - 1, option[1])
	picker.item_selected.connect(func(i): _on_choice(field, picker.get_item_metadata(i)))
	grid.add_child(FcUiTables.label(title))
	grid.add_child(picker)
	_inputs[field] = picker
	return picker


# --- reacting to changes ---------------------------------------------------------------------------------

func _on_number(field: String, value: int) -> void:
	if _updating:
		return
	_spec[field] = value
	if field in ["height_cm", "wingspan_cm"]:
		_refresh_potential_cap()
	_refresh_points()


func _on_attribute(key: String, value: int) -> void:
	if _updating:
		return
	_spec["attributes"][key] = value
	_refresh_points()


func _on_choice(field: String, value) -> void:
	if _updating:
		return
	if field == "archetype":
		# a new archetype replaces the attributes with its template; everything else you typed stays
		var fresh := FcPlayerBuild.default_spec(str(value), int(_spec["position"]), _defs)
		_spec["archetype"] = value
		_spec["attributes"] = fresh["attributes"]
		_refresh_attributes()
	else:
		_spec[field] = value
	_refresh_points()


func _refresh_all() -> void:
	_updating = true
	for field in ["first_name", "last_name", "country"]:
		(_inputs[field] as LineEdit).text = str(_spec[field])
	for field in ["jersey_number", "height_cm", "weight_kg", "wingspan_cm", "potential"]:
		(_inputs[field] as SpinBox).value = int(_spec[field])
	for field in ["position", "secondary_position", "handedness", "archetype"]:
		var picker := _inputs[field] as OptionButton
		for i in picker.item_count:
			if picker.get_item_metadata(i) == _spec[field]:
				picker.select(i)
	_updating = false
	_refresh_attributes()
	_refresh_potential_cap()
	_refresh_points()


func _refresh_attributes() -> void:
	_updating = true
	for key in _attribute_inputs:
		(_attribute_inputs[key] as SpinBox).value = int(_spec["attributes"][key])
	_updating = false


func _refresh_potential_cap() -> void:
	_potential.max_value = FcPlayerBuild.potential_cap(_spec)
	if _spec["potential"] > _potential.max_value:
		_spec["potential"] = int(_potential.max_value)
		_updating = true
		_potential.value = _spec["potential"]
		_updating = false


func _refresh_points() -> void:
	var left := int(FcBuildRules.rules()["budget_points"]) - FcPlayerBuild.budget_used(_spec["attributes"])
	_points_label.text = "Points left to spend: %d" % left
	_refresh_preview()
	_points_label.add_theme_color_override("font_color", FcUiTheme.BAD if left < 0 else FcUiTheme.HEADING)
	var archetype := FcArchetypes.get_archetype(str(_spec["archetype"]))
	_archetype_note.text = "%s: %s" % [archetype.get("name", ""), archetype.get("description", "")]


# --- checking and creating -------------------------------------------------------------------------------

## The current build as a plain dictionary (a copy).
func current_spec() -> Dictionary:
	return _spec.duplicate(true)


## Programmatic edits for tests and for loading a draft: sets one field the same way the controls do.
func set_field(field: String, value) -> void:
	_spec[field] = value
	_refresh_all()


func set_attribute(key: String, value: int) -> void:
	_spec["attributes"][key] = value
	_refresh_attributes()
	_refresh_points()


## Validates the build and shows every problem in plain words (or a green light). Returns the errors.
func check() -> Array[String]:
	var errors := FcPlayerBuild.validate(_spec, _defs)
	if errors.is_empty():
		_messages.text = "This build is valid. Press Create my player."
		_messages.add_theme_color_override("font_color", FcUiTheme.GOOD)
	else:
		_messages.text = "To fix:\n- " + "\n- ".join(errors)
		_messages.add_theme_color_override("font_color", FcUiTheme.BAD)
	return errors


func request_create() -> void:
	if check().is_empty():
		create_requested.emit(current_spec())
