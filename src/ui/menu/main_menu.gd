class_name FcMainMenu
extends RefCounted
## Builds the main menu into a content box: the Full Court logo, the Continue card (the latest readable save), the three mode cards (each with
## its own picture), the saved games as cards, and the footer (Settings, Credits, Quit, and the small Novaeris mark). FcApp supplies
## what the buttons DO through `actions` and what is saved through `slots`; this class owns only how it looks, so the menu stays a
## view (docs/VISUAL_IDENTITY_PLAN.md, 5.6).
## actions: open_owner, open_career, open_dynasty, continue_latest, load(slot_id), delete(slot_id), select(slot_id), settings, credits, gallery (optional), quit.
## options: compact (bool), content_warning (String), selected_slot (String).

const WIDE_LOGO := 340
const COMPACT_LOGO := 250
const MODES := [
	{"kind": "owner", "title": "Owner Mode", "skin": FcModeSkin.FRANCHISE, "status": "Available", "tone": FcStatusChip.Tone.INFO, "stretch": 1.5, "min_width": 300,
		"blurb": "Run every part of a franchise for up to 50 seasons: money, people, players, the draft, the league's rules.", "action": "open_owner"},
	{"kind": "career", "title": "Career Mode", "skin": FcModeSkin.BROADCAST, "status": "Playable", "tone": FcStatusChip.Tone.SUCCESS, "stretch": 1.0, "min_width": 270,
		"blurb": "Create one player and take them through a career. Draft, contracts, teams, rivalries.", "action": "open_career"},
	{"kind": "dynasty", "title": "Dynasty Mode", "skin": FcModeSkin.COLLECTIBLE, "status": "Playable", "tone": FcStatusChip.Tone.SUCCESS, "stretch": 1.0, "min_width": 270,
		"blurb": "Collect fictional player cards, open packs, build a 13-player roster and compete in challenges and tournaments.", "action": "open_dynasty"},
]


## Fills `box`. Returns {"mode_cards": Array[FcModeCard], "save_cards": Array[FcSaveCard], "continue_button": FcButton or null}.
static func build(box: VBoxContainer, slots: Array, actions: Dictionary, options: Dictionary = {}) -> Dictionary:
	var compact := bool(options.get("compact", false))
	var result := {"mode_cards": [], "save_cards": [], "continue_button": null}
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", FcUiTokens.SPACE_4)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(page)
	page.name = "MenuPage"
	box.add_child(scroll)
	_header(page, compact)
	var warning := str(options.get("content_warning", ""))
	if warning != "":
		var warn := FcUiTables.label(warning, FcUiTokens.TYPE_SMALL)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		page.add_child(warn)
	var latest: FcSaveMetadata = null
	for m in slots:
		if m.readable:
			latest = m
			break
	if latest != null:
		result["continue_button"] = _continue_card(page, latest, actions, compact)
	result["mode_cards"] = _mode_cards(page, actions, compact)
	if not slots.is_empty():
		result["save_cards"] = _saved_games(page, slots, actions, options, compact)
	_footer(page, actions, compact)
	return result


static func _header(page: VBoxContainer, compact: bool) -> void:
	var logo := FcBrand.logo(FcBrand.FULL_COURT, COMPACT_LOGO if compact else WIDE_LOGO, "FULL COURT")
	page.add_child(logo)
	var tagline := FcUiTables.label("Basketball management simulation. Choose how you want to play.", FcUiTokens.TYPE_BODY)
	tagline.theme_type_variation = "MutedLabel"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(tagline)


