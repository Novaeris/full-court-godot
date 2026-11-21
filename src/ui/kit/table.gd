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
var _empty: Control
var _pool: Array = []
var _col_x: Array = []
var _col_w: Array = []
var _layout_width: float = 0.0
var _pending_update := false
## Multi-select mode (option "multi"): clicking a row toggles it and any number of rows can be picked (trades, protect lists).
var multi: bool = false
var _picked: Dictionary = {}


func _init(column_defs: Array = [], row_data: Array = [], options: Dictionary = {}) -> void:
	_options = options
	multi = bool(options.get("multi", false))
	columns = column_defs
	row_height = int(options.get("row_height", maxi(FcUiTokens.min_target(), roundi(34 * FcUiTokens.text_scale))))
	focus_mode = Control.FOCUS_ALL
	add_theme_constant_override("separation", 0)
	_header = FcTableRow.new(true)
	_header.custom_minimum_size.y = row_height
	_header.clip_contents = true
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
	if bool(options.get("compact_empty", false)):
		var note := FcUiTables.label(str(options.get("empty_title", "Nothing to show yet.")), FcUiTokens.TYPE_SMALL)
		note.theme_type_variation = "MutedLabel"
		note.custom_minimum_size.y = row_height
		_empty = note
	else:
		var state := FcEmptyState.new(str(options.get("empty_title", "Nothing here yet")), str(options.get("empty_text", "")))
		state.body_label.custom_minimum_size.x = 0   # an empty table must not widen its screen (the empty state's usual 260 px is for full-page use)
		_empty = state
	_empty.visible = false
	add_child(_empty)
	_build_header()
	_body.gui_input.connect(_on_body_input)
	_body.mouse_exited.connect(_on_mouse_exited)
	_body.resized.connect(_on_resized)
	_scroll.resized.connect(_update_window)   # the number of rows in view depends on the height, which settles after the width
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)
	resized.connect(_relayout)   # an empty table has no visible body, so the header is laid out from the table's own width
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


## A table from plain text, the way the older tabs build their lists: `titles` (strings), `text_rows` (arrays of strings or values), `widths`
## (0 = flexible). Each row's id is its index. Columns whose every filled cell looks like a number sort as numbers ("$29.4M", "12.5", "40%"),
## and align right. Use it to move a plain list onto the table without changing its data; the selection is `selected_id` (the row index) or,
## with {"multi": true}, `selected_ids()`.
static func from_strings(titles: Array, text_rows: Array, widths: Array = [], options: Dictionary = {}) -> FcTable:
	var column_defs: Array = []
	for i in titles.size():
		var numeric := _looks_numeric(i, text_rows)
		var key := "c%d" % i
		var def := {"key": key, "title": str(titles[i]), "kind": "number" if numeric else "text"}
		if i < widths.size() and int(widths[i]) > 0:
			def["width"] = int(widths[i])
		if numeric:
			def["sort_value"] = func(r: Dictionary): return parse_number(str(r.get(key, "")))
		column_defs.append(def)
	var row_data := rows_from_strings(titles, text_rows)
	var opts := options.duplicate()
	if not opts.has("compact_empty"):
		opts["compact_empty"] = true
	if not opts.has("max_rows"):
		opts["max_rows"] = clampi(text_rows.size(), 1, 12)
	var table := FcTable.new(column_defs, row_data, opts)
	table.custom_minimum_size.y = table.row_height * (mini(maxi(text_rows.size(), 1), int(opts["max_rows"])) + 1) + 2
	return table


## The row dictionaries of a from_strings table for new text rows (for set_rows when the list changes while the screen is open).
static func rows_from_strings(titles: Array, text_rows: Array) -> Array:
	var row_data: Array = []
	for r in text_rows.size():
		var d := {"id": r}
		for i in titles.size():
			d["c%d" % i] = str(text_rows[r][i]) if i < text_rows[r].size() else ""
		row_data.append(d)
	return row_data


## The number inside a formatted cell ("$29.4M" 29400000, "1,250" 1250, "40%" 40, "+3" 3); NAN when there is none.
static func parse_number(text: String) -> float:
	var t := text.replace("$", "").replace(",", "").replace("%", "").replace("*", "").replace("+", "").strip_edges()
	if t == "" or t == "-":
		return NAN
	var factor := 1.0
	var last := t.substr(t.length() - 1).to_upper()
	if last == "M" or last == "K" or last == "B":
		factor = {"K": 1000.0, "M": 1000000.0, "B": 1000000000.0}[last]
		t = t.substr(0, t.length() - 1)
	return float(t) * factor if t.is_valid_float() else NAN


