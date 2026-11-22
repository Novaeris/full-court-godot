class_name FcGameDayScreen
extends VBoxContainer
## The body of the game-day preview (see FcGameDay): the two teams side by side (stacked on a phone) with crest, record, rank, the
## expected starting five with ratings, and who is out. Display only.

var model: Dictionary = {}


func setup(day_model: Dictionary, looks: Array, phone: bool = false) -> FcGameDayScreen:
	model = day_model
	add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	var date := FcUiTables.label("%s   %s plays at home" % [model["date"], model["sides"][0]["name"]], FcUiTokens.TYPE_SMALL)
	date.theme_type_variation = "MutedLabel"
	add_child(date)
	var row: BoxContainer = VBoxContainer.new() if phone else HBoxContainer.new()
	row.add_theme_constant_override("separation", FcUiTokens.SPACE_4)
	add_child(row)
	for side in 2:
		row.add_child(_team_column(model["sides"][side], looks[side] if side < looks.size() else {}, side == int(model["user_side"]), side == 0))
	return self


func _team_column(info: Dictionary, look: Dictionary, is_user: bool, is_home: bool) -> Control:
	var panel := FcPanel.new("Home" if is_home else "Away", FcPanel.Variant.RAISED if is_user else FcPanel.Variant.SURFACE)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.name = "Home" if is_home else "Away"
	var chip := FcTeamChip.new().setup(look, str(info["name"]), 36, is_user, false)
	panel.body.add_child(chip)
	var facts := FcUiTables.label("Record %s    League rank %d    Starters %d overall" % [info["record"], info["rank"], info["overall"]], FcUiTokens.TYPE_SMALL)
	facts.theme_type_variation = "MutedLabel"
	facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	facts.custom_minimum_size.x = 120
	panel.body.add_child(facts)
	for p in info["starters"]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
		var pos := FcUiTables.label(str(p["position"]), FcUiTokens.TYPE_SMALL, true)
		pos.custom_minimum_size.x = 30
		line.add_child(pos)
		var name_label := FcUiTables.label(str(p["name"]), FcUiTokens.TYPE_BODY)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var ovr := FcUiTables.label(str(p["overall"]), FcUiTokens.TYPE_BODY, true)
		ovr.theme_type_variation = "NumericLabel"
		line.add_child(ovr)
		panel.body.add_child(line)
	if (info["out"] as Array).is_empty():
		var healthy := FcUiTables.label("Everyone is available.", FcUiTokens.TYPE_SMALL)
		healthy.theme_type_variation = "MutedLabel"
		panel.body.add_child(healthy)
	else:
		for o in info["out"]:
			var hurt := FcUiTables.label("Out: %s (%d game%s, %s)" % [o["name"], o["games"], "" if int(o["games"]) == 1 else "s", o["injury"]], FcUiTokens.TYPE_SMALL)
			hurt.add_theme_color_override("font_color", FcUiTokens.DANGER)
			hurt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hurt.custom_minimum_size.x = 120
			panel.body.add_child(hurt)
	return panel
