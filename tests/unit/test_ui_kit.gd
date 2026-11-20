extends FcTestCase
## The component kit (src/ui/kit): each component builds, shows every state it claims, and emits the signals screens rely on.
## (How they LOOK is checked in the Component Gallery screenshots; these tests check structure and behaviour.)

var host: Control
var got: Array = []


func before_each() -> void:
	FcUiTheme.build(1)
	host = Control.new()
	host.size = Vector2(800, 600)
	Engine.get_main_loop().root.add_child(host)
	got = []


func after_each() -> void:
	FcMotion.reduced = false
	FcUiTokens.touch_mode = false
	Engine.get_main_loop().root.remove_child(host)
	host.free()


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for c in node.get_children():
		var found := _find_button(c, text)
		if found != null:
			return found
	return null


# --- buttons ------------------------------------------------------------------------------------------------------------

func test_button_variants_map_to_theme_variations() -> void:
	var expected := {FcButton.Variant.PRIMARY: "PrimaryButton", FcButton.Variant.SECONDARY: "", FcButton.Variant.DESTRUCTIVE: "DangerButton",
		FcButton.Variant.GHOST: "GhostButton", FcButton.Variant.ICON: "IconButton"}
	for variant in expected:
		var b := FcButton.make("x", variant)
		assert_eq(b.theme_type_variation, expected[variant], "variant %s" % variant)
		b.free()


func test_button_press_emits_and_icon_loads() -> void:
	var b := FcButton.make("Go", FcButton.Variant.PRIMARY, func() -> void: got.append("pressed"), "play")
	host.add_child(b)
	b.pressed.emit()
	assert_eq(got, ["pressed"])
	assert_true(b.icon != null, "icon from the Lucide bundle")
	b.icon_name = "no-such-icon"
	assert_true(b.icon == null, "an unknown icon is simply absent")


func test_button_loading_disables_and_restores() -> void:
	var b := FcButton.make("Save")
	host.add_child(b)
	b.loading = true
	assert_true(b.disabled, "disabled while loading")
	assert_eq(b.text, "Working...")
	b.loading = false
	assert_true(not b.disabled and b.text == "Save", "restored")
	b.disabled = true
	b.loading = true
	b.loading = false
	assert_true(b.disabled, "a button that was disabled before loading stays disabled")


func test_buttons_grow_to_the_touch_target_on_touch_layouts() -> void:
	assert_eq(FcButton.make("x").custom_minimum_size.y, float(FcUiTokens.DESKTOP_TARGET), "desktop height")
	FcUiTokens.touch_mode = true
	assert_eq(FcButton.make("x").custom_minimum_size.y, float(FcUiTokens.TOUCH_TARGET), "touch height is at least 44")
	var icon := FcButton.icon_only("settings", "Settings")
	assert_true(icon.custom_minimum_size.x >= 44 and icon.tooltip_text == "Settings", "icon buttons are square touch targets with a tooltip")


# --- navigation and selection --------------------------------------------------------------------------------------------

func test_tab_bar_selects_and_emits_only_for_the_player() -> void:
	var tabs := FcTabBar.new()
	host.add_child(tabs)
	tabs.set_tabs([["a", "One"], ["b", "Two", "trophy"], ["c", "Three"]])
	tabs.tab_selected.connect(func(id: String) -> void: got.append(id))
	assert_eq(tabs.current_id, "a", "the first tab opens")
	tabs.select("b")
	assert_eq(got, [], "select() is silent")
	tabs.button_for("c").pressed.emit()
	assert_eq(got, ["c"])
	tabs.button_for("c").pressed.emit()
	assert_eq(got, ["c"], "choosing the open tab again does nothing")
	assert_eq(tabs.tab_ids().size(), 3)
	assert_true(tabs.button_for("b").icon != null, "a tab can carry an icon")
	assert_eq(tabs.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO, "scrolls sideways instead of forcing the window wider")


func test_tab_bar_keeps_the_selection_when_the_tabs_are_replaced() -> void:
	var tabs := FcTabBar.new()
	host.add_child(tabs)
	tabs.set_tabs([["a", "One"], ["b", "Two"]], "b")
	assert_eq(tabs.current_id, "b")
	tabs.set_tabs([["x", "X"]], "missing")
	assert_eq(tabs.current_id, "x", "an unknown selection falls back to the first tab")


func test_choice_group_is_single_choice() -> void:
	var group := FcChoiceGroup.new()
	host.add_child(group)
	group.set_options([["grid", "Grid"], ["carousel", "Carousel"]], "carousel")
	group.selected.connect(func(id: String) -> void: got.append(id))
	assert_eq(group.current_id, "carousel")
	group.button_for("grid").pressed.emit()
	assert_eq(got, ["grid"])


