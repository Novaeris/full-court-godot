class_name FcTable
extends VBoxContainer
## The kit's data table: sortable column headers, single-row selection, keyboard navigation, text that is ellipsized with a tooltip,
## and cells that can hold more than text (a rating badge, a mini bar, any control such as a player portrait or a team crest).
## It replaces the plain Godot Tree for Owner and Career lists (docs/VISUAL_IDENTITY_PLAN.md, 5.1) and is VIRTUALISED: only the
## rows in view exist as controls (a pool of about 20, rebound while scrolling), so 1,000 rows cost the same as 20.
##
## Columns are dictionaries: key (looked up in each row), title, width (px; 0 or missing = flexible), kind ("text", "number",
## "rating", "bar", "custom"), align ("left", "right", "center"; numbers default right), sortable (default true), format
## (Callable(value) -> String), sort_value (Callable(row) -> Variant), max and tone (bars), make (Callable() -> Control) and
## bind (Callable(cell, row)) for custom cells.
## Rows are dictionaries with an "id" (int or String, unique) plus a value for every column key.
## options: row_height, max_rows (height of the table before it scrolls, default 12), sort_key, sort_ascending, empty_title, empty_text.
## FcTable.build() is the one call screens make: it returns the touch card stack on compact layouts and an FcEmptyState for no rows.

signal row_selected(id)
signal row_activated(id)
signal sort_changed(key: String, ascending: bool)

var columns: Array = []
var rows: Array = []
var selected_id = null
var sort_key: String = ""
var sort_ascending: bool = true
var row_height: int = 34

var _options: Dictionary = {}
var _order: Array = []
var _hover: int = -1
var _header: FcTableRow
var _scroll: ScrollContainer
var _body: Control
var _empty: FcEmptyState
var _pool: Array = []
var _col_x: Array = []
var _col_w: Array = []
var _layout_width: float = 0.0
var _pending_update := false


func _init(column_defs: Array = [], row_data: Array = [], options: Dictionary = {}) -> void:
	_options = options
	columns = column_defs
	row_height = int(options.get("row_height", maxi(FcUiTokens.min_target(), roundi(34 * FcUiTokens.text_scale))))
	focus_mode = Control.FOCUS_ALL
	add_theme_constant_override("separation", 0)
	_header = FcTableRow.new(true)
	_header.custom_minimum_size.y = row_height
	add_child(_header)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_body = Control.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.mouse_filter = Control.MOUSE_FILTER_PASS
	_body.clip_contents = true
	_scroll.add_child(_body)
	_empty = FcEmptyState.new(str(options.get("empty_title", "Nothing here yet")), str(options.get("empty_text", "")))
	_empty.visible = false
	add_child(_empty)
	_build_header()
	_body.gui_input.connect(_on_body_input)
	_body.mouse_exited.connect(_on_mouse_exited)
	_body.resized.connect(_on_resized)
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)
	focus_entered.connect(_refresh_looks)
	focus_exited.connect(_refresh_looks)
	if options.has("sort_key"):
		sort_key = str(options["sort_key"])
		sort_ascending = bool(options.get("sort_ascending", true))
	set_rows(row_data)


## The call screens use: the table, or the card stack on compact (touch) layouts, or an empty state when there is nothing to show.
static func build(column_defs: Array, row_data: Array, options: Dictionary = {}) -> Control:
	if row_data.is_empty():
		return FcEmptyState.new(str(options.get("empty_title", "Nothing here yet")), str(options.get("empty_text", "")))
	if bool(options.get("compact", FcUiTokens.touch_mode)):
		return _card_stack(column_defs, row_data)
	var table := FcTable.new(column_defs, row_data, options)
	table.custom_minimum_size.y = table.row_height * (mini(row_data.size(), int(options.get("max_rows", 12))) + 1) + 2
	return table


# --- data ------------------------------------------------------------------------------------------------------------

## Replaces the rows (keeps the sort and, when its row still exists, the selection).
func set_rows(row_data: Array) -> void:
	rows = row_data
	if selected_id != null and _index_of_id(selected_id) < 0:
		selected_id = null
	_resort()


## Row ids in the order shown (tests and screens read it).
func ids() -> Array:
	var out: Array = []
	for i in _order:
		out.append(rows[i].get("id"))
	return out


func row_count() -> int:
	return rows.size()


func selected_row() -> Dictionary:
	var i := _index_of_id(selected_id)
	return rows[i] if i >= 0 else {}


## How many row controls exist (stays small however many rows there are).
func pool_size() -> int:
	return _pool.size()


