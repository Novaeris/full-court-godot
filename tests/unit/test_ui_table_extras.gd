extends FcTestCase
## The table features added for the Owner redesign: building a table from plain text (numbers sort as numbers), multi-select, compact empty
## lines, and the stacked bar and chart colours.

const SURFACES := [FcUiTokens.BG, FcUiTokens.SURFACE, FcUiTokens.SURFACE_RAISED, FcUiTokens.SURFACE_HIGH]


func test_money_and_percent_text_parses_to_numbers() -> void:
	assert_eq(FcTable.parse_number("$29.4M"), 29400000.0)
	assert_eq(FcTable.parse_number("$250K"), 250000.0)
	assert_eq(FcTable.parse_number("1,250"), 1250.0)
	assert_eq(FcTable.parse_number("40%"), 40.0)
	assert_eq(FcTable.parse_number("+3"), 3.0)
	assert_eq(FcTable.parse_number("* 12"), 12.0)
	assert_true(is_nan(FcTable.parse_number("Harbor")), "words are not numbers")
	assert_true(is_nan(FcTable.parse_number("-")), "a dash is blank")


func test_from_strings_sorts_numeric_columns_as_numbers() -> void:
	var rows := [["A", "$9.0M", "12"], ["B", "$10.0M", "9"], ["C", "$2.5M", "100"]]
	var t := FcTable.from_strings(["Team", "Payroll", "Wins"], rows)
	assert_eq(t.columns[1]["kind"], "number", "money columns are numeric")
	assert_eq(t.columns[0]["kind"], "text")
	t.sort_by("c1", false)
	assert_eq(t.ids(), [1, 0, 2], "$10.0M sorts above $9.0M (text order would not)")
	t.sort_by("c2", false)
	assert_eq(t.ids(), [2, 0, 1], "100 sorts above 12 and 9")
	t.free()


func test_from_strings_ids_are_row_indexes_and_selection_works() -> void:
	var t := FcTable.from_strings(["Name"], [["a"], ["b"], ["c"]])
	t.select_id(2)
	assert_eq(t.selected_id, 2)
	assert_eq(t.selected_row()["c0"], "c")
	t.free()


func test_an_empty_from_strings_table_is_a_quiet_line_not_a_big_empty_state() -> void:
	var t := FcTable.from_strings(["Name"], [])
	assert_true(t._empty is Label, "one muted line")
	t.free()


func test_multi_select_toggles_rows_and_keeps_the_given_order() -> void:
	var t := FcTable.from_strings(["Name"], [["a"], ["b"], ["c"], ["d"]], [], {"multi": true})
	t.select_id(3)
	t.select_id(1)
	assert_eq(t.selected_ids(), [1, 3], "in row order, not click order")
	t.select_id(3)
	assert_eq(t.selected_ids(), [1], "clicking a picked row un-picks it")
	t.clear_selection()
	assert_eq(t.selected_ids(), [])
	t.free()


func test_a_single_select_table_reports_one_id_in_a_list() -> void:
	var t := FcTable.from_strings(["Name"], [["a"], ["b"]])
	assert_eq(t.selected_ids(), [])
	t.select_id(1)
	assert_eq(t.selected_ids(), [1])
	t.free()


func test_rows_can_be_replaced_with_new_text_rows() -> void:
	var titles := ["Owner", "Vote"]
	var t := FcTable.from_strings(titles, [])
	t.set_rows(FcTable.rows_from_strings(titles, [["Ann", "Yes"], ["Bo", "No"]]))
	assert_eq(t.row_count(), 2)
	assert_eq(t.rows[1]["c0"], "Bo")
	t.free()


func test_a_stacked_bar_lists_every_part_with_amount_and_share_and_draws_only_positive_ones() -> void:
	var bar := FcStackedBar.new(func(v) -> String: return "$%dM" % int(v))
	bar.set_parts([{"label": "Tickets", "value": 60}, {"label": "Sponsors", "value": 30}, {"label": "Tax share", "value": 10}, {"label": "Nothing", "value": 0}])
	assert_eq(bar.segment_count(), 3, "the zero part is not drawn")
	var texts := bar.legend_texts()
	assert_eq(texts.size(), 4, "but it is listed")
	assert_true(str(texts[0]).begins_with("Tickets") and "(60%)" in str(texts[0]), "largest first, with its share: " + str(texts[0]))
	assert_true("$30M" in str(texts[1]))
	bar.free()


func test_a_stacked_bar_with_no_money_draws_no_segments() -> void:
	var bar := FcStackedBar.new()
	bar.set_parts([{"label": "A", "value": 0}])
	assert_eq(bar.segment_count(), 0)
	bar.free()


func test_every_chart_colour_is_visible_on_every_surface() -> void:
	for color in FcUiTokens.CHART:
		for surface in SURFACES:
			assert_true(FcUiContrast.ratio(color, surface) >= 3.0, "%s on %s" % [str(color), str(surface)])
	assert_true(FcUiTokens.CHART.size() >= 8, "enough colours for a revenue breakdown")