func test_dropdown_returns_values_and_shows_errors() -> void:
	var dd := FcDropdown.make([["Any", ""], ["Guard", "G"], ["Center", "C"]], "G", func(v) -> void: got.append(v))
	host.add_child(dd)
	assert_eq(dd.value(), "G", "the current value is selected")
	dd.item_selected.emit(2)
	assert_eq(got, ["C"], "chosen carries the value, not the label")
	dd.select_value("")
	assert_eq(dd.value(), "")
	assert_eq(dd.theme_type_variation, "")
	dd.error = true
	assert_eq(dd.theme_type_variation, "ErrorOption", "error state is a red outline")
	dd.error = false
	assert_eq(dd.theme_type_variation, "")


func test_toggle_reports_changes() -> void:
	var t := FcToggle.make("Sound", true, func(on: bool) -> void: got.append(on))
	host.add_child(t)
	assert_true(t.button_pressed, "starts on without firing")
	assert_eq(got, [])
	t.button_pressed = false
	assert_eq(got, [false])


func test_slider_shows_its_value_and_can_be_set_silently() -> void:
	var s := FcSlider.new(0, 100, 5, "%")
	s.set_value_silent(70)
	assert_eq(s.readout.text, "70%", "the readout follows a restored value")
	assert_eq(s.value(), 70.0)
	s.disabled = true
	assert_true(not s.slider.editable, "disabled")
	s.free()   # emission and dragging need a live tree: tests/live/test_live_kit.gd


func test_progress_variants_and_clamping() -> void:
	var variations := {FcProgress.Variant.ACCENT: "", FcProgress.Variant.SUCCESS: "SuccessProgress", FcProgress.Variant.DANGER: "DangerProgress", FcProgress.Variant.GOLD: "GoldProgress"}
	for v in variations:
		var p := FcProgress.new(v)
		assert_eq(p.theme_type_variation, variations[v])
		p.free()
	var bar := FcProgress.new()
	bar.set_progress(150, 100)
	assert_eq(bar.value, 100.0, "clamped to the maximum")
	bar.set_progress(5, 0)
	assert_eq(bar.max_value, 1.0, "a zero maximum cannot divide by zero")
	FcMotion.reduced = true
	host.add_child(bar)
	bar.set_progress_animated(40, 100)
	assert_eq(bar.value, 40.0, "reduced motion jumps")


func test_search_field_submits_and_shows_its_states() -> void:
	var f := FcSearchField.new("Find")
	f.search_changed.connect(func(q: String) -> void: got.append(q))
	f.text_submitted.emit("maya")
	assert_eq(got, ["maya"], "Enter searches immediately")
	assert_eq(f.placeholder_text, "Find")
	assert_true(f.clear_button_enabled, "has a clear button")
	assert_true(f._glyph.texture == FcUiIcons.texture("search"), "search icon")
	f.loading = true
	assert_true(f._glyph.texture == FcUiIcons.texture("loader"), "loading shows the spinner glyph")
	f.loading = false
	assert_true(f._glyph.texture == FcUiIcons.texture("search"))
	f.error = true
	assert_eq(f.theme_type_variation, "ErrorLineEdit")
	f.free()   # the typing delay (debounce) is timer based: tests/live/test_live_kit.gd


# --- feedback -----------------------------------------------------------------------------------------------------------

func test_modal_confirm_and_cancel_paths() -> void:
	var m := FcModal.confirm(host, "Delete?", "Gone for good.", func() -> void: got.append("confirmed"), true, "Delete")
	assert_true(m.get_parent() == host, "opened on the parent")
	assert_true(m.cancel_button != null, "a confirmation has a cancel button")
	assert_eq(m.confirm_button.theme_type_variation, "DangerButton", "destructive confirm is red")
	m.cancelled.connect(func() -> void: got.append("cancelled"))
	m.confirm_button.pressed.emit()
	m.close(false)
	assert_eq(got, ["confirmed"], "closing twice does nothing more")


func test_modal_cancel_and_info_dialogs() -> void:
	var m := FcModal.confirm(host, "Next season?", "", func() -> void: got.append("confirmed"))
	m.cancelled.connect(func() -> void: got.append("cancelled"))
	m.cancel_button.pressed.emit()
	assert_eq(got, ["cancelled"], "cancel does not confirm")
	var info := FcModal.notice(host, "Saved", "All done.")
	assert_true(info.cancel_button == null, "an info dialog has one button")
	assert_eq(info.confirm_button.theme_type_variation, "PrimaryButton")