## Sorts by a column. `ascending` null picks the natural first direction: text A to Z, numbers high to low.
func sort_by(key: String, ascending = null) -> void:
	var col := _column(key)
	if col.is_empty():
		return
	if ascending == null:
		ascending = (not sort_ascending) if sort_key == key else _kind(col) == "text"
	sort_key = key
	sort_ascending = bool(ascending)
	_resort()
	sort_changed.emit(sort_key, sort_ascending)


func select_id(id, emit: bool = true) -> void:
	var i := _index_of_id(id)
	if i < 0:
		selected_id = null
		_refresh_looks()
		return
	selected_id = id
	var pos := _order.find(i)
	_ensure_visible(pos)
	_refresh_looks()
	if emit:
		row_selected.emit(id)


# --- sorting and lookup ----------------------------------------------------------------------------------------------

func _resort() -> void:
	_order = range(rows.size())
	var col := _column(sort_key)
	if not col.is_empty() and rows.size() > 1:
		var values: Array = []
		for r in rows:
			values.append(_sort_value(r, col))
		var asc := sort_ascending
		# the original position is the tie-break, so equal values keep their order (sort_custom alone is not stable)
		_order.sort_custom(func(a: int, b: int) -> bool:
			var a_blank := _is_blank(values[a])
			var b_blank := _is_blank(values[b])
			if a_blank or b_blank:
				return (not a_blank) if a_blank != b_blank else a < b   # blanks last in both directions
			var c := _compare(values[a], values[b])
			if c == 0:
				return a < b
			return c < 0 if asc else c > 0)
	_body.custom_minimum_size.y = _order.size() * row_height
	_empty.visible = rows.is_empty()
	_scroll.visible = not rows.is_empty()
	_update_header_marks()
	for r in _pool:
		r.display_index = -1
	_update_window()


## -1, 0 or 1. Numbers compare as numbers, everything else as text without regard to case; blanks sort last.
static func _is_blank(v) -> bool:
	return v == null or (v is String and v == "")


static func _compare(a, b) -> int:
	var a_blank := _is_blank(a)
	var b_blank := _is_blank(b)
	if a_blank or b_blank:
		return 0 if a_blank and b_blank else (1 if a_blank else -1)
	if (a is int or a is float) and (b is int or b is float):
		return -1 if a < b else (1 if a > b else 0)
	return str(a).naturalnocasecmp_to(str(b))


func _sort_value(row: Dictionary, col: Dictionary):
	var f = col.get("sort_value")
	if f is Callable and (f as Callable).is_valid():
		return (f as Callable).call(row)
	return row.get(str(col["key"]))


func _index_of_id(id) -> int:
	if id == null:
		return -1
	for i in rows.size():
		if rows[i].get("id") == id:
			return i
	return -1


func _column(key: String) -> Dictionary:
	for c in columns:
		if str(c.get("key", "")) == key:
			return c
	return {}


func _kind(col: Dictionary) -> String:
	return str(col.get("kind", "text"))


func _align(col: Dictionary) -> String:
	var kind := _kind(col)
	return str(col.get("align", "right" if kind == "number" else "left"))


# --- header and layout -----------------------------------------------------------------------------------------------

func _build_header() -> void:
	for c in columns:
		var b := Button.new()
		b.theme_type_variation = "GhostButton"
		b.text = str(c.get("title", ""))
		b.clip_text = true
		b.focus_mode = Control.FOCUS_ALL
		b.alignment = _button_alignment(_align(c))
		b.disabled = not bool(c.get("sortable", true))
		b.tooltip_text = "Sort by %s" % str(c.get("title", "")) if not b.disabled else ""
		var key := str(c.get("key", ""))
		b.pressed.connect(sort_by.bind(key))
		_header.add_child(b)
		_header.cells.append(b)


static func _button_alignment(align: String) -> HorizontalAlignment:
	match align:
		"right":
			return HORIZONTAL_ALIGNMENT_RIGHT
		"center":
			return HORIZONTAL_ALIGNMENT_CENTER
	return HORIZONTAL_ALIGNMENT_LEFT


func _update_header_marks() -> void:
	for i in columns.size():
		var b: Button = _header.cells[i]
		var key := str(columns[i].get("key", ""))
		b.text = str(columns[i].get("title", "")) + (("  ↑" if sort_ascending else "  ↓") if key == sort_key else "")


func _on_mouse_exited() -> void:
	_set_hover(-1)


func _on_scrolled(_value: float) -> void:
	_update_window()


