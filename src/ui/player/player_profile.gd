class_name FcPlayerProfile
extends VBoxContainer
## The player profile as a DOSSIER (D-059 follow-up), the same view in every mode: a hero (the player standing in his team's kit on a stage, name,
## overall and potential, position, archetype, team, style summary) over a strip of vitals (age, height, weight, wingspan, hand, number), then
## tabs. The Overview is a set of panels: ratings (a radar of the attribute groups and the strongest attributes), development (a timeline of
## the player's career arc), personality, contract and team, the latest season and honours; Attributes, Badges, Stats, History and Awards are
## the deep views. A panel a mode has no data for is not shown (a Dynasty card has no contract or personality; nothing is invented).
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
	stage = FcShowcaseStage.new().setup(vm["subject"], 170 if _compact else 210)
	stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	layout.add_child(stage)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	var title := FcUiTables.label(str(vm["name"]), FcUiTokens.TYPE_DISPLAY, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(title)
	name_row.add_child(_rating_block("OVR", int(vm["overall"])))
	if int(vm["potential"]) > 0:
		name_row.add_child(_rating_block("POT", int(vm["potential"])))
	words.add_child(name_row)
	var position := str(vm["position"]) + ("/" + str(vm["secondary"]) if str(vm["secondary"]) != "" else "")
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	chips.add_child(FcStatusChip.make(position, FcStatusChip.Tone.NEUTRAL))
	if str(vm["archetype"]) != "":
		chips.add_child(FcStatusChip.make(str(vm["archetype"]), FcStatusChip.Tone.INFO))
	chips.add_child(FcStatusChip.make(str(vm["playstyle"]["label"]), FcStatusChip.Tone.SUCCESS))
	words.add_child(chips)
	var team: Dictionary = vm["team"]
	if str(team.get("name", "")) != "":
		var look := FcTeamLook.resolve(FcTeamLook.subject("profile_team:%s" % str(team["name"]), str(team["name"]), str(team.get("abbreviation", "")), str(team.get("primary", "")), str(team.get("secondary", ""))))
		words.add_child(FcTeamChip.new().setup(look, str(team["name"]), 28, false, false))
	var style := FcUiTables.label(str(vm["playstyle"]["text"]), FcUiTokens.TYPE_SMALL)
	style.theme_type_variation = "MutedLabel"
	style.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(style)
	var vitals := FcKpiStrip.new()
	vitals.name = "Vitals"
	vitals.set_items(_vitals())
	for tile in vitals.get_children():
		(tile as Control).custom_minimum_size.x = 84
	words.add_child(vitals)
	layout.add_child(words)
	var uniform := FcUniformPreview.new().setup(stage.visual, 64)
	uniform.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	uniform.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	layout.add_child(uniform)
	return layout


## An overall or potential as a big badge with its caption under it.
func _rating_block(caption: String, value: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var badge := FcRatingBadge.new(value, FcRatingBadge.Size.LARGE)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(badge)
	var label := FcUiTables.label(caption, FcUiTokens.TYPE_SMALL)
	label.theme_type_variation = "MutedLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	return box


## The vitals strip: only what is known (a Dynasty card has no height or age; nothing is invented).
func _vitals() -> Array:
	var out: Array = []
	if int(vm["age"]) > 0:
		out.append({"label": "Age", "value": str(vm["age"])})
	var physical: Dictionary = vm["physical"]
	if not physical.is_empty():
		out.append({"label": "Height", "value": "%d cm" % physical["height_cm"], "delta": _feet_inches(int(physical["height_cm"]))})
		out.append({"label": "Weight", "value": "%d kg" % physical["weight_kg"]})
		out.append({"label": "Wingspan", "value": "%d cm" % physical["wingspan_cm"]})
		out.append({"label": "Shoots", "value": str(physical["hand"])})
	if int(vm.get("jersey", 0)) > 0:
		out.append({"label": "Number", "value": "#%d" % int(vm["jersey"])})
	return out


static func _feet_inches(cm: int) -> String:
	var inches := roundi(cm / 2.54)
	return "%d'%d\"" % [inches / 12, inches % 12]


# --- tabs ---------------------------------------------------------------------------------------------------------------------

func _overview() -> void:
	var flow := HFlowContainer.new()
	flow.name = "DossierPanels"
	flow.add_theme_constant_override("h_separation", FcUiTokens.SPACE_3)
	flow.add_theme_constant_override("v_separation", FcUiTokens.SPACE_3)
	_body.add_child(flow)
	flow.add_child(_ratings_panel())
	flow.add_child(_development_panel())
	if not (vm.get("personality", []) as Array).is_empty():
		flow.add_child(_personality_panel())
	if not (vm.get("contract", {}) as Dictionary).is_empty():
		flow.add_child(_contract_panel())
	var rows: Array = vm["stats"]["rows"]
	if not rows.is_empty():
		flow.add_child(_season_panel(rows[rows.size() - 1]))
	if not (vm["awards"] as Array).is_empty():
		flow.add_child(_honours_panel())


func _panel(title_text: String) -> FcPanel:
	var panel := FcPanel.new(title_text, FcPanel.Variant.SURFACE)
	panel.custom_minimum_size.x = 250 if _compact else 330
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return panel


## Ratings: the attribute groups as a radar (the mean of each group) and the six strongest attributes.
func _ratings_panel() -> FcPanel:
	var panel := _panel("Ratings")
	var sums := {}
	var counts := {}
	for a in vm["attributes"]:
		var category := str(a["category"])
		sums[category] = float(sums.get(category, 0.0)) + float(a["value"])
		counts[category] = int(counts.get(category, 0)) + 1
	var names: Array = []
	var values: Array = []
	for category in sums:
		names.append(str(category).capitalize())
		values.append(float(sums[category]) / float(counts[category]))
	if names.size() >= 3:
		var radar := FcRadar.new(names, values)
		radar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		panel.add(radar)
	for a in top_attributes(6):
		panel.add(_bar_row(str(a["name"]), int(a["value"])))
	return panel


## Development: the career-arc timeline for Owner and Career players, the progress lines Career already has, the card note for Dynasty.
func _development_panel() -> FcPanel:
	var panel := _panel("Development")
	var progression: Dictionary = vm["progression"]
	match str(progression["kind"]):
		"career":
			var bar := FcProgress.new()
			bar.set_progress(float(progression["into_level"]), float(maxi(1, int(progression["needed"]))))
			panel.add(bar)
			panel.add(FcStatLine.make("Level", "%d   (%d of %d XP to the next)" % [progression["level"], progression["into_level"], progression["needed"]]))
			panel.add(FcDevelopmentTrack.new().setup(int(vm["age"]), int(progression.get("peak_age", 27)), int(progression["overall"]), int(progression["potential"])))
			panel.add(FcStatLine.make("Overall / ceiling", "%d / %d" % [progression["overall"], progression["potential"]]))
			panel.add(FcStatLine.make("Development points", str(progression["development_points"])))
			panel.add(FcStatLine.make("Skill points", str(progression["skill_points"])))
		"outlook":
			panel.add(FcDevelopmentTrack.new().setup(int(progression["age"]), int(progression["peak_age"]), int(progression["overall"]), int(progression["potential"])))
			var gap := int(progression["potential"]) - int(progression["overall"])
			panel.add(FcStatLine.make("Overall / potential", "%d / %d" % [progression["overall"], progression["potential"]]))
			panel.add(FcStatLine.make("Room to grow", "%d" % maxi(0, gap)))
			panel.add(FcStatLine.make("Expected to peak at", "age %d (now %d)" % [progression["peak_age"], progression["age"]]))
		_:
			panel.add(FcStatLine.make("Mastery frame", str(progression["frame"])))
			var note := FcUiTables.label(str(progression["note"]), FcUiTokens.TYPE_SMALL)
			note.theme_type_variation = "MutedLabel"
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			panel.add(note)
	return panel


func _personality_panel() -> FcPanel:
	var panel := _panel("Personality")
	for t in vm["personality"]:
		var row := _bar_row(str(t["name"]), int(t["value"]))
		row.tooltip_text = str(t["description"])
		panel.add(row)
	return panel


func _contract_panel() -> FcPanel:
	var panel := _panel("Contract and team")
	var c: Dictionary = vm["contract"]
	var team: Dictionary = vm["team"]
	if str(team.get("name", "")) != "":
		panel.add(FcStatLine.make("Team", str(team["name"])))
	panel.add(FcStatLine.make("Salary this season", FcUiTables.money(int(c["salary"]))))
	panel.add(FcStatLine.make("Signed through", "%d-%02d (%d season%s left)" % [c["through"], (int(c["through"]) + 1) % 100, c["years_left"], "" if int(c["years_left"]) == 1 else "s"]))
	panel.add(FcStatLine.make("Total value", FcUiTables.money(int(c["total"]))))
	var flags := HFlowContainer.new()
	flags.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	if bool(c["cornerstone"]):
		flags.add_child(FcStatusChip.make("Cornerstone", FcStatusChip.Tone.INFO))
	if bool(c["no_trade"]):
		flags.add_child(FcStatusChip.make("No-trade clause", FcStatusChip.Tone.WARNING))
	if flags.get_child_count() > 0:
		panel.add(flags)
	return panel


## The latest season in one line of numbers (the Stats tab has them all).
func _season_panel(row: Array) -> FcPanel:
	var panel := _panel("Latest season")
	var columns: Array = vm["stats"]["columns"]
	var strip := FcKpiStrip.new()
	var items: Array = []
	for i in columns.size():
		if str(columns[i]) in ["PPG", "RPG", "APG", "MPG", "GP"]:
			items.append({"label": str(columns[i]), "value": str(row[i])})
	strip.set_items(items)
	for tile in strip.get_children():
		(tile as Control).custom_minimum_size.x = 72
	panel.add(FcUiTables.label(str(row[0]), FcUiTokens.TYPE_SMALL))
	panel.add(strip)
	return panel


func _honours_panel() -> FcPanel:
	var panel := _panel("Honours and milestones")
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	chips.add_theme_constant_override("v_separation", FcUiTokens.SPACE_2)
	var shown := 0
	for a in vm["awards"]:
		if shown >= 6:
			break
		chips.add_child(FcStatusChip.make(str(a), FcStatusChip.Tone.INFO))
		shown += 1
	panel.add(chips)
	if (vm["awards"] as Array).size() > shown:
		var more := FcUiTables.label("+ %d more on the Awards tab" % ((vm["awards"] as Array).size() - shown), FcUiTokens.TYPE_SMALL)
		more.theme_type_variation = "MutedLabel"
		panel.add(more)
	return panel


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
	modal.panel.custom_minimum_size.x = 0 if app.layout.is_mobile() else 960
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, clampf(app.size.y - 190.0, 360.0, 760.0))   # as tall as the window allows
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var profile := FcPlayerProfile.new().setup(view_model, app.layout.is_mobile())
	profile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(profile)
	modal.content.add_child(scroll)
	app.host.modals.open(modal)
	return modal