func test_modal_scrim_click_cancels_only_when_dismissible() -> void:
	var m := FcModal.confirm(host, "x", "", func() -> void: pass)
	m.dismissible = false
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	m.cancelled.connect(func() -> void: got.append("cancelled"))
	m._on_scrim_input(click)
	assert_eq(got, [], "a non-dismissible dialog ignores outside clicks")
	m.dismissible = true
	m._on_scrim_input(click)
	assert_eq(got, ["cancelled"])


func test_toasts_never_block_the_controls_beneath_them_on_desktop() -> void:
	# regression: a toast once covered "Sign selected free agent" and swallowed the click (found by tools/click_test.gd)
	var desktop := FcToast.new(FcToast.Kind.INFO, "Released a player.")
	assert_eq(desktop.mouse_filter, Control.MOUSE_FILTER_IGNORE, "clicks pass through a desktop toast")
	assert_eq(desktop.size_flags_horizontal, Control.SIZE_SHRINK_END, "it sits at the right, away from the main buttons")
	FcUiTokens.touch_mode = true
	var touch := FcToast.new(FcToast.Kind.INFO, "Released a player.")
	assert_eq(touch.mouse_filter, Control.MOUSE_FILTER_STOP, "on touch a tap dismisses it")
	assert_eq(touch.size_flags_horizontal, Control.SIZE_SHRINK_CENTER)
	for t in [desktop, touch]:
		t.free()


func test_toasts_say_what_kind_they_are_and_errors_stay_longer() -> void:
	assert_eq(FcToast.hold_seconds(FcToast.Kind.INFO), 3.0)
	assert_eq(FcToast.hold_seconds(FcToast.Kind.ERROR), 6.0)
	for kind in FcToast.COLORS:
		assert_true(FcUiIcons.has_icon(FcToast.ICONS[kind]), "icon for toast kind %s" % kind)
	var t := FcToast.new(FcToast.Kind.ERROR, "The save failed")
	assert_eq(t.message, "The save failed")
	assert_eq(t.kind, FcToast.Kind.ERROR)
	t.free()


func test_loading_overlay_blocks_clicks_and_updates_its_message() -> void:
	var overlay := FcLoadingOverlay.show_on(host, "Simulating...")
	assert_eq(overlay.mouse_filter, Control.MOUSE_FILTER_STOP, "blocks the screen below")
	assert_eq(overlay.loading.message_label.text, "Simulating...")
	overlay.loading.set_message("Almost done")
	assert_eq(overlay.loading.message_label.text, "Almost done")
	overlay.dismiss()


func test_empty_state_kinds_and_action() -> void:
	var plain := FcEmptyState.new("No cards", "Open a pack.")
	assert_true(plain.action_button == null, "no action unless asked")
	var error := FcEmptyState.new("Failed", "Try again.", FcEmptyState.Kind.ERROR, "", "Retry", func() -> void: got.append("retry"))
	host.add_child(error)
	error.action_button.pressed.emit()
	assert_eq(got, ["retry"])
	for kind in FcEmptyState.ICONS:
		assert_true(FcUiIcons.has_icon(FcEmptyState.ICONS[kind]))
	assert_eq(plain.title_label.text, "No cards")


# --- data ---------------------------------------------------------------------------------------------------------------

func test_data_table_is_a_tree_on_desktop_and_cards_on_compact() -> void:
	var columns := ["Player", "Pos", "OVR"]
	var rows := [["Maya", "PG", 84], ["Dev", "C", 79]]
	var desktop := FcDataTable.build(columns, rows, [0, 60, 60], {"compact": false})
	assert_true(desktop is Tree, "desktop keeps the dense table (existing behaviour)")
	var compact := FcDataTable.build(columns, rows, [], {"compact": true})
	assert_eq(compact.get_child_count(), 2, "one card per row")
	var card: FcPanel = compact.get_child(0)
	assert_eq(card.body.get_child_count(), 3, "title plus one line per other column")
	FcUiTokens.touch_mode = true
	assert_true(not (FcDataTable.build(columns, rows) is Tree), "touch layouts default to cards")
	for c in [desktop, compact]:
		c.free()


func test_empty_data_table_explains_itself() -> void:
	var t := FcDataTable.build(["A"], [], [], {"empty_title": "No players", "empty_text": "Sign someone."})
	assert_true(t is FcEmptyState)
	assert_eq((t as FcEmptyState).title_label.text, "No players")
	t.free()