func _on_resized() -> void:
	if absf(_body.size.x - _layout_width) < 0.5:
		return
	_layout_width = _body.size.x
	_compute_columns(_layout_width)
	_place_header()
	for r in _pool:
		r.display_index = -1
	_update_window()


## Fixed columns keep their width; the rest share what is left (never narrower than 48 px).
func _compute_columns(total: float) -> void:
	_col_x = []
	_col_w = []
	var fixed := 0.0
	var flex := 0
	for c in columns:
		var w := float(c.get("width", 0))
		if w > 0.0:
			fixed += w
		else:
			flex += 1
	var share := maxf(48.0, (total - fixed) / float(maxi(flex, 1)))
	var x := 0.0
	for c in columns:
		var w := float(c.get("width", 0))
		w = w if w > 0.0 else share
		_col_x.append(x)
		_col_w.append(w)
		x += w


func _place_header() -> void:
	_header.size.x = _layout_width + _scroll_bar_width()
	for i in columns.size():
		var b: Control = _header.cells[i]
		b.position = Vector2(_col_x[i], 0)
		b.size = Vector2(_col_w[i], row_height)


func _scroll_bar_width() -> float:
	return _scroll.size.x - _body.size.x if _scroll.size.x > _body.size.x else 0.0


# --- virtual rows ----------------------------------------------------------------------------------------------------

func _update_window() -> void:
	var n := _order.size()
	if n == 0:
		for r in _pool:
			r.visible = false
			r.display_index = -1
		return
	if _col_x.is_empty():
		_compute_columns(maxf(_body.size.x, float(_options.get("fallback_width", 640))))
	var view_h := _scroll.size.y if _scroll.size.y > 0.0 else float(row_height * int(_options.get("max_rows", 12)))
	var first := clampi(int(_scroll.scroll_vertical / row_height), 0, n - 1)
	var need := mini(n, int(ceil(view_h / float(row_height))) + 2)
	while _pool.size() < need:
		var row := FcTableRow.new()
		for c in columns:
			var cell := _make_cell(c)
			row.add_child(cell)
			row.cells.append(cell)
		_body.add_child(row)
		_pool.append(row)
	var p := _pool.size()
	for row in _pool:
		if row.display_index >= 0 and (row.display_index < first or row.display_index >= first + need):
			row.visible = false
			row.display_index = -1
	for k in range(first, mini(n, first + need)):
		var row: FcTableRow = _pool[k % p]
		if row.display_index != k:
			row.display_index = k
			_bind_row(row, rows[_order[k]])
			_place_row(row, k)
		row.visible = true
	_refresh_looks()


func _make_cell(col: Dictionary) -> Control:
	match _kind(col):
		"rating":
			return FcRatingBadge.new(0, FcRatingBadge.Size.SMALL)
		"bar":
			return FcMiniBar.new()
		"custom":
			var f = col.get("make")
			if f is Callable and (f as Callable).is_valid():
				var made = (f as Callable).call()
				if made is Control:
					return made
	var label := Label.new()
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _kind(col) == "number":
		label.theme_type_variation = "NumericLabel"
	return label


func _bind_row(row: FcTableRow, data: Dictionary) -> void:
	for i in columns.size():
		var col: Dictionary = columns[i]
		var cell: Control = row.cells[i]
		var key := str(col["key"])
		match _kind(col):
			"rating":
				(cell as FcRatingBadge).set_rating(int(data.get(key, 0)))
			"bar":
				var tone = col.get("tone")
				var color: Color = (tone as Callable).call(data) if tone is Callable and (tone as Callable).is_valid() else FcUiTokens.INFO
				(cell as FcMiniBar).set_ratio(float(data.get(key, 0)) / maxf(float(col.get("max", 100)), 0.0001), color)
			"custom":
				var b = col.get("bind")
				if b is Callable and (b as Callable).is_valid():
					(b as Callable).call(cell, data)
			_:
				var label := cell as Label
				label.text = cell_text(data, col)
				label.horizontal_alignment = _button_alignment(_align(col))


## The text a cell shows (also used by the touch card stack and by tooltips).
static func cell_text(data: Dictionary, col: Dictionary) -> String:
	var value = data.get(str(col.get("key", "")), "")
	var f = col.get("format")
	if f is Callable and (f as Callable).is_valid():
		return str((f as Callable).call(value))
	return str(value)


