class_name FcSearchField
extends LineEdit
## A search box with a search icon and a clear button. search_changed(text) fires 250 ms after the player stops typing (so a
## list is not rebuilt on every key); text_submitted (Enter) fires at once. States: `loading` swaps the icon for a spinner
## glyph, `error` draws a red outline.

signal search_changed(query: String)

const DEBOUNCE := 0.25

var loading: bool = false:
	set(v):
		loading = v
		_glyph.texture = FcUiIcons.texture("loader" if v else "search")
var error: bool = false:
	set(v):
		error = v
		theme_type_variation = "ErrorLineEdit" if v else ""
var _timer := Timer.new()
## The search (or spinner) glyph at the right edge. LineEdit.right_icon cannot be scaled, so a small TextureRect is used.
var _glyph := FcUiIcons.rect("search", FcUiTokens.TEXT_MUTED, 18)


func _init(hint: String = "Search") -> void:
	placeholder_text = hint
	clear_button_enabled = true
	_glyph.anchor_left = 1.0
	_glyph.anchor_right = 1.0
	_glyph.anchor_top = 0.5
	_glyph.anchor_bottom = 0.5
	_glyph.offset_left = -30
	_glyph.offset_right = -12
	_glyph.offset_top = -9
	_glyph.offset_bottom = 9
	add_child(_glyph)
	draw.connect(func() -> void: _glyph.visible = text == "")   # once there is text, the clear button takes the glyph's place
	custom_minimum_size = Vector2(190, FcUiTokens.min_target())
	_timer.one_shot = true
	_timer.wait_time = DEBOUNCE
	add_child(_timer)
	_timer.timeout.connect(func() -> void: search_changed.emit(text))
	text_changed.connect(func(_t: String) -> void: _timer.start())
	text_submitted.connect(func(t: String) -> void:
		_timer.stop()
		search_changed.emit(t))