static func _looks_numeric(column: int, text_rows: Array) -> bool:
	var seen := false
	for row in text_rows:
		if column >= row.size():
			continue
		var cell := str(row[column]).strip_edges()
		if cell == "" or cell == "-":
			continue
		seen = true
		if is_nan(parse_number(cell)):
			return false
	return seen


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


## The picked ids in the order the rows were given (multi-select mode; a single selection gives a list of one).
func selected_ids() -> Array:
	if not multi:
		return [] if selected_id == null else [selected_id]
	var out: Array = []
	for r in rows:
		if _picked.has(r.get("id")):
			out.append(r.get("id"))
	return out


func clear_selection() -> void:
	_picked.clear()
	selected_id = null
	_refresh_looks()


func select_id(id, emit: bool = true) -> void:
	var i := _index_of_id(id)
	if i < 0:
		selected_id = null
		_refresh_looks()
		return
	if multi:
		if _picked.has(id):
			_picked.erase(id)
		else:
			_picked[id] = true
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
	return v == null or (v is String and v == "") or (v is float and is_nan(v))


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
		_style_header_button(b)
		b.disabled = not bool(c.get("sortable", true))
		b.tooltip_text = "Sort by %s" % str(c.get("title", "")) if not b.disabled else ""
		var key := str(c.get("key", ""))
		b.pressed.connect(sort_by.bind(key))
		_header.add_child(b)
		_header.cells.append(b)


## Header buttons: flat, with small side padding so short titles in narrow columns ("MPG", "Ovr") are not clipped.
static func _style_header_button(b: Button) -> void:
	for state in ["normal", "disabled", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, _header_box(FcUiTokens.TRANSPARENT))
	b.add_theme_stylebox_override("hover", _header_box(FcUiTokens.SURFACE_HIGH))
	b.add_theme_stylebox_override("focus", b.get_theme_stylebox("focus", "Button"))
	b.add_theme_color_override("font_color", FcUiTokens.TEXT_MUTED)
	b.add_theme_color_override("font_hover_color", FcUiTokens.TEXT)
	b.add_theme_color_override("font_disabled_color", FcUiTokens.TEXT_MUTED)


static func _header_box(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	return box


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
	_relayout()


func _relayout() -> void:
	var total := _body.size.x if _scroll.visible and _body.size.x > 0.0 else size.x
	if total <= 0.0 or absf(total - _layout_width) < 0.5:
		return
	_layout_width = total
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
	var widths: Array = []
	var sum := 0.0
	for i in columns.size():
		var w := float(columns[i].get("width", 0))
		w = w if w > 0.0 else share
		w = maxf(w, _title_width(i))   # a column is never narrower than its own title (with the sort arrow)
		widths.append(w)
		sum += w
	var squeeze := total / sum if sum > total and total > 0.0 else 1.0   # in a narrow container every column gives up the same share
	var x := 0.0
	for w in widths:
		_col_x.append(x)
		_col_w.append(float(w) * squeeze)
		x += float(w) * squeeze


## The width a column's title needs (text, sort arrow and the button padding).
func _title_width(i: int) -> float:
	if _header == null or i >= _header.cells.size():
		return 0.0
	var b: Button = _header.cells[i]
	var title := str(columns[i].get("title", ""))
	if title == "":
		return 0.0
	var font := b.get_theme_font("font")
	return font.get_string_size(title + "  ↓", HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x + 18.0


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
		s.x = w if bool(columns[i].get("fill", false)) else minf(s.x, w)
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
		var is_picked: bool = _picked.has(id) if multi else (selected_id != null and id == selected_id)
		row.set_look(row.display_index % 2 == 1, is_picked, row.display_index == _hover, focused)


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
	if multi and event.is_action("ui_select") and selected_id != null:
		accept_event()
		select_id(selected_id)   # Space toggles the row the cursor is on
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
	if multi:
		selected_id = rows[_order[target]].get("id")   # moving the cursor does not toggle; Space does
		_ensure_visible(target)
		_refresh_looks()
		return
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
