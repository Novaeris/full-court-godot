class_name FcPlayerProfile
extends VBoxContainer
## The player profile, the same view in every mode: a showcase stage with the player standing in his team's uniform, name, rating,
## position, archetype, style summary and physical information, and tabs for Overview, Attributes, Badges, Stats, History and Awards.
## A tab a mode has no data for is not shown (Dynasty cards have no season history; nothing is invented). Built from the view-model of
## FcPlayerPresentation, so it never reads game objects and never changes them. Mobile layouts stack the stage above the text.

var vm: Dictionary = {}
var stage: FcShowcaseStage
var tabs := FcTabBar.new()
var _body := VBoxContainer.new()
var _compact: bool = false


func setup(view_model: Dictionary, compact: bool = false) -> FcPlayerProfile:
	vm = view_model
	_compact = compact
	add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	add_child(_header())
	var tab_list: Array = tab_ids()
	tabs.set_tabs(tab_list.map(func(id: String) -> Array: return [id, id.capitalize()]))
	tabs.tab_selected.connect(show_tab)
	add_child(tabs)
	_body.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	add_child(_body)
	show_tab(tab_list[0])
	return self


## The tabs this player has something for, in order.
func tab_ids() -> Array:
	var out: Array = ["overview", "attributes"]
	if not (vm["badges"] as Array).is_empty():
		out.append("badges")
	if not (vm["stats"]["rows"] as Array).is_empty():
		out.append("stats")
	if not (vm["history"]["rows"] as Array).is_empty():
		out.append("history")
	if not (vm["awards"] as Array).is_empty():
		out.append("awards")
	return out


func show_tab(id: String) -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	tabs.select(id)
	match id:
		"attributes":
			_attributes()
		"badges":
			for b in vm["badges"]:
				_body.add_child(FcStatLine.make(str(b["name"]), str(b["description"])))
		"stats":
			_body.add_child(FcDataTable.build(vm["stats"]["columns"], vm["stats"]["rows"]))
		"history":
			_body.add_child(FcDataTable.build(vm["history"]["columns"], vm["history"]["rows"]))
		"awards":
			for a in vm["awards"]:
				_body.add_child(FcStatusChip.make(str(a), FcStatusChip.Tone.INFO))
		_:
			_overview()


# --- header -------------------------------------------------------------------------------------------------------------------

