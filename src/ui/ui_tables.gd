class_name FcUiTables
extends RefCounted
## Small helpers for building the plain data tables the screens are made of.


## A read-only table. `columns` are titles; `rows` are arrays of strings (or values).
## `widths` are optional minimum column widths in pixels. Returns the Tree.
static func table(columns: Array, rows: Array, widths: Array = []) -> Tree:
	var tree := Tree.new()
	tree.columns = columns.size()
	tree.column_titles_visible = true
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in columns.size():
		tree.set_column_title(i, str(columns[i]))
		# a width of 0 (or no width) makes the column flexible; otherwise it is fixed
		var fixed := i < widths.size() and int(widths[i]) > 0
		tree.set_column_expand(i, not fixed)
		if fixed:
			tree.set_column_custom_minimum_width(i, int(widths[i]))
		if _is_numeric_column(i, rows):
			tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_RIGHT)
		else:
			tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
	var root := tree.create_item()
	if rows.is_empty():
		tree.add_child(_empty_note())
	for row in rows:
		var item := tree.create_item(root)
		for i in columns.size():
			item.set_text(i, str(row[i]) if i < row.size() else "")
			if _is_numeric_column(i, rows):
				item.set_text_alignment(i, HORIZONTAL_ALIGNMENT_RIGHT)
	return tree


## The message an empty table shows under its column titles, so an empty panel never looks broken. It ignores the mouse.
static func _empty_note() -> Label:
	var note := label("Nothing to show yet.", 14)
	note.theme_type_variation = "MutedLabel"
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	note.offset_top = 44
	note.offset_left = 12
	note.name = "EmptyNote"
	return note


## Numbers (and money, percentages, ratios such as 0.533) read best right-aligned;
## names and sentences read best left-aligned. A column counts as numeric when every
## filled cell looks like a number. An empty table keeps column 0 left and the rest right.
static func _is_numeric_column(column: int, rows: Array) -> bool:
	if rows.is_empty():
		return column > 0
	var seen := false
	for row in rows:
		if column >= row.size():
			continue
		var cell := str(row[column]).strip_edges()
		if cell == "":
			continue
		seen = true
		if _numeric_pattern().search(cell) == null:
			return false
	return seen


static var _numeric_regex: RegEx = null


static func _numeric_pattern() -> RegEx:
	if _numeric_regex == null:
		_numeric_regex = RegEx.new()
		_numeric_regex.compile("^[-+$]?[\\d.,]+[MKB%]?$")
	return _numeric_regex


static func money(dollars: int) -> String:
	var sign := "-" if dollars < 0 else ""
	var a := absi(dollars)
	if a >= 1000000000:
		return "%s$%.2fB" % [sign, a / 1e9]
	if a >= 1000000:
		return "%s$%.1fM" % [sign, a / 1e6]
	if a >= 1000:
		return "%s$%dK" % [sign, roundi(a / 1000.0)]
	return "%s$%d" % [sign, a]


## A text label. `size` is a design size that follows the player's text-size setting (FcUiTokens.fs); `bold` makes it a
## heading: the display font in the heading colour (the condensed face is drawn a little larger so it reads the same).
static func label(text: String, size: int = 0, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	var px := FcUiTokens.fs(size) if size > 0 else 0
	if bold:
		l.theme_type_variation = "HeadingLabel"
		if px == 0:
			px = FcUiTokens.fs(FcUiTokens.TYPE_BODY)
		px = roundi(px * 1.12)
	if px > 0:
		l.add_theme_font_size_override("font_size", px)
	return l


static func button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	return b
