class_name FcTabPages
extends VBoxContainer
## Pages with a tab bar above them: the kit's replacement for Godot's TabContainer. The bar is the shared FcTabBar (underlined accent,
## scrolls sideways when the tabs do not fit, keyboard arrows), the open page fills the rest and the others are hidden. Owner Mode's
## screens use it so they share the look of the Dynasty and Career screens. It keeps the small reading API the screens and tests used
## (`current_tab`, `get_tab_count`, `get_tab_title`, `get_current_tab_control`, `tab_changed`).

const LONG_TEXT := 60
const WRAP_MIN_WIDTH := 240

signal tab_changed(index: int)

var current_tab: int = 0:
	set(value):
		open(value)
	get:
		return _current

var _bar := FcTabBar.new()
var _area := FcPanel.new("", FcPanel.Variant.SURFACE)
var _pages: Array[Control] = []
var _titles: Array[String] = []
var _current: int = 0


func _init() -> void:
	add_theme_constant_override("separation", FcUiTokens.SPACE_1)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bar.tab_selected.connect(func(id: String) -> void: open(int(id), true))
	add_child(_bar)
	_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_area.body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_area)


## Adds a page with its tab title. The first page added is the open one until open() says otherwise.
func add_page(page: Control, title: String) -> void:
	page.name = title
	wrap_long_labels(page)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pages.append(page)
	_titles.append(title)
	_area.body.add_child(page)
	page.visible = _pages.size() - 1 == _current
	var list: Array = []
	for i in _titles.size():
		list.append([str(i), _titles[i]])
	_bar.set_tabs(list, str(_current))


## Opens page `index` (clamped). Emits tab_changed only when the player picked it, so code that sets current_tab stays quiet.
func open(index: int, from_player: bool = false) -> void:
	if _pages.is_empty():
		_current = 0
		return
	index = clampi(index, 0, _pages.size() - 1)
	var changed := index != _current
	_current = index
	for i in _pages.size():
		_pages[i].visible = i == _current
	_bar.select(str(_current))
	if changed and from_player:
		tab_changed.emit(_current)


func get_tab_count() -> int:
	return _pages.size()


func get_tab_title(index: int) -> String:
	return _titles[index] if index >= 0 and index < _titles.size() else ""


func get_current_tab_control() -> Control:
	return _pages[_current] if _current < _pages.size() else null


## The tab button for a page (for tests and click tools).
func tab_button(index: int) -> Button:
	return _bar.button_for(str(index))


## Long sentences wrap instead of stretching the screen: any label of more than LONG_TEXT characters that does not wrap yet gets word
## wrapping and a minimum width of WRAP_MIN_WIDTH. Short labels and labels a screen already set up for wrapping are left alone.
static func wrap_long_labels(node: Node) -> void:
	if node is Label:
		var label := node as Label
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF and label.text.length() > LONG_TEXT:
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size.x = maxf(label.custom_minimum_size.x, WRAP_MIN_WIDTH)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for child in node.get_children():
		wrap_long_labels(child)
