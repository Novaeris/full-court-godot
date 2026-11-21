extends FcTestCase
## Regression tests for what the release screen matrix and the Owner presentation audit found (docs/validation/OWNER_PRESENTATION_AUDIT.md).


func after_each() -> void:
	FcUiTokens.touch_mode = false


func test_selecting_a_tab_from_code_leaves_exactly_one_tab_open() -> void:
	var bar := FcTabBar.new()
	bar.set_tabs([["a", "Overview"], ["b", "Roster"], ["c", "Finances"]], "a")
	bar.select("b")   # what an Owner screen does when it rebuilds on the tab the player was last on
	var open := 0
	for id in bar.tab_ids():
		if bar.button_for(id).button_pressed:
			open += 1
	assert_eq(open, 1, "only one tab looks open")
	assert_true(bar.button_for("b").button_pressed and not bar.button_for("a").button_pressed, "and it is the selected one")
	bar.free()


func test_an_empty_table_says_so_instead_of_showing_a_blank_box() -> void:
	var empty := FcUiTables.table(["Season", "Wins"], [])
	assert_true(empty.get_node_or_null("EmptyNote") != null, "an empty table carries a note")
	var full := FcUiTables.table(["Season", "Wins"], [["2026", "41"]])
	assert_true(full.get_node_or_null("EmptyNote") == null, "a table with rows does not")
	empty.free()
	full.free()


func test_a_short_button_is_as_wide_as_a_finger_on_touch() -> void:
	FcUiTokens.touch_mode = true
	var b := FcButton.make("X")
	b._refresh()
	assert_true(b.custom_minimum_size.x >= FcUiTokens.TOUCH_TARGET and b.custom_minimum_size.y >= FcUiTokens.TOUCH_TARGET, "44 x 44 at least")
	b.free()


func test_the_owner_action_row_wraps() -> void:
	# the source of the 844 px line at Large text: it must be a flow container, not a plain row
	var source := FileAccess.get_file_as_string("res://src/ui/app.gd")
	assert_true(source.contains("var actions := HFlowContainer.new()"), "the dashboard action row wraps")


func test_the_theme_has_a_focus_style_for_every_interactive_control() -> void:
	for size in 3:
		assert_true(FcUiViewportAudit.focus_styles_missing(FcUiTheme.build(size)).is_empty(), "text size %d" % size)
	FcUiTheme.build(1)


func test_a_phone_is_scaled_by_its_density_to_about_412_logical_pixels() -> void:
	assert_eq(FcLayoutProfile.phone_scale(420), 2.625, "a 420 dpi phone")
	assert_true(absf(1080.0 / FcLayoutProfile.phone_scale(420) - 412.0) < 2.0, "1080 px wide becomes about 412 logical px")
	assert_eq(FcLayoutProfile.phone_scale(0), 1.0, "an unknown density changes nothing")
	assert_eq(FcLayoutProfile.phone_scale(1000), 4.0, "and it is capped")


func test_safe_area_margins_are_converted_to_logical_pixels() -> void:
	var m := FcLayoutProfile.safe_margins(Rect2i(0, 105, 1080, 2200), Vector2i(1080, 2400), 2.625)
	assert_eq(m["top"], 40, "105 physical px at scale 2.625 is 40 logical px")
	assert_eq(m["bottom"], 37, "the bottom inset (95 px) too")
	assert_eq(FcLayoutProfile.safe_margins(Rect2i(0, 105, 1080, 2200), Vector2i(1080, 2400))["top"], 105, "scale 1 changes nothing")
