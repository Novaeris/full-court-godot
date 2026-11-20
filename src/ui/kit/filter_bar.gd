class_name FcFilterBar
extends HFlowContainer
## A row of filters that wraps to the width it has: a search box, dropdowns and chips (pill toggles). It keeps the current choices
## in values() (key to value) and emits changed(values) whenever one changes. Chips are single-choice (clicking the open chip
## clears it) or multi-choice (values holds an Array). A "Clear" button resets everything. The owner screen does the filtering;
## this only collects the choices.
## Options are [label, value] pairs.

signal changed(values: Dictionary)

var _values: Dictionary = {}
var _controls: Dictionary = {}   # key -> {"kind", "control"/"buttons", "multi"}
var _silent := false


func _init() -> void:
	add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	add_theme_constant_override("v_separation", FcUiTokens.SPACE_2)


func add_search(key: String, hint: String = "Search") -> FcSearchField:
	var field := FcSearchField.new(hint)
	_values[key] = ""
	_controls[key] = {"kind": "search", "control": field}
	field.search_changed.connect(func(text: String) -> void: _assign(key, text))
	add_child(field)
	return field


## `any_label` is shown for "no filter" (the first item, whose value is "").
func add_dropdown(key: String, any_label: String, options: Array) -> FcDropdown:
	var items: Array = [[any_label, ""]]
	items.append_array(options)
	var dd := FcDropdown.make(items, "")
	_values[key] = ""
	_controls[key] = {"kind": "dropdown", "control": dd}
	dd.chosen.connect(func(v) -> void: _assign(key, v))
	add_child(dd)
	return dd


func add_chips(key: String, options: Array, multi: bool = false) -> void:
	_values[key] = [] if multi else ""
	var buttons: Dictionary = {}
	_controls[key] = {"kind": "chips", "buttons": buttons, "multi": multi}
	for option in options:
		var b := Button.new()
		b.text = str(option[0])
		b.toggle_mode = true
		b.theme_type_variation = "ChipButton"
		b.custom_minimum_size.y = FcUiTokens.min_target()
		b.focus_mode = Control.FOCUS_ALL
		var value = option[1]
		buttons[value] = b
		b.toggled.connect(func(on: bool) -> void: _chip(key, value, on))
		add_child(b)


func add_clear_button(text: String = "Clear") -> void:
	add_child(FcButton.make(text, FcButton.Variant.GHOST, clear))


func values() -> Dictionary:
	return _values.duplicate(true)


## Restores choices (for example when coming back to a screen) without emitting changed.
func set_values(v: Dictionary) -> void:
	_silent = true
	for key in v:
		if not _controls.has(key):
			continue
		var c: Dictionary = _controls[key]
		match c["kind"]:
			"search":
				(c["control"] as LineEdit).text = str(v[key])
				_values[key] = str(v[key])
			"dropdown":
				(c["control"] as FcDropdown).select_value(v[key])
				_values[key] = v[key]
			"chips":
				var chosen: Array = v[key] if c["multi"] else [v[key]]
				for value in c["buttons"]:
					(c["buttons"][value] as Button).set_pressed_no_signal(value in chosen)
				_values[key] = chosen.duplicate() if c["multi"] else v[key]
	_silent = false


## Resets every filter and emits changed once.
func clear() -> void:
	var blank := {}
	for key in _controls:
		blank[key] = [] if _controls[key].get("multi", false) else ""
	set_values(blank)
	changed.emit(values())


func _assign(key: String, value) -> void:
	_values[key] = value
	if not _silent:
		changed.emit(values())


func _chip(key: String, value, on: bool) -> void:
	if _silent:
		return
	var c: Dictionary = _controls[key]
	if c["multi"]:
		var list: Array = _values[key]
		if on and not list.has(value):
			list.append(value)
		elif not on:
			list.erase(value)
	else:
		_silent = true
		for other in c["buttons"]:
			(c["buttons"][other] as Button).set_pressed_no_signal(on and other == value)
		_silent = false
		_values[key] = value if on else ""
	changed.emit(values())