func test_filter_bar_collects_choices_and_clears() -> void:
	var bar := FcFilterBar.new()
	host.add_child(bar)
	var search := bar.add_search("q")
	var dd := bar.add_dropdown("position", "Any position", [["Guard", "G"], ["Center", "C"]])
	bar.add_chips("rarity", [["Common", "common"], ["Rare", "rare"]], true)
	bar.add_chips("owned", [["Owned", "yes"], ["Missing", "no"]], false)
	bar.changed.connect(func(v: Dictionary) -> void: got.append(v))
	assert_eq(bar.values(), {"q": "", "position": "", "rarity": [], "owned": ""})
	dd.item_selected.emit(1)
	assert_eq(got.back()["position"], "G")
	search.search_changed.emit("maya")
	assert_eq(got.back()["q"], "maya")
	var rare := _find_button(bar, "Rare")
	rare.button_pressed = true
	assert_eq(got.back()["rarity"], ["rare"], "multi chips collect a list")
	_find_button(bar, "Common").button_pressed = true
	assert_eq(got.back()["rarity"], ["rare", "common"])
	rare.button_pressed = false
	assert_eq(got.back()["rarity"], ["common"])
	var owned := _find_button(bar, "Owned")
	var missing := _find_button(bar, "Missing")
	owned.button_pressed = true
	missing.button_pressed = true
	assert_eq(got.back()["owned"], "no", "single chips are exclusive")
	assert_true(not owned.button_pressed, "the other chip lets go")
	missing.button_pressed = false
	assert_eq(got.back()["owned"], "", "clicking the open chip clears it")
	var count := got.size()
	bar.clear()
	assert_eq(got.size(), count + 1, "clear emits once")
	assert_eq(bar.values(), {"q": "", "position": "", "rarity": [], "owned": ""})


func test_filter_bar_restores_choices_silently() -> void:
	var bar := FcFilterBar.new()
	host.add_child(bar)
	bar.add_search("q")
	bar.add_dropdown("position", "Any", [["Guard", "G"]])
	bar.add_chips("rarity", [["Rare", "rare"]], true)
	bar.changed.connect(func(_v: Dictionary) -> void: got.append("changed"))
	bar.set_values({"q": "okoro", "position": "G", "rarity": ["rare"]})
	assert_eq(got, [], "restoring does not emit")
	assert_eq(bar.values(), {"q": "okoro", "position": "G", "rarity": ["rare"]})
	assert_true(_find_button(bar, "Rare").button_pressed, "the chip shows as pressed")


func test_rating_badge_uses_one_tier_colour_per_rating() -> void:
	var low := FcRatingBadge.new(50)
	var high := FcRatingBadge.new(90)
	assert_eq(low.number.text, "50")
	assert_true(low.number.get_theme_color("font_color") != high.number.get_theme_color("font_color"), "different tiers, different colours")
	assert_eq(high.tooltip_text, "Star", "the tier name is the tooltip")
	assert_eq(FcRatingBadge.new(150).value, 99, "ratings clamp to 99")
	assert_eq(FcRatingBadge.new(-4).value, 0)
	var same_a := FcRatingBadge.new(78)
	var same_b := FcRatingBadge.new(78)
	assert_eq(same_a.number.get_theme_color("font_color"), same_b.number.get_theme_color("font_color"), "the same rating always looks the same")
	for b in [low, high, same_a, same_b]:
		b.free()


func test_stat_tile_colours_its_change() -> void:
	var up := FcStatTile.make("Overall", "84", "+2")
	var down := FcStatTile.make("Cash", "$1M", "-3")
	var flat := FcStatTile.make("Record", "3-1")
	assert_eq(up.delta_node.get_theme_color("font_color"), FcUiTokens.SUCCESS)
	assert_eq(down.delta_node.get_theme_color("font_color"), FcUiTokens.DANGER)
	assert_true(not flat.delta_node.visible, "no change, no row")
	assert_eq(up.label_node.text, "OVERALL", "labels are small caps")
	for t in [up, down, flat]:
		t.free()


func test_stat_bar_picks_the_leader_and_shares_the_bar() -> void:
	var bar := FcStatBar.new("Rebounds", 40, 60)
	assert_eq(bar.leader(), 1, "the right side leads")
	assert_eq(bar.left_share(), 0.4)
	bar.set_values(50, 50)
	assert_eq(bar.leader(), -1, "level")
	bar.set_values(0, 0)
	assert_eq(bar.left_share(), 0.5, "zero totals split evenly")
	var turnovers := FcStatBar.new("Turnovers", 11, 15, "", "", true)
	assert_eq(turnovers.leader(), 0, "fewer turnovers lead")
	bar.free()
	turnovers.free()


