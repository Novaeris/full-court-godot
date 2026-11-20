class_name FcDataTable
extends RefCounted
## Tables for both presentation targets. Desktop: the dense sortable-looking Tree (FcUiTables.table), unchanged. Compact (touch and
## phone layouts): the same rows as a stack of small cards, the first column as the title and the others as "label  value" lines,
## so nothing needs sideways scrolling. An empty table shows an FcEmptyState instead of a blank grid.
## options: compact (bool, default FcUiTokens.touch_mode), empty_title, empty_text.


static func build(columns: Array, rows: Array, widths: Array = [], options: Dictionary = {}) -> Control:
	if rows.is_empty():
		return FcEmptyState.new(str(options.get("empty_title", "Nothing here yet")), str(options.get("empty_text", "")))
	if not bool(options.get("compact", FcUiTokens.touch_mode)):
		var tree := FcUiTables.table(columns, rows, widths)
		# a Tree has no height of its own: show up to 12 rows (the player scrolls beyond that) unless the caller says otherwise
		tree.custom_minimum_size.y = float(options.get("min_height", mini(rows.size(), 12) * 30 + 36))
		return tree
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	for row in rows:
		var card := FcPanel.new("", FcPanel.Variant.FLAT)
		card.add(FcUiTables.label(str(row[0]) if row.size() > 0 else "", FcUiTokens.TYPE_H3, true))
		for i in range(1, columns.size()):
			card.add(FcStatLine.make(str(columns[i]), str(row[i]) if i < row.size() else ""))
		stack.add_child(card)
	return stack
