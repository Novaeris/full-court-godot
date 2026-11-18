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


## Builds the form (called automatically; tests may call it directly).
func build() -> void:
	if not _inputs.is_empty():
		return
	_spec = FcPlayerBuild.default_spec("floor_general", FcPosition.Id.PG, _defs)
	add_theme_constant_override("separation", 8)
	add_child(FcUiTables.label("Create your player", 20, true))
	var intro := FcUiTables.label("Choose who your player is, then spend your points. An archetype is only a starting point: change any attribute to build a hybrid. Taller and longer players can reach higher in some skills and lower in others.", 14)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(400, 0)
	add_child(intro)

	var identity := GridContainer.new()
	identity.columns = 4
	identity.add_theme_constant_override("h_separation", 12)
	add_child(identity)
	_text(identity, "first_name", "First name")
	_text(identity, "last_name", "Last name")
	_text(identity, "country", "Country")
	_number(identity, "jersey_number", "Jersey number", 0, 99, 1)
	_choice(identity, "position", "Position", [["Point guard", 1], ["Shooting guard", 2], ["Small forward", 3], ["Power forward", 4], ["Center", 5]])
	_choice(identity, "secondary_position", "Secondary position", [["None", 0], ["Point guard", 1], ["Shooting guard", 2], ["Small forward", 3], ["Power forward", 4], ["Center", 5]])
	_choice(identity, "handedness", "Dominant hand", [["Right", 0], ["Left", 1], ["Both", 2]])
	var archetype_options: Array = []
	for a in FcArchetypes.all():
		archetype_options.append([a["name"], a["key"]])
	_choice(identity, "archetype", "Archetype", archetype_options)
	_number(identity, "height_cm", "Height (cm)", 165, 232, 1)
	_number(identity, "weight_kg", "Weight (kg)", 60, 180, 1)
	_number(identity, "wingspan_cm", "Wingspan (cm)", 165, 250, 1)
	_potential = _number(identity, "potential", "Potential", 40, 99, 1)

	var look := GridContainer.new()
	look.columns = 4
	look.add_theme_constant_override("h_separation", 12)
	add_child(look)
	var appearance: Dictionary = FcBuildRules.rules()["appearance"]
	for part in appearance:
		var picker := OptionButton.new()
		for option in appearance[part]:
			picker.add_item(str(option).replace("_", " "))
		picker.tooltip_text = "Your player's %s." % str(part).replace("_", " ")
		picker.item_selected.connect(func(i): _spec["appearance"][part] = appearance[part][i])
		look.add_child(FcUiTables.label(str(part).replace("_", " ").capitalize()))
		look.add_child(picker)
		_inputs["appearance_" + part] = picker

	_archetype_note = FcUiTables.label("", 14)
	_archetype_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_archetype_note.custom_minimum_size = Vector2(400, 0)
	add_child(_archetype_note)
	_points_label = FcUiTables.label("", 16, true)
	add_child(_points_label)

	var attribute_box := VBoxContainer.new()   # the screen around the form scrolls
	attribute_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var categories: Array = []
	for key in _defs.attributes.keys():
		var category: String = _defs.attributes.get_def(key).category
		if not categories.has(category):
			categories.append(category)
	for category in categories:
		attribute_box.add_child(FcUiTables.label(category.capitalize(), 16, true))
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 10)
		attribute_box.add_child(grid)
		for key in _defs.attributes.keys_in_category(category):
			var def: FcAttributeDef = _defs.attributes.get_def(key)
			var box := SpinBox.new()
			box.min_value = int(FcBuildRules.rules()["attribute_floor"])
			box.max_value = int(FcBuildRules.rules()["start_attribute_cap"])
			box.step = 1
			box.tooltip_text = "%s. Starts between %d and %d; your body and potential set how far it can grow later." % [def.description, int(FcBuildRules.rules()["attribute_floor"]), int(FcBuildRules.rules()["start_attribute_cap"])]
			box.value_changed.connect(func(v): _on_attribute(key, int(v)))
			grid.add_child(FcUiTables.label(def.display_name))
			grid.add_child(box)
			_attribute_inputs[key] = box
	add_child(attribute_box)

	_messages = FcUiTables.label("", 14)
	_messages.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_messages.custom_minimum_size = Vector2(400, 0)
	add_child(_messages)
	var buttons := HBoxContainer.new()
	buttons.add_child(FcUiTables.button("Check my build", check))
	buttons.add_child(FcUiTables.button("Create my player", request_create))
	add_child(buttons)
	_refresh_all()


# --- building the form -----------------------------------------------------------------------------------

func _text(grid: GridContainer, field: String, title: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(140, 0)
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