func test_stat_line_and_status_chip_and_panel() -> void:
	var line := FcStatLine.make("Points", "24.3", true)
	assert_eq(line.label_node.text, "Points")
	assert_eq(line.value_node.text, "24.3")
	assert_eq(line.value_node.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT, "numbers align right")
	for tone in FcStatusChip.COLORS:
		var chip := FcStatusChip.make("x", tone)
		assert_eq(chip.tone, tone)
		chip.free()
	var panel := FcPanel.new("Title", FcPanel.Variant.MODAL)
	assert_eq(panel.theme_type_variation, "ModalPanel")
	assert_eq(panel.body.get_child_count(), 1, "the title is the first row")
	panel.add(Label.new())
	assert_eq(panel.body.get_child_count(), 2)
	for n in [line, panel]:
		n.free()


# --- broadcast and franchise sets ---------------------------------------------------------------------------------------------

func test_score_bug_reads_like_a_scoreboard() -> void:
	var bug := FcScoreBug.new()
	bug.setup("HBR", 108, "SKY", 101, "Final")
	assert_eq(bug.summary(), "HBR 108 FINAL 101 SKY")
	bug.free()


func test_lower_third_and_letterhead_and_kpi_strip() -> void:
	var third := FcLowerThird.new("Player of the game", "Maya Okoro")
	assert_eq(third.title_label.text, "Player of the game", "the title is shown exactly as given (a player name keeps its case)")
	var quiet := FcLowerThird.new("Title")
	assert_true(not quiet.subtitle_label.visible, "no subtitle, no row")
	var head := FcLetterhead.new()
	head.setup("Harbor Kings", "Season 3", "HBKX", "#1F3A5F", "#1F3A5F")
	assert_eq(head._crest_text.text, "HBK", "the crest shows at most three letters")
	var ink: Color = head._crest_text.get_theme_color("font_color")
	assert_true(FcUiContrast.ratio(ink, Color("#1F3A5F")) >= 4.5, "crest text stays readable even when the branding colours match")
	var kpi := FcKpiStrip.new()
	kpi.set_items([{"label": "Cash", "value": "$4M"}, {"label": "Record", "value": "3-1", "delta": "+1"}])
	assert_eq(kpi.tile_count(), 2)
	kpi.set_items([{"label": "Only", "value": "1"}])
	assert_eq(kpi.tile_count(), 1, "set_items replaces the tiles")
	for n in [third, quiet, head, kpi]:
		n.free()


# --- the gallery --------------------------------------------------------------------------------------------------------------

func test_the_gallery_builds_every_section_in_every_skin_and_layout() -> void:
	var gallery := FcComponentGallery.new()
	gallery.size = Vector2(900, 700)
	host.add_child(gallery)
	gallery.build()
	var titles := gallery.section_titles()
	for expected in ["Colour", "Typography", "Buttons", "Inputs and navigation", "Feedback", "Data", "Cards", "Broadcast set", "Franchise set", "Motion"]:
		assert_true(expected in titles, "section " + expected)
	for skin in FcModeSkin.ids():
		gallery.set_skin(skin)
		assert_eq(gallery.section_titles().size(), 10, "%s skin keeps every section" % skin)
	for index in 3:
		gallery.set_text_index(index)
		assert_eq(gallery.section_titles().size(), 10)
	FcUiTokens.touch_mode = true
	gallery.build()
	assert_eq(gallery.section_titles().size(), 10, "touch layout builds too")
	var closed := []
	gallery.closed.connect(func() -> void: closed.append(true))
	_find_button(gallery, "Back").pressed.emit()
	assert_eq(closed, [true], "Back asks the app to leave")
	FcUiTheme.build(1)


func test_the_gallery_opens_from_the_app_and_restores_the_players_settings() -> void:
	var app := FcApp.new()
	app.preferences = FcPreferences.new("user://test_preferences.cfg")
	app.preferences.tutorial_done = true
	app.preferences.reduce_motion = false
	app.saves = FcSaveManager.new("user://test_saves_ui_kit")
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	app.show_gallery()
	var gallery: FcComponentGallery = app._form["gallery"]
	assert_true(gallery != null and gallery.get_parent() != null, "the gallery is shown by the app")
	FcUiTokens.touch_mode = true
	FcMotion.reduced = true
	gallery.set_text_index(2)
	gallery.closed.emit()
	assert_true(not FcUiTokens.touch_mode and not FcMotion.reduced, "leaving restores touch and motion")
	assert_eq(FcUiTokens.text_scale, FcUiTokens.TEXT_SCALES[app.preferences.text_size], "and the player's own text size")
	Engine.get_main_loop().root.remove_child(app)
	app.free()
	FcSafeFile.remove_tree("user://test_saves_ui_kit")
