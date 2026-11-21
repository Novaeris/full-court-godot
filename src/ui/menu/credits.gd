class_name FcCredits
extends RefCounted
## The Credits screen (it replaces the old About screen): the Full Court logo and version, the studio (Novaeris), the people and projects
## whose work is in the game (fonts, icons, the engine, with their licences), the content report, and the support shortcuts (logs,
## saves and content folders). Built into a content box; FcApp passes what the buttons do. Licence texts are required by the licences,
## so they stay on this screen in full.

const THIRD_PARTY := [
	["Inter", "Body text. SIL Open Font License 1.1.", "Copyright The Inter Project Authors"],
	["Barlow Condensed", "Headings and numbers. SIL Open Font License 1.1.", "Copyright Jeremy Tribby"],
	["Lucide", "Icons. ISC License.", "Copyright Lucide Contributors; portions Copyright Cole Bemis (Feather)"],
	["Godot Engine", "The engine. MIT License.", "Copyright (c) 2014-present Godot Engine contributors; (c) 2007-2014 Juan Linietsky, Ariel Manzur"],
]


## `actions`: back, open_logs, open_saves, open_content (all Callables). `content_summary` is the release report line ("" for none).
static func build(box: VBoxContainer, actions: Dictionary, content_summary: String = "") -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", FcUiTokens.SPACE_4)
	scroll.add_child(page)
	box.add_child(scroll)

	page.add_child(FcBrand.logo(FcBrand.FULL_COURT, 280, "Full Court"))
	var about := FcUiTables.label("Version %s. A basketball management simulation with original teams, players and staff in real cities." % FcVersion.GAME_VERSION, FcUiTokens.TYPE_BODY)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(about)

	var studio := FcPanel.new("Made by Novaeris", FcPanel.Variant.RAISED)
	studio.add(FcBrand.logo(FcBrand.NOVAERIS, 220, "Novaeris"))
	var studio_text := FcUiTables.label("Full Court is designed and built by the Novaeris studio.", FcUiTokens.TYPE_SMALL + 1)
	studio_text.theme_type_variation = "MutedLabel"
	studio_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	studio.add(studio_text)
	page.add_child(studio)

	var third := FcPanel.new("Built with", FcPanel.Variant.SURFACE)
	for entry in THIRD_PARTY:
		third.add(FcStatLine.make(str(entry[0]), str(entry[1])))
		var holder := FcUiTables.label(str(entry[2]), FcUiTokens.TYPE_MICRO + 1)
		holder.theme_type_variation = "CaptionLabel"
		holder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		third.add(holder)
	page.add_child(third)

	if content_summary != "":
		var content := FcPanel.new("Content", FcPanel.Variant.SURFACE)
		var summary := FcUiTables.label(content_summary, FcUiTokens.TYPE_SMALL + 1)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add(summary)
		page.add_child(content)

	var licence := FcPanel.new("Engine licence text", FcPanel.Variant.SURFACE)
	var text := TextEdit.new()
	text.editable = false
	text.custom_minimum_size.y = 180
	text.text = Engine.get_license_text()
	licence.add(text)
	page.add_child(licence)

	var support := FcPanel.new("Support", FcPanel.Variant.SURFACE)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	buttons.add_child(FcButton.make("Open the logs folder", FcButton.Variant.SECONDARY, actions["open_logs"], "info"))
	buttons.add_child(FcButton.make("Open the saves folder", FcButton.Variant.SECONDARY, actions["open_saves"]))
	buttons.add_child(FcButton.make("Open the content folder", FcButton.Variant.SECONDARY, actions["open_content"]))
	support.add(buttons)
	var hint := FcUiTables.label("If something goes wrong, send the newest file in the logs folder together with a description. Nothing is sent automatically.", FcUiTokens.TYPE_SMALL)
	hint.theme_type_variation = "MutedLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	support.add(hint)
	page.add_child(support)
	page.add_child(FcButton.make("Back", FcButton.Variant.SECONDARY, actions["back"], "chevron-left"))
