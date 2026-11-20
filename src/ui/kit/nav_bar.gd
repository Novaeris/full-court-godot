class_name FcNavBar
extends VBoxContainer
## A mode's main navigation, in the form each presentation target needs. DESKTOP (bottom = false): a row of tabs along the top,
## all items visible. MOBILE (bottom = true): a bar along the bottom edge with at most `primary` items as icon-over-label buttons
## and a "More" button that opens the rest in a menu, every target at least 44 px tall. Same items, same signal either way.
## Items are [id, label, icon_name]. Emits selected(id) when the player picks one (select() does not emit).

signal selected(id: String)

const MAX_BOTTOM_ITEMS := 4

var current_id: String = ""
var bottom: bool = false
var _items: Array = []
var _primary: Array = []
var _tabs: FcTabBar = null
var _bar: PanelContainer = null
var _buttons: Dictionary = {}
var _more: Button = null
var _menu: PopupMenu = null


## Sets the items and builds the bar. `primary_ids` are the items kept on the bottom bar (the first MAX_BOTTOM_ITEMS if empty).
func setup(items: Array, current: String, on_bottom: bool, primary_ids: Array = []) -> void:
	_items = items
	current_id = current
	bottom = on_bottom
	_primary = primary_ids.duplicate()
	if _primary.is_empty():
		for item in items.slice(0, MAX_BOTTOM_ITEMS):
			_primary.append(item[0])
	_rebuild()


## Marks an item as the open one without emitting.
func select(id: String) -> void:
	current_id = id
	if _tabs != null:
		_tabs.select(id)
	for b_id in _buttons:
		(_buttons[b_id] as Button).set_pressed_no_signal(b_id == id)
	if _more != null:
		_more.set_pressed_no_signal(not _primary.has(id))


## The ids shown directly (all of them on desktop, the primary ones on the bottom bar).
func visible_ids() -> Array:
	if not bottom:
		var out: Array = []
		for item in _items:
			out.append(item[0])
		return out
	return _primary.duplicate()


## The ids that live in the More menu (none on desktop).
func overflow_ids() -> Array:
	var out: Array = []
	if bottom:
		for item in _items:
			if not _primary.has(item[0]):
				out.append(item[0])
	return out


func button_for(id: String) -> Button:
	return _tabs.button_for(id) if _tabs != null else _buttons.get(id)


func more_button() -> Button:
	return _more


func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_tabs = null
	_bar = null
	_buttons.clear()
	_more = null
	_menu = null
	if not bottom:
		_tabs = FcTabBar.new()
		var tabs: Array = []
		for item in _items:
			tabs.append([item[0], item[1]])
		_tabs.set_tabs(tabs, current_id)
		_tabs.tab_selected.connect(_pick)
		add_child(_tabs)
		return
	_bar = PanelContainer.new()
	_bar.theme_type_variation = "NavBarPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	_bar.add_child(row)
	var group := ButtonGroup.new()
	for item in _items:
		if not _primary.has(item[0]):
			continue
		var b := _nav_button(str(item[1]), str(item[2]) if item.size() > 2 else "")
		b.button_group = group
		var id := str(item[0])
		b.pressed.connect(func() -> void: _pick(id))
		_buttons[id] = b
		row.add_child(b)
	if not overflow_ids().is_empty():
		_more = _nav_button("More", "ellipsis")
		_more.pressed.connect(_open_menu)
		row.add_child(_more)
		_menu = PopupMenu.new()
		for item in _items:
			if not _primary.has(item[0]):
				_menu.add_item(str(item[1]))
				_menu.set_item_metadata(_menu.item_count - 1, str(item[0]))
		_menu.index_pressed.connect(func(i: int) -> void: _pick(str(_menu.get_item_metadata(i))))
		add_child(_menu)
	add_child(_bar)
	select(current_id)


func _nav_button(label: String, icon_name: String) -> Button:
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.theme_type_variation = "NavButton"
	b.icon = FcUiIcons.texture(icon_name)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, maxi(FcUiTokens.TOUCH_TARGET + 12, 56))
	b.focus_mode = Control.FOCUS_ALL
	return b


func _open_menu() -> void:
	if _menu == null or _more == null:
		return
	var rect := _more.get_global_rect()
	var menu_height := _menu.get_contents_minimum_size().y + 16
	_menu.popup(Rect2i(Vector2i(int(rect.position.x), int(rect.position.y - menu_height)), Vector2i(maxi(int(rect.size.x), 180), 0)))


func _pick(id: String) -> void:
	if id == current_id:
		select(id)
		return
	current_id = id
	select(id)
	selected.emit(id)