func _place_row(row: FcTableRow, display_index: int) -> void:
	row.position = Vector2(0, display_index * row_height)
	row.size = Vector2(_layout_width if _layout_width > 0.0 else float(_col_x[-1] + _col_w[-1]), row_height)
	var pad := 8.0
	for i in columns.size():
		var cell: Control = row.cells[i]
		var w := float(_col_w[i]) - pad * 2.0
		if cell is Label:
			cell.position = Vector2(_col_x[i] + pad, 0)
			cell.size = Vector2(w, row_height)
			continue
		var s := cell.get_combined_minimum_size()
		s.x = minf(s.x, w)
		cell.size = s
		var x := float(_col_x[i]) + pad
		match _align(columns[i]):
			"right":
				x = float(_col_x[i]) + float(_col_w[i]) - pad - s.x
			"center":
				x = float(_col_x[i]) + (float(_col_w[i]) - s.x) / 2.0
		if _kind(columns[i]) == "bar":
			cell.size.x = w
			x = float(_col_x[i]) + pad
		cell.position = Vector2(x, (row_height - s.y) / 2.0)


func _refresh_looks() -> void:
	var focused := has_focus()
	for row in _pool:
		if row.display_index < 0:
			continue
		var id = rows[_order[row.display_index]].get("id")
		row.set_look(row.display_index % 2 == 1, selected_id != null and id == selected_id, row.display_index == _hover, focused)


# --- mouse and keyboard ----------------------------------------------------------------------------------------------

func _on_body_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var idx := _index_at(event.position.y)
		_set_hover(idx)
		_body.tooltip_text = _tooltip_at(event.position) if idx >= 0 else ""
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var idx := _index_at(event.position.y)
		if idx < 0:
			return
		grab_focus()
		var id = rows[_order[idx]].get("id")
		select_id(id)
		if event.double_click:
			row_activated.emit(id)


func _index_at(y: float) -> int:
	var i := int(y / row_height)
	return i if i >= 0 and i < _order.size() else -1


func _tooltip_at(pos: Vector2) -> String:
	var idx := _index_at(pos.y)
	for i in columns.size():
		if pos.x >= float(_col_x[i]) and pos.x < float(_col_x[i]) + float(_col_w[i]):
			var kind := _kind(columns[i])
			return cell_text(rows[_order[idx]], columns[i]) if kind == "text" or kind == "number" else ""
	return ""


func _set_hover(idx: int) -> void:
	if idx != _hover:
		_hover = idx
		_refresh_looks()


func _gui_input(event: InputEvent) -> void:
	if not event.is_pressed() or _order.is_empty():
		return
	var cur := _order.find(_index_of_id(selected_id))
	var page := maxi(1, int(_scroll.size.y / row_height) - 1)
	var target := cur
	if event.is_action("ui_down"):
		target = cur + 1
	elif event.is_action("ui_up"):
		target = cur - 1
	elif event.is_action("ui_page_down"):
		target = cur + page
	elif event.is_action("ui_page_up"):
		target = cur - page
	elif event.is_action("ui_home"):
		target = 0
	elif event.is_action("ui_end"):
		target = _order.size() - 1
	elif event.is_action("ui_accept"):
		if selected_id != null:
			row_activated.emit(selected_id)
			accept_event()
		return
	else:
		return
	accept_event()
	target = clampi(target, 0, _order.size() - 1)
	select_id(rows[_order[target]].get("id"))


func _ensure_visible(pos: int) -> void:
	if pos < 0:
		return
	var top := pos * row_height
	var view_h := int(_scroll.size.y)
	if top < _scroll.scroll_vertical:
		_scroll.scroll_vertical = top
	elif top + row_height > _scroll.scroll_vertical + view_h and view_h > 0:
		_scroll.scroll_vertical = top + row_height - view_h
	_update_window()


# --- touch layout ----------------------------------------------------------------------------------------------------

static func _card_stack(column_defs: Array, row_data: Array) -> Control:
	# the title is the first text column; picture columns (custom cells, no title) have no text to show on a card
	var shown: Array = column_defs.filter(func(c: Dictionary) -> bool: return str(c.get("kind", "text")) != "custom" and str(c.get("title", "")) != "")
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	for data in row_data:
		var card := FcPanel.new("", FcPanel.Variant.FLAT)
		if not shown.is_empty():
			card.add(FcUiTables.label(cell_text(data, shown[0]), FcUiTokens.TYPE_H3, true))
		for i in range(1, shown.size()):
			card.add(FcStatLine.make(str(shown[i].get("title", "")), cell_text(data, shown[i])))
		stack.add_child(card)
	return stack
