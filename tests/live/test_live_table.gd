extends FcLiveTestCase
## FcTable in a real scene: layout, virtualised rows while scrolling, keyboard navigation, mouse selection, header clicks, touch fallback
## and timing for 400 and 1,000 rows (the Phase B prototype gate, docs/VISUAL_IDENTITY_PLAN.md 5.1).

const COLUMNS := [
	{"key": "name", "title": "Player"},
	{"key": "pos", "title": "Pos", "width": 56},
	{"key": "age", "title": "Age", "width": 56, "kind": "number"},
	{"key": "ovr", "title": "OVR", "width": 72, "kind": "rating", "align": "center"},
	{"key": "used", "title": "Contract", "width": 100, "kind": "bar"},
]


func _rows(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"id": i + 1, "name": "Player number %d with a rather long name" % i, "pos": ["PG", "SG", "SF", "PF", "C"][i % 5], "age": 19 + (i * 7) % 18, "ovr": 40 + (i * 37) % 59, "used": (i * 13) % 100})
	return out


func _table(n: int, w: int = 800, h: int = 400) -> FcTable:
	var t := FcTable.new(COLUMNS, _rows(n), {"row_height": 40, "max_rows": 8})
	t.size = Vector2(w, h)
	host.add_child(t)
	return t


func _key(action: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	return e


func test_only_a_screenful_of_rows_exists_for_1000_rows() -> void:
	var t := _table(1000)
	await frames(3)
	assert_true(t.pool_size() <= 14, "pool is %d" % t.pool_size())
	var visible := 0
	for r in t._pool:
		if r.visible:
			visible += 1
	assert_true(visible >= 8, "enough rows to fill the view (%d)" % visible)


func test_scrolling_rebinds_rows_and_shows_the_right_ones() -> void:
	var t := _table(400)
	await frames(3)
	t._scroll.scroll_vertical = 40 * 200
	await frames(2)
	var shown: Array = []
	for r in t._pool:
		if r.visible:
			shown.append(r.display_index)
	shown.sort()
	assert_true(shown.size() > 0 and shown[0] >= 198 and shown[-1] <= 215, "rows around 200 are bound: %s" % str(shown))
	var first_row: FcTableRow = null
	for r in t._pool:
		if r.visible and r.display_index == shown[0]:
			first_row = r
	assert_true(str((first_row.cells[0] as Label).text).contains(str(shown[0])), "the label follows the data")
	assert_eq(int(first_row.position.y), shown[0] * 40, "the row sits at its place in the list")


func test_keyboard_moves_the_selection_and_scrolls_it_into_view() -> void:
	var t := _table(400)
	await frames(3)
	var activated: Array = []
	t.row_activated.connect(func(id) -> void: activated.append(id))
	t.select_id(1)
	for i in 30:
		t._gui_input(_key("ui_down"))
	assert_eq(t.selected_id, 31)
	assert_true(t._scroll.scroll_vertical > 0, "the view followed the selection")
	t._gui_input(_key("ui_end"))
	assert_eq(t.selected_id, 400)
	t._gui_input(_key("ui_home"))
	assert_eq(t.selected_id, 1)
	t._gui_input(_key("ui_page_down"))
	assert_true(int(t.selected_id) > 3, "page down jumps several rows")
	t._gui_input(_key("ui_up"))
	t._gui_input(_key("ui_accept"))
	assert_eq(activated.size(), 1, "Enter activates the selected row")


func test_a_click_selects_and_a_double_click_activates() -> void:
	var t := _table(50)
	await frames(3)
	var picked: Array = []
	var activated: Array = []
	t.row_selected.connect(func(id) -> void: picked.append(id))
	t.row_activated.connect(func(id) -> void: activated.append(id))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(100, 40 * 3 + 5)
	t._on_body_input(click)
	assert_eq(picked, [4], "the fourth row")
	click.double_click = true
	t._on_body_input(click)
	assert_eq(activated, [4])


func test_a_header_click_sorts_and_marks_the_column() -> void:
	var t := _table(60)
	await frames(2)
	var sorted: Array = []
	t.sort_changed.connect(func(key: String, asc: bool) -> void: sorted.append([key, asc]))
	(t._header.cells[3] as Button).pressed.emit()
	await frames(1)
	assert_eq(sorted, [["ovr", false]], "ratings start high to low")
	assert_true((t._header.cells[3] as Button).text.contains("↓"), "the header shows the direction")
	var top: Dictionary = t.rows[t._order[0]]
	for r in t.rows:
		assert_true(int(top["ovr"]) >= int(r["ovr"]), "the top row has the highest rating")


func test_columns_fill_the_width_and_long_text_is_trimmed() -> void:
	var t := _table(20, 700)
	await frames(3)
	var total := 0.0
	for w in t._col_w:
		total += float(w)
	assert_true(absf(total - t._body.size.x) < 1.0, "columns add up to the body width (%f vs %f)" % [total, t._body.size.x])
	var label: Label = null
	for r in t._pool:
		if r.visible:
			label = r.cells[0]
			break
	assert_eq(label.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "long names end in an ellipsis")
	assert_true(label.size.x <= float(t._col_w[0]), "the label stays inside its column")


func test_an_empty_table_shows_its_message_and_no_rows() -> void:
	var t := FcTable.new(COLUMNS, [], {"empty_title": "No players"})
	host.add_child(t)
	await frames(2)
	assert_true(t._empty.visible and not t._scroll.visible, "the empty state replaces the body")
	assert_eq(t.pool_size(), 0)


func test_focus_shows_on_the_selected_row() -> void:
	var t := _table(20)
	await frames(2)
	t.select_id(2)
	t.grab_focus()
	await frames(1)
	var shown := false
	for r in t._pool:
		if r.visible and r.is_selected:
			shown = r.show_focus
	assert_true(shown, "the selected row draws a focus outline while the table has focus")


func test_timing_for_400_and_1000_rows() -> void:
	for n in [400, 1000]:
		var t0 := Time.get_ticks_usec()
		var t := _table(n, 800, 520)
		var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
		await frames(2)
		var s0 := Time.get_ticks_usec()
		var steps := 300
		for i in steps:
			t._scroll.scroll_vertical = (i * 97) % (n * 40 - 400)
			t._update_window()
		var step_ms := (Time.get_ticks_usec() - s0) / 1000.0 / steps
		var s1 := Time.get_ticks_usec()
		t.sort_by("ovr")
		var sort_ms := (Time.get_ticks_usec() - s1) / 1000.0
		print("PERF table %d rows: build %.1f ms, scroll step %.2f ms, sort %.1f ms, %d row controls" % [n, build_ms, step_ms, sort_ms, t.pool_size()])
		assert_true(build_ms < 150.0, "build of %d rows took %.1f ms" % [n, build_ms])
		assert_true(step_ms < 4.0, "a scroll step took %.2f ms (60 fps needs under 16)" % step_ms)
		assert_true(sort_ms < 60.0, "sorting %d rows took %.1f ms" % [n, sort_ms])
		t.queue_free()
		await frames(1)


func test_the_touch_layout_uses_cards_not_a_table() -> void:
	FcUiTokens.touch_mode = true
	var c := FcTable.build(COLUMNS, _rows(5), {})
	host.add_child(c)
	await frames(2)
	assert_true(not (c is FcTable), "compact layouts get the card stack")
	assert_eq(c.get_child_count(), 5)
