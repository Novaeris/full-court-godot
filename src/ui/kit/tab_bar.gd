class_name FcTabBar
extends ScrollContainer
## A row of tabs: the open one is underlined in the accent colour. It scrolls sideways when the tabs do not fit (phones, small
## windows), so it never forces the window wider. Keyboard and controller: the buttons take focus and arrows move between them.
## Tabs are [id, label] or [id, label, icon_name]. Emits tab_selected(id) when the player picks one (select() does not emit).

signal tab_selected(id: String)

var current_id: String = ""
var _row := HBoxContainer.new()
var _group := ButtonGroup.new()
var _buttons: Dictionary = {}


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_row.add_theme_constant_override("separation", FcUiTokens.SPACE_1)
	add_child(_row)


## Replaces the tabs. The first one is open unless `selected` names another.
func set_tabs(tabs: Array, selected: String = "") -> void:
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	_buttons.clear()
	for tab in tabs:
		var b := Button.new()
		b.text = str(tab[1])
		b.toggle_mode = true
		b.button_group = _group
		b.theme_type_variation = "TabButton"
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size.y = FcUiTokens.min_target()
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if tab.size() > 2:
			b.icon = FcUiIcons.texture(str(tab[2]))
		var id := str(tab[0])
		b.pressed.connect(func() -> void: _pick(id))
		_row.add_child(b)
		_buttons[id] = b
	var first := str(tabs[0][0]) if not tabs.is_empty() else ""
	select(selected if _buttons.has(selected) else first)
	custom_minimum_size.y = FcUiTokens.min_target() + 8


## Opens a tab without emitting.
func select(id: String) -> void:
	current_id = id
	# set_pressed_no_signal does not release the other buttons of the group: without this a screen that reopens on the tab the player was
	# last on (every Owner screen rebuild) showed two tabs as open (found in the Owner presentation audit)
	for key in _buttons:
		(_buttons[key] as Button).set_pressed_no_signal(key == id)


func tab_ids() -> Array:
	return _buttons.keys()


func button_for(id: String) -> Button:
	return _buttons.get(id)


func _pick(id: String) -> void:
	if id == current_id:
		return
	current_id = id
	tab_selected.emit(id)
