extends FcTestCase
## The main menu and the brand (Phase D, D-057): the logo loader and its fallback, the three mode cards, the save cards and the Continue card,
## the startup splash, the credits, and the new preference. How it LOOKS is checked in the screenshots and the live test; this file checks
## what it contains and does.


func _meta(slot: String, label: String, mode: String = "owner", readable: bool = true) -> FcSaveMetadata:
	var m := FcSaveMetadata.new()
	m.slot_id = slot
	m.label = label
	m.mode = mode
	m.team_name = "Harbor Kings"
	m.season = 2026
	m.saved_at = "2026-11-21T18:16:08"
	m.readable = readable
	return m


func _actions(log: Array) -> Dictionary:
	return {"open_owner": func() -> void: log.append("owner"), "open_career": func() -> void: log.append("career"), "open_dynasty": func() -> void: log.append("dynasty"),
		"continue_latest": func() -> void: log.append("continue"), "load": func(s: String) -> void: log.append("load " + s), "delete": func(s: String) -> void: log.append("delete " + s),
		"select": func(s: String) -> void: log.append("select " + s), "settings": func() -> void: log.append("settings"), "credits": func() -> void: log.append("credits"),
		"quit": func() -> void: log.append("quit")}


# --- brand -----------------------------------------------------------------------------------------------------------

func test_the_brand_files_load() -> void:
	for id in [FcBrand.FULL_COURT, FcBrand.NOVAERIS, FcBrand.NOVAERIS_MARK, FcBrand.NOVAERIS_WORDMARK]:
		assert_true(FcBrand.has(id), id + " loads")


func test_a_logo_picks_the_smallest_prepared_size_that_is_wide_enough() -> void:
	var small := FcBrand.texture(FcBrand.FULL_COURT, 200)
	var mid := FcBrand.texture(FcBrand.FULL_COURT, 700)
	var master := FcBrand.texture(FcBrand.FULL_COURT, 0)
	assert_eq(small.get_width(), 256)
	assert_eq(mid.get_width(), 1024)
	assert_true(master.get_width() > 1024, "no size asked for gives the master")
	assert_eq(FcBrand.texture(FcBrand.FULL_COURT, 5000).get_width(), master.get_width(), "wider than any copy: the master, never an upscale")


func test_a_logo_control_carries_the_brand_name_and_the_right_shape() -> void:
	var logo := FcBrand.logo(FcBrand.FULL_COURT, 300, "FULL COURT")
	assert_eq(logo.name, "Logo")
	assert_eq(logo.tooltip_text, "FULL COURT")
	assert_true(logo is TextureRect and logo.custom_minimum_size.x == 300.0 and logo.custom_minimum_size.y > 50.0)
	logo.free()


func test_a_missing_logo_falls_back_to_a_text_wordmark() -> void:
	var logo := FcBrand.logo("no_such_logo", 300, "FULL COURT")
	assert_true(logo is Label and (logo as Label).text == "FULL COURT", "text instead of an error")
	assert_true(not FcBrand.has("no_such_logo"))
	logo.free()


# --- the menu --------------------------------------------------------------------------------------------------------

func test_without_saves_the_menu_has_three_mode_cards_and_no_continue() -> void:
	var box := VBoxContainer.new()
	var result := FcMainMenu.build(box, [], _actions([]))
	assert_eq(result["mode_cards"].size(), 3)
	assert_eq(result["save_cards"].size(), 0)
	assert_eq(result["continue_button"], null)
	assert_true(box.find_child("ContinueCard", true, false) == null, "no Continue card")
	box.free()


func test_each_mode_card_opens_its_mode() -> void:
	var log: Array = []
	var box := VBoxContainer.new()
	var result := FcMainMenu.build(box, [], _actions(log))
	var names: Array = []
	for card in result["mode_cards"]:
		names.append(card.mode_name)
		card.button.pressed.emit()
	assert_eq(names, ["Owner Mode", "Career Mode", "Dynasty Mode"])
	assert_eq(log, ["owner", "career", "dynasty"])
	(result["mode_cards"][0] as FcModeCard).chosen.emit()
	assert_eq(log.back(), "owner", "the whole card is a click target too")
	box.free()


func test_the_three_modes_have_three_different_compositions_and_accents() -> void:
	var kinds := {}
	var accents := {}
	var box := VBoxContainer.new()
	for card in FcMainMenu.build(box, [], _actions([]))["mode_cards"]:
		kinds[card.art.kind] = true
		accents[card.art.accent.to_html()] = true
	assert_eq(kinds.size(), 3, "owner, career and dynasty each have their own picture")
	assert_eq(accents.size(), 3, "and their own colour")
	box.free()