static func _continue_card(page: VBoxContainer, meta: FcSaveMetadata, actions: Dictionary, compact: bool) -> FcButton:
	var mode := str(meta.mode).to_lower()
	var accent: Color = FcModeSkin.resolve(str(FcSaveCard.MODE_SKINS.get(mode, FcModeSkin.NEUTRAL)))["accent"]
	var panel := FcPanel.new("", FcPanel.Variant.RAISED)
	panel.set_accent(accent)
	panel.name = "ContinueCard"
	var row: BoxContainer = HBoxContainer.new() if not compact else VBoxContainer.new()
	row.add_theme_constant_override("separation", FcUiTokens.SPACE_4)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 1)
	var caption := FcUiTables.label("CONTINUE WHERE YOU LEFT OFF", FcUiTokens.TYPE_MICRO + 1)
	caption.theme_type_variation = "CaptionLabel"
	text.add_child(caption)
	var title := FcUiTables.label(meta.label if meta.label != "" else meta.slot_id, FcUiTokens.TYPE_H2, true)
	title.clip_text = true   # a long save name is cut with an ellipsis instead of widening the menu
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(title)
	var detail := FcUiTables.label(FcSaveCard.detail_text(meta), FcUiTokens.TYPE_SMALL)
	detail.theme_type_variation = "MutedLabel"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(detail)
	row.add_child(text)
	var button := FcButton.make("Continue", FcButton.Variant.PRIMARY, actions["continue_latest"], "play")
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(button)
	panel.add(row)
	page.add_child(panel)
	return button


static func _mode_cards(page: VBoxContainer, actions: Dictionary, compact: bool) -> Array:
	# a flow: the three cards sit in one row when the window is wide (Owner widest) and wrap into a stack when it is narrow
	var holder := HFlowContainer.new()
	holder.add_theme_constant_override("h_separation", FcUiTokens.SPACE_4)
	holder.add_theme_constant_override("v_separation", FcUiTokens.SPACE_4)
	holder.name = "ModeCards"
	var cards: Array = []
	for m in MODES:
		var card := FcModeCard.new(str(m["kind"]), str(m["title"]), str(m["blurb"]), str(m["status"]), m["tone"], str(m["skin"]), 150 if compact else 190)
		card.size_flags_stretch_ratio = float(m["stretch"])
		card.custom_minimum_size.x = float(m["min_width"])
		card.chosen.connect(actions[str(m["action"])])
		holder.add_child(card)
		cards.append(card)
	page.add_child(holder)
	return cards


static func _saved_games(page: VBoxContainer, slots: Array, actions: Dictionary, options: Dictionary, compact: bool) -> Array:
	var heading := FcUiTables.label("Saved games", FcUiTokens.TYPE_H3, true)
	page.add_child(heading)
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", FcUiTokens.SPACE_3)
	grid.add_theme_constant_override("v_separation", FcUiTokens.SPACE_2)
	grid.name = "SavedGames"
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cards: Array = []
	var chosen_slot := str(options.get("selected_slot", slots[0].slot_id))
	for m in slots:
		var card := FcSaveCard.new(m)
		card.custom_minimum_size.x = 330 if compact else 420
		card.is_selected = m.slot_id == chosen_slot
		card.selected.connect(func(slot_id: String) -> void:
			for c in cards:
				c.is_selected = c.slot_id == slot_id
			actions["select"].call(slot_id))
		card.load_requested.connect(actions["load"])
		card.delete_requested.connect(actions["delete"])
		grid.add_child(card)
		cards.append(card)
	page.add_child(grid)
	return cards


static func _footer(page: VBoxContainer, actions: Dictionary, compact: bool) -> void:
	var footer: BoxContainer = VBoxContainer.new() if compact else HBoxContainer.new()
	footer.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	var buttons := HFlowContainer.new()
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	buttons.add_child(FcButton.make("Settings", FcButton.Variant.GHOST, actions["settings"], "settings"))
	buttons.add_child(FcButton.make("Credits", FcButton.Variant.GHOST, actions["credits"], "info"))
	if actions.has("gallery"):
		buttons.add_child(FcButton.make("Gallery (dev)", FcButton.Variant.GHOST, actions["gallery"], "layers"))
	buttons.add_child(FcButton.make("Quit", FcButton.Variant.GHOST, actions["quit"]))
	footer.add_child(buttons)
	var studio := FcBrand.logo(FcBrand.NOVAERIS_WORDMARK, 128, "Novaeris")
	studio.modulate.a = 0.8
	studio.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	studio.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if compact else Control.SIZE_SHRINK_END
	footer.add_child(studio)
	page.add_child(footer)
