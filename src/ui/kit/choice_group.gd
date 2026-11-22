class_name FcChoiceGroup
extends HBoxContainer
## A segmented choice: exactly one of a few options is selected (grid or carousel, a difficulty, a sort direction). Use a
## dropdown for long lists. Options are [id, label]. Emits selected(id) when the player picks one (select() does not emit).

signal selected(id: String)

var current_id: String = ""
var _group := ButtonGroup.new()
var _buttons: Dictionary = {}


func _init() -> void:
	add_theme_constant_override("separation", 2)


func set_options(options: Array, current: String = "") -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_buttons.clear()
	for option in options:
		var b := Button.new()
		b.text = str(option[1])
		b.toggle_mode = true
		b.button_group = _group
		b.theme_type_variation = "SegmentButton"
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size.y = FcUiTokens.min_target()
		var id := str(option[0])
		b.pressed.connect(func() -> void: _pick(id))
		add_child(b)
		_buttons[id] = b
	var first := str(options[0][0]) if not options.is_empty() else ""
	select(current if _buttons.has(current) else first)


func select(id: String) -> void:
	current_id = id
	if _buttons.has(id):
		for key in _buttons:   # set_pressed_no_signal does not release the others in the group, so do it here
			(_buttons[key] as Button).set_pressed_no_signal(str(key) == id)


func button_for(id: String) -> Button:
	return _buttons.get(id)


func _pick(id: String) -> void:
	if id == current_id:
		return
	current_id = id
	selected.emit(id)
