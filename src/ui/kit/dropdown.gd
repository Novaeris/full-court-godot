class_name FcDropdown
extends OptionButton
## A dropdown for choosing one item from a list. Items are strings or [label, value] pairs; value() returns the chosen value
## (or the label when no value was given). `error` draws a red outline (a missing or invalid choice).

signal chosen(value)

var error: bool = false:
	set(v):
		error = v
		theme_type_variation = "ErrorOption" if error else ""
var _values: Array = []


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	fit_to_longest_item = false
	item_selected.connect(func(i: int) -> void: chosen.emit(_values[i]))


## Replaces the items and selects the one whose value is `current` (the first when none matches).
func set_items(items: Array, current = null) -> void:
	clear()
	_values.clear()
	for item in items:
		var label := str(item[0]) if item is Array else str(item)
		_values.append(item[1] if item is Array else item)
		add_item(label)
	selected = maxi(0, _values.find(current)) if not _values.is_empty() else -1
	custom_minimum_size.y = FcUiTokens.min_target()


func value():
	return _values[selected] if selected >= 0 and selected < _values.size() else null


## Selects by value without emitting.
func select_value(v) -> void:
	var i := _values.find(v)
	if i >= 0:
		selected = i


static func make(items: Array, current = null, on_choose: Callable = Callable()) -> FcDropdown:
	var d := FcDropdown.new()
	d.set_items(items, current)
	if on_choose.is_valid():
		d.chosen.connect(on_choose)
	return d