func test_saves_become_cards_with_a_continue_card_for_the_latest_readable_one() -> void:
	var log: Array = []
	var box := VBoxContainer.new()
	var slots := [_meta("a", "Newest", "owner", false), _meta("b", "Second"), _meta("c", "Third", "career")]
	var result := FcMainMenu.build(box, slots, _actions(log), {"selected_slot": "b"})
	assert_eq(result["save_cards"].size(), 3)
	assert_true(result["continue_button"] != null, "a Continue card")
	assert_true((box.find_child("ContinueCard", true, false) as Control).get_child_count() > 0)
	result["continue_button"].pressed.emit()
	assert_eq(log, ["continue"])
	var cards: Array = result["save_cards"]
	assert_true(cards[1].is_selected and not cards[0].is_selected, "the chosen slot starts highlighted")
	assert_true(cards[0].load_button.disabled, "a damaged save cannot be loaded")
	assert_eq(cards[0].status_chip.label_node.text, "Damaged")
	cards[2].load_button.pressed.emit()
	cards[1].delete_button.pressed.emit()
	assert_eq(log.slice(1), ["load c", "delete b"])
	box.free()


func test_when_every_save_is_damaged_there_is_no_continue() -> void:
	var box := VBoxContainer.new()
	var result := FcMainMenu.build(box, [_meta("a", "Broken", "owner", false)], _actions([]))
	assert_eq(result["continue_button"], null)
	assert_eq(result["save_cards"].size(), 1, "the damaged save is still listed (so it can be deleted)")
	box.free()


func test_selecting_a_card_highlights_it_and_tells_the_app() -> void:
	var log: Array = []
	var box := VBoxContainer.new()
	var result := FcMainMenu.build(box, [_meta("a", "One"), _meta("b", "Two")], _actions(log))
	var cards: Array = result["save_cards"]
	cards[1].selected.emit("b")
	assert_true(cards[1].is_selected and not cards[0].is_selected)
	assert_eq(log, ["select b"])
	box.free()


func test_save_card_text_is_readable_and_complete() -> void:
	var m := _meta("a", "Houston dynasty")
	assert_eq(FcSaveCard.detail_text(m), "Harbor Kings  ·  Season 2026-27  ·  Owner")
	assert_eq(FcSaveCard.status_text(m), "Ready")
	m.readable = false
	assert_eq(FcSaveCard.status_text(m), "Damaged")
	var card := FcSaveCard.new(_meta("a", "Houston dynasty"))
	assert_eq(card.title_label.text, "Houston dynasty")
	assert_true(card.saved_label.text.begins_with("Saved 2026-11-21 18:16"))
	card.free()


func test_the_footer_has_settings_credits_quit_and_the_studio_mark() -> void:
	var log: Array = []
	var box := VBoxContainer.new()
	FcMainMenu.build(box, [], _actions(log))
	var labels: Array = []
	_collect_buttons(box, labels)
	for expected in ["Settings", "Credits", "Quit"]:
		assert_true(expected in labels, expected + " button")
	var studio := false
	for n in box.find_children("Logo", "", true, false):
		if (n as Control).get_meta("brand_id", "") == FcBrand.NOVAERIS_WORDMARK or (n is Label and (n as Label).text == "Novaeris"):
			studio = true
	assert_true(studio, "the small Novaeris mark is in the footer")
	box.free()


func _collect_buttons(node: Node, out: Array) -> void:
	if node is Button:
		out.append((node as Button).text)
	for c in node.get_children():
		_collect_buttons(c, out)


# --- splash, credits, preference -------------------------------------------------------------------------------------

func test_the_splash_can_show_and_finishes_once() -> void:
	assert_true(FcSplash.can_show(), "both logos exist")
	var splash := FcSplash.new()
	var done: Array = []
	splash.finished.connect(func() -> void: done.append(true))
	splash._finish()
	splash._finish()
	assert_eq(done.size(), 1, "skipping twice still finishes once")
	splash.free()


func test_the_credits_name_both_brands_and_what_the_game_is_built_with() -> void:
	var box := VBoxContainer.new()
	FcCredits.build(box, {"back": func() -> void: pass, "open_logs": func() -> void: pass, "open_saves": func() -> void: pass, "open_content": func() -> void: pass}, "Release 1 is playable.")
	var texts: Array = []
	_collect_texts(box, texts)
	var joined := "\n".join(texts)
	for expected in ["Made by Novaeris", "Built with", "Inter", "Barlow Condensed", "Lucide", "Godot Engine", "Open the logs folder", "Release 1 is playable."]:
		assert_true(joined.contains(expected), "the credits mention " + expected)
	assert_true(box.find_children("Logo", "", true, false).size() >= 2, "both logos")
	box.free()


func _collect_texts(node: Node, out: Array) -> void:
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	for c in node.get_children():
		_collect_texts(c, out)


func test_the_startup_logos_preference_defaults_on_and_is_remembered() -> void:
	var path := "user://test_prefs_menu.cfg"
	var prefs := FcPreferences.new(path)
	assert_true(prefs.show_splash, "on by default")
	prefs.show_splash = false
	prefs.save_file()
	var again := FcPreferences.new(path)
	again.load_file()
	assert_true(not again.show_splash, "the choice is remembered")
	DirAccess.remove_absolute(path)
