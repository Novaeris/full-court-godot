class_name FcSkeleton
extends VBoxContainer
## A loading placeholder shaped like the content that is coming (rows of a table, lines of text): grey bars that pulse softly while
## something loads, so a screen never flashes empty and then jumps. Still (no pulse) when motion is reduced. Use it for content that
## takes a moment to appear; FcLoading is for a long wait with a message.

var _bars: Array = []


func _init(row_count: int = 5, row_height: int = 28) -> void:
	add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	for i in row_count:
		var bar := ColorRect.new()
		bar.color = FcUiTokens.SURFACE_HIGH
		bar.custom_minimum_size = Vector2(0, row_height)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar)
		_bars.append(bar)
	tooltip_text = "Loading"


func _ready() -> void:
	if FcMotion.reduced or _bars.is_empty():
		return
	var tw := create_tween().set_loops()
	tw.tween_property(self, "modulate:a", 0.55, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)


func bar_count() -> int:
	return _bars.size()
