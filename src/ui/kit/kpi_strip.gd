class_name FcKpiStrip
extends HFlowContainer
## The Franchise dashboard's row of key numbers (cash, record, payroll, attendance): each an FcStatTile with an accent bar. Wraps to
## the width available, so it stays usable in a small window. Items are {label, value, delta (optional)}.


func _init() -> void:
	add_theme_constant_override("h_separation", FcUiTokens.SPACE_3)
	add_theme_constant_override("v_separation", FcUiTokens.SPACE_3)


func set_items(items: Array) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	for item in items:
		var tile := FcStatTile.make(str(item.get("label", "")), str(item.get("value", "")), str(item.get("delta", "")), true)
		tile.custom_minimum_size.x = 150
		add_child(tile)


func tile_count() -> int:
	return get_child_count()
