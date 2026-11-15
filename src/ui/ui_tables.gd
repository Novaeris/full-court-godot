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
		tree.set_column_expand(i, i == 0 or widths.is_empty())
		if i < widths.size():
			tree.set_column_custom_minimum_width(i, int(widths[i]))
			tree.set_column_expand(i, false)
		if i > 0:
			tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_RIGHT)
	var root := tree.create_item()
	for row in rows:
		var item := tree.create_item(root)
		for i in columns.size():
			item.set_text(i, str(row[i]) if i < row.size() else "")
			if i > 0:
				item.set_text_alignment(i, HORIZONTAL_ALIGNMENT_RIGHT)
	return tree


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


static func label(text: String, size: int = 0, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if bold:
		l.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	return l


static func button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	return b
