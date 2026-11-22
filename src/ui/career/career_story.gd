class_name FcCareerStory
extends RefCounted
## The story side of the Career hub: the public image (fan favour, media image, hype and the latest headlines), the career timeline year by
## year, and the legacy page (pillars, tier, key moments, Hall of Fame, retired number). Built from FcCareerMedia, FcCareerTimeline and
## FcLegacy, so it shows only what those compute. Screens call the career controller (`legacy()`), never the engines.


## The three public-image numbers with their words, and the newest headlines.
static func public_image(profile: FcCareerProfile) -> Control:
	var panel := FcPanel.new("Public image", FcPanel.Variant.SURFACE)
	panel.name = "PublicImagePanel"
	for pair in [["fan_favor", "Fans", profile.fan_favor], ["media_image", "Press", profile.media_image], ["hype", "Hype", profile.hype]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
		var name_label := _wl(str(pair[1]), FcUiTokens.TYPE_BODY, true)
		name_label.custom_minimum_size.x = 56
		row.add_child(name_label)
		var bar := FcProgress.new(FcProgress.Variant.ACCENT)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.set_progress(float(pair[2]), 100.0)
		row.add_child(bar)
		var words := _wl("%s (%d)" % [FcCareerMedia.label(str(pair[0]), int(pair[2])), int(pair[2])], FcUiTokens.TYPE_BODY)
		words.custom_minimum_size.x = 140
		row.add_child(words)
		panel.add(row)
	var headlines := profile.headlines
	if headlines.is_empty():
		panel.add(_wl("No headlines yet: big games, titles and awards make them.", FcUiTokens.TYPE_SMALL, true))
	else:
		panel.add(_wl("Headlines", FcUiTokens.TYPE_H3, true))
		for i in range(headlines.size() - 1, maxi(-1, headlines.size() - 6), -1):
			panel.add(_wl("%d  %s" % [int(headlines[i]["year"]), str(headlines[i]["text"])], FcUiTokens.TYPE_BODY, true))
	return panel


## The timeline, newest year first, one block per year.
static func timeline(profile: FcCareerProfile) -> Control:
	var box := VBoxContainer.new()
	box.name = "CareerTimeline"
	box.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	box.add_child(_wl("Career timeline", FcUiTokens.TYPE_H3, true))
	var years := FcCareerTimeline.years(profile)
	if years.is_empty():
		box.add_child(_wl("Nothing yet: your career story is written as you play.", FcUiTokens.TYPE_BODY, true))
		return box
	var grouped := FcCareerTimeline.by_year(profile)
	years.reverse()
	for year in years:
		box.add_child(_wl("%d-%02d" % [int(year), (int(year) + 1) % 100], FcUiTokens.TYPE_BODY, true))
		for row in grouped[year]:
			var line := _wl("   %s" % str(row["text"]), FcUiTokens.TYPE_SMALL, true)
			line.tooltip_text = str(row["kind"]).capitalize()
			box.add_child(line)
	return box


## The legacy page for a summary from FcCareerController.legacy().
static func legacy_page(summary: Dictionary, retired: bool) -> Control:
	var box := VBoxContainer.new()
	box.name = "LegacyPage"
	box.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	var head := FcPanel.new("Your legacy" if retired else "Your legacy so far", FcPanel.Variant.RAISED)
	head.add(_wl("%s   (%d / 100)" % [str(summary["tier"]), int(summary["total"])], FcUiTokens.TYPE_H2, true))
	head.add(_wl(str(summary["narrative"]), FcUiTokens.TYPE_BODY, true))
	box.add_child(head)
	var pillars := FcPanel.new("What it is built from", FcPanel.Variant.SURFACE)
	for p in summary["pillars"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
		var name_label := _wl(str(p["label"]), FcUiTokens.TYPE_BODY, true)
		name_label.custom_minimum_size.x = 110
		row.add_child(name_label)
		var bar := FcProgress.new(FcProgress.Variant.GOLD)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.set_progress(float(p["score"]), 100.0)
		row.add_child(bar)
		pillars.add(row)
		pillars.add(_wl("%d: %s" % [int(p["score"]), str(p["line"])], FcUiTokens.TYPE_SMALL, true))
	box.add_child(pillars)
	var moments := FcPanel.new("Key moments", FcPanel.Variant.SURFACE)
	if (summary["moments"] as Array).is_empty():
		moments.add(_wl("No moments recorded yet.", FcUiTokens.TYPE_BODY, true))
	for m in summary["moments"]:
		moments.add(_wl("%d  %s" % [int(m["year"]), str(m["text"])], FcUiTokens.TYPE_BODY, true))
	box.add_child(moments)
	return box


## A label that wraps instead of widening the page (the third argument of FcUiTables.label is bold, not wrap).
static func _wl(text: String, size: int = 0, bold: bool = false) -> Label:
	var l := FcUiTables.label(text, size, bold)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l