func _header() -> Control:
	var layout: BoxContainer = VBoxContainer.new() if _compact else HBoxContainer.new()
	layout.add_theme_constant_override("separation", FcUiTokens.SPACE_5)
	stage = FcShowcaseStage.new().setup(vm["subject"], 150 if _compact else 200)
	stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	layout.add_child(stage)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	var name_row := HBoxContainer.new()
	var title := FcUiTables.label(str(vm["name"]), FcUiTokens.TYPE_DISPLAY, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(title)
	name_row.add_child(FcRatingBadge.new(int(vm["overall"]), FcRatingBadge.Size.LARGE))
	words.add_child(name_row)
	var position := str(vm["position"]) + ("/" + str(vm["secondary"]) if str(vm["secondary"]) != "" else "")
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	chips.add_child(FcStatusChip.make(position, FcStatusChip.Tone.NEUTRAL))
	if str(vm["archetype"]) != "":
		chips.add_child(FcStatusChip.make(str(vm["archetype"]), FcStatusChip.Tone.INFO))
	chips.add_child(FcStatusChip.make(str(vm["playstyle"]["label"]), FcStatusChip.Tone.SUCCESS))
	words.add_child(chips)
	var style := FcUiTables.label(str(vm["playstyle"]["text"]), FcUiTokens.TYPE_SMALL)
	style.theme_type_variation = "MutedLabel"
	style.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(style)
	var team: Dictionary = vm["team"]
	if str(team.get("name", "")) != "":
		words.add_child(FcStatLine.make("Team", str(team["name"])))
	var physical: Dictionary = vm["physical"]
	if not physical.is_empty():
		words.add_child(FcStatLine.make("Height", "%d cm (%s)" % [physical["height_cm"], _feet_inches(int(physical["height_cm"]))]))
		words.add_child(FcStatLine.make("Weight", "%d kg" % physical["weight_kg"]))
		words.add_child(FcStatLine.make("Wingspan", "%d cm" % physical["wingspan_cm"]))
		words.add_child(FcStatLine.make("Shoots", str(physical["hand"])))
	if int(vm["age"]) > 0:
		words.add_child(FcStatLine.make("Age", str(vm["age"])))
	layout.add_child(words)
	var uniform := FcUniformPreview.new().setup(stage.visual, 64)
	uniform.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	uniform.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	layout.add_child(uniform)
	return layout


static func _feet_inches(cm: int) -> String:
	var inches := roundi(cm / 2.54)
	return "%d'%d\"" % [inches / 12, inches % 12]


# --- tabs ---------------------------------------------------------------------------------------------------------------------

func _overview() -> void:
	var progression: Dictionary = vm["progression"]
	match str(progression["kind"]):
		"career":
			_body.add_child(FcUiTables.label("Career progress", FcUiTokens.TYPE_H3, true))
			var bar := FcProgress.new()
			bar.set_progress(float(progression["into_level"]), float(maxi(1, int(progression["needed"]))))
			_body.add_child(bar)
			_body.add_child(FcStatLine.make("Level", "%d   (%d of %d XP to the next)" % [progression["level"], progression["into_level"], progression["needed"]]))
			_body.add_child(FcStatLine.make("Overall / ceiling", "%d / %d" % [progression["overall"], progression["potential"]]))
			_body.add_child(FcStatLine.make("Development points", str(progression["development_points"])))
			_body.add_child(FcStatLine.make("Skill points", str(progression["skill_points"])))
		"outlook":
			_body.add_child(FcUiTables.label("Development outlook", FcUiTokens.TYPE_H3, true))
			var gap := int(progression["potential"]) - int(progression["overall"])
			_body.add_child(FcStatLine.make("Overall / potential", "%d / %d" % [progression["overall"], progression["potential"]]))
			_body.add_child(FcStatLine.make("Room to grow", "%d" % maxi(0, gap)))
			_body.add_child(FcStatLine.make("Expected to peak at", "age %d (now %d)" % [progression["peak_age"], progression["age"]]))
		_:
			_body.add_child(FcUiTables.label("Card", FcUiTokens.TYPE_H3, true))
			_body.add_child(FcStatLine.make("Mastery frame", str(progression["frame"])))
			var note := FcUiTables.label(str(progression["note"]), FcUiTokens.TYPE_SMALL)
			note.theme_type_variation = "MutedLabel"
			_body.add_child(note)
	_body.add_child(FcUiTables.label("Strongest attributes", FcUiTokens.TYPE_H3, true))
	for a in top_attributes(6):
		_body.add_child(_bar_row(str(a["name"]), int(a["value"])))


## The `count` highest attributes (ties by name): what the overview highlights.
func top_attributes(count: int) -> Array:
	var all: Array = (vm["attributes"] as Array).duplicate()
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["value"] > b["value"] or (a["value"] == b["value"] and str(a["name"]) < str(b["name"])))
	return all.slice(0, count)


func _attributes() -> void:
	var by_category := {}
	for a in vm["attributes"]:
		if not by_category.has(a["category"]):
			by_category[a["category"]] = []
		by_category[a["category"]].append(a)
	for category in by_category:
		_body.add_child(FcUiTables.label(str(category).capitalize(), FcUiTokens.TYPE_H3, true))
		for a in by_category[category]:
			_body.add_child(_bar_row(str(a["name"]), int(a["value"])))


func _bar_row(label_text: String, value: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	var name := Label.new()
	name.text = label_text
	name.custom_minimum_size.x = 150
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = value
	bar.custom_minimum_size = Vector2(80, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = FcRatingBadge.tier_color(value)
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


## Opens the profile as a dialog on the app's dialog layer.
static func open_modal(app: FcApp, view_model: Dictionary) -> FcModal:
	var modal := FcModal.new(str(view_model["name"]), "", FcModal.Kind.INFO, "Close")
	modal.panel.custom_minimum_size.x = 0 if app.layout.is_mobile() else 760
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var profile := FcPlayerProfile.new().setup(view_model, app.layout.is_mobile())
	profile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(profile)
	modal.content.add_child(scroll)
	app.host.modals.open(modal)
	return modal
