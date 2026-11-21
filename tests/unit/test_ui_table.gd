extends FcTestCase
## FcTable logic that needs no screen: sorting (text, numbers, blanks, stability), selection kept across a refresh, the touch card
## stack and the empty state. Layout, virtualisation, keyboard and timing are in tests/live/test_live_table.gd.

const COLUMNS := [
	{"key": "name", "title": "Player"},
	{"key": "age", "title": "Age", "kind": "number"},
	{"key": "ovr", "title": "OVR", "kind": "rating"},
]


func _rows() -> Array:
	return [
		{"id": 1, "name": "Zed", "age": 30, "ovr": 70},
		{"id": 2, "name": "amy", "age": 22, "ovr": 80},
		{"id": 3, "name": "Bob", "age": 22, "ovr": 60},
		{"id": 4, "name": "", "age": 25, "ovr": 80},
	]


func test_text_sorts_without_regard_to_case_and_blanks_go_last() -> void:
	var t := FcTable.new(COLUMNS, _rows())
	t.sort_by("name", true)
	assert_eq(t.ids(), [2, 3, 1, 4], "amy, Bob, Zed, then the blank")
	t.sort_by("name", false)
	assert_eq(t.ids(), [1, 3, 2, 4], "descending reverses the names but blanks stay last")
	t.free()


func test_numbers_sort_as_numbers_and_ties_keep_their_order() -> void:
	var t := FcTable.new(COLUMNS, _rows())
	t.sort_by("age", true)
	assert_eq(t.ids(), [2, 3, 4, 1], "22, 22 (original order), 25, 30")
	t.sort_by("ovr", false)
	assert_eq(t.ids(), [2, 4, 1, 3], "80, 80 (original order), 70, 60")
	t.free()


func test_a_number_column_starts_high_to_low_and_a_second_click_flips_it() -> void:
	var t := FcTable.new(COLUMNS, _rows())
	t.sort_by("ovr")
	assert_true(not t.sort_ascending, "numbers start high to low")
	t.sort_by("ovr")
	assert_true(t.sort_ascending, "the same header again flips the direction")
	t.sort_by("name")
	assert_true(t.sort_ascending, "text starts A to Z")
	t.free()


func test_sorting_by_an_unknown_column_changes_nothing() -> void:
	var t := FcTable.new(COLUMNS, _rows())
	t.sort_by("nope")
	assert_eq(t.ids(), [1, 2, 3, 4])
	t.free()


func test_a_custom_sort_value_is_used() -> void:
	var cols := [{"key": "name", "title": "Player", "sort_value": func(r: Dictionary): return -int(r["id"])}]
	var t := FcTable.new(cols, _rows(), {"sort_key": "name", "sort_ascending": true})
	assert_eq(t.ids(), [4, 3, 2, 1])
	t.free()


func test_selection_survives_a_refresh_and_clears_when_the_row_is_gone() -> void:
	var t := FcTable.new(COLUMNS, _rows())
	var picked: Array = []
	t.row_selected.connect(func(id) -> void: picked.append(id))
	t.select_id(3)
	assert_eq(t.selected_id, 3)
	assert_eq(picked, [3])
	assert_eq(t.selected_row()["name"], "Bob")
	t.set_rows(_rows().slice(1))
	assert_eq(t.selected_id, 3, "the row is still there")
	t.set_rows([{"id": 9, "name": "New", "age": 20, "ovr": 50}])
	assert_eq(t.selected_id, null, "the selected row left the list")
	t.free()


func test_selecting_an_unknown_id_clears_the_selection() -> void:
	var t := FcTable.new(COLUMNS, _rows())
	t.select_id(1)
	t.select_id(99)
	assert_eq(t.selected_id, null)
	t.free()


func test_cell_text_uses_the_format() -> void:
	var col := {"key": "age", "format": func(v) -> String: return "%d yrs" % int(v)}
	assert_eq(FcTable.cell_text({"age": 31}, col), "31 yrs")
	assert_eq(FcTable.cell_text({}, {"key": "x"}), "", "a missing value is blank")


func test_build_returns_an_empty_state_the_card_stack_or_the_table() -> void:
	var empty := FcTable.build(COLUMNS, [], {"empty_title": "No players"})
	assert_true(empty is FcEmptyState, "no rows: an empty state")
	assert_eq((empty as FcEmptyState).title_label.text, "No players")
	var cards := FcTable.build(COLUMNS, _rows(), {"compact": true})
	assert_true(cards is VBoxContainer and not (cards is FcTable), "compact: a card stack")
	assert_eq(cards.get_child_count(), 4, "one card per row")
	var table := FcTable.build(COLUMNS, _rows(), {"compact": false})
	assert_true(table is FcTable, "desktop: the table")
	for n in [empty, cards, table]:
		n.free()


func test_the_row_pool_never_exceeds_a_screenful_even_for_a_thousand_rows() -> void:
	var rows: Array = []
	for i in 1000:
		rows.append({"id": i, "name": "P%d" % i, "age": 20 + i % 15, "ovr": i % 99})
	var t := FcTable.new(COLUMNS, rows, {"max_rows": 12})
	assert_true(t.pool_size() > 0 and t.pool_size() <= 16, "pool is %d for 1000 rows" % t.pool_size())
	assert_eq(t.row_count(), 1000)
	t.free()
