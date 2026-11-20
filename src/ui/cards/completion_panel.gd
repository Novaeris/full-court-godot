class_name FcCompletionPanel
extends RefCounted
## The collection completion presentation: one overall bar and a bar per rarity (in the rarity's colour), the team sets as short lines, and
## a "Complete" chip on any group the player has finished. It draws what FcCompletion.compute returns; it decides nothing.


static func build(data: Dictionary) -> Control:
	var panel := FcPanel.new("Collection completion", FcPanel.Variant.SURFACE)
	var overall: Dictionary = data["overall"]
	var head := HBoxContainer.new()
	var count := FcUiTables.label("%d of %d cards (%d%%)" % [overall["owned"], overall["total"], overall["percent"]], FcUiTokens.TYPE_BODY)
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(count)
	if overall["complete"]:
		head.add_child(FcStatusChip.make("Complete", FcStatusChip.Tone.SUCCESS))
	panel.add(head)
	var bar := FcProgress.new(FcProgress.Variant.GOLD if overall["complete"] else FcProgress.Variant.ACCENT)
	bar.set_progress(overall["owned"], overall["total"])
	panel.add(bar)
	var rarities := HFlowContainer.new()
	rarities.add_theme_constant_override("h_separation", FcUiTokens.SPACE_4)
	rarities.add_theme_constant_override("v_separation", FcUiTokens.SPACE_2)
	for group in data["by_rarity"]:
		rarities.add_child(_rarity_cell(group))
	panel.add(rarities)
	var teams: Array = data["by_team"]
	if not teams.is_empty():
		var line := HFlowContainer.new()
		line.add_theme_constant_override("h_separation", FcUiTokens.SPACE_3)
		for group in teams:
			var chip := FcUiTables.label("%s %d/%d" % [group["key"], group["owned"], group["total"]], FcUiTokens.TYPE_SMALL)
			chip.theme_type_variation = "MutedLabel" if not group["complete"] else ""
			if group["complete"]:
				chip.add_theme_color_override("font_color", FcUiTokens.SUCCESS)
			line.add_child(chip)
		panel.add(line)
	return panel


static func _rarity_cell(group: Dictionary) -> Control:
	var cell := VBoxContainer.new()
	cell.custom_minimum_size.x = 130
	cell.add_theme_constant_override("separation", 2)
	var rarity: String = group["key"]
	var title := FcUiTables.label("%s %d/%d%s" % [FcRarityStyle.label(rarity), group["owned"], group["total"], "  done" if group["complete"] else ""], FcUiTokens.TYPE_SMALL)
	title.add_theme_color_override("font_color", FcRarityStyle.color(rarity))
	cell.add_child(title)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(120, 8)
	bar.max_value = maxi(1, group["total"])
	bar.value = group["owned"]
	var fill := StyleBoxFlat.new()
	fill.bg_color = FcRarityStyle.color(rarity)
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	cell.add_child(bar)
	return cell
