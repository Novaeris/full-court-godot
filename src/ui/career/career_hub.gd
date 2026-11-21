class_name FcCareerHub
extends RefCounted
## The top of the Career hub as a basketball-RPG hero panel: the player large on the stage (the same figure as on the profile and in every
## list), the overall and potential as big rating badges, the archetype, the level with an XP bar, and the points to spend. Only values the
## career rules already compute are shown (FcCareerController.card() and .progress(): level, XP into the level, development and skill points).
## It never invents a stat, a level or an achievement. Built from those two dictionaries and the presentation view-model.

## Returns the hero control. `open_profile` is a Callable() for the "Player profile" button.
static func hero(card: Dictionary, progress: Dictionary, view_model: Dictionary, open_profile: Callable) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", FcUiTokens.SPACE_5)
	row.add_theme_constant_override("v_separation", FcUiTokens.SPACE_3)
	row.name = "CareerHero"
	var stage := FcShowcaseStage.new().setup(view_model["subject"], 170)
	row.add_child(stage)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size.x = 360
	info.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	row.add_child(info)

	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	var ratings := HBoxContainer.new()
	ratings.add_theme_constant_override("separation", FcUiTokens.SPACE_4)
	ratings.add_child(_rating_block("Overall", int(card["overall"])))
	ratings.add_child(_rating_block("Potential", int(card["potential"]), "your ceiling"))
	identity.add_child(ratings)
	var tags := VBoxContainer.new()
	tags.add_theme_constant_override("separation", FcUiTokens.SPACE_1)
	tags.add_child(FcStatusChip.make(str(card["archetype"]), FcStatusChip.Tone.INFO))
	var position := str(card["position"]) + (("/" + str(card["secondary"])) if str(card["secondary"]) != "" else "")
	tags.add_child(FcStatusChip.make(position, FcStatusChip.Tone.NEUTRAL))
	identity.add_child(tags)
	info.add_child(identity)

	var level := FcUiTables.label("Level %d" % int(progress["level"]), FcUiTokens.TYPE_H2, true)
	info.add_child(level)
	var bar := FcProgress.new(FcProgress.Variant.GOLD)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.set_progress(float(progress["into_level"]), float(maxi(1, int(progress["needed"]))))
	bar.tooltip_text = "%d of %d XP to the next level" % [int(progress["into_level"]), int(progress["needed"])]
	info.add_child(bar)
	var xp := FcUiTables.label("XP %d (%d of %d to the next level)" % [progress["xp"], progress["into_level"], progress["needed"]], FcUiTokens.TYPE_SMALL)
	xp.theme_type_variation = "MutedLabel"
	info.add_child(xp)
	var points := FcUiTables.label("Development points %d    Skill points %d" % [progress["development_points"], progress["skill_points"]], FcUiTokens.TYPE_BODY)
	points.tooltip_text = "Development points raise attributes up to your potential; skill points unlock badges."
	info.add_child(points)

	var body := FcUiTables.label("Age %d   %d cm, %d kg, wingspan %d cm   Team: %s" % [card["age"], card["height_cm"], card["weight_kg"], card["wingspan_cm"], card["team"]], FcUiTokens.TYPE_SMALL)
	body.theme_type_variation = "MutedLabel"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(body)
	var profile_button := FcButton.make("Player profile", FcButton.Variant.SECONDARY, open_profile, "user")
	profile_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info.add_child(profile_button)
	return row


static func _rating_block(caption: String, value: int, note: String = "") -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	var badge := FcRatingBadge.new(value, FcRatingBadge.Size.LARGE)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	block.add_child(badge)
	var label := FcUiTables.label(caption + ("" if note == "" else " (%s)" % note), FcUiTokens.TYPE_SMALL)
	label.theme_type_variation = "CaptionLabel"
	block.add_child(label)
	return block


## The Card tab: a radar of the attribute groups (now, with what the player can reach) beside the grouped tables.
static func card_tab(card: Dictionary) -> Control:
	var box := HFlowContainer.new()
	box.add_theme_constant_override("h_separation", FcUiTokens.SPACE_4)
	box.add_theme_constant_override("v_separation", FcUiTokens.SPACE_4)
	var names: Array = []
	var now: Array = []
	var reach: Array = []
	for group in card["groups"]:
		var total_now := 0.0
		var total_reach := 0.0
		var count := 0
		for r in group["rows"]:
			total_now += float(r[1])
			total_reach += float(r[2])
			count += 1
		if count > 0:
			names.append(str(group["name"]))
			now.append(total_now / count)
			reach.append(total_reach / count)
	if names.size() >= 3:
		var panel := FcPanel.new("Attribute groups", FcPanel.Variant.SURFACE)
		panel.add(FcRadar.new(names, now, reach))
		var legend := FcUiTables.label("Filled: now. Gold outline: what you can reach.", FcUiTokens.TYPE_SMALL)
		legend.theme_type_variation = "MutedLabel"
		panel.add(legend)
		box.add_child(panel)
	var tables := HFlowContainer.new()
	tables.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tables.add_theme_constant_override("h_separation", FcUiTokens.SPACE_4)
	tables.add_theme_constant_override("v_separation", FcUiTokens.SPACE_3)
	for group in card["groups"]:
		var rows: Array = []
		for row in group["rows"]:
			rows.append([row[0], row[1], row[2]])
		var part := VBoxContainer.new()
		part.custom_minimum_size.x = 300
		part.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		part.add_child(FcUiTables.label(str(group["name"]), FcUiTokens.TYPE_H3, true))
		part.add_child(FcTable.from_strings(["Attribute", "Now", "Can reach"], rows, [0, 50, 80]))
		tables.add_child(part)
	box.add_child(tables)
	return box
