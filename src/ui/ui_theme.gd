class_name FcUiTheme
extends RefCounted
## The look of the game in one place: colours, rounded panels, button and tab styles, table style and text size.
## The founder has not chosen a look yet (references are still wanted), so this is a calm default: a dark navy
## surface with a basketball-orange accent, easy to read on a desktop monitor. Change the constants here (or send
## references) and every screen follows; screens never set colours themselves except through this class.

const BACKGROUND := Color(0.075, 0.09, 0.125)
const SURFACE := Color(0.11, 0.13, 0.18)
const SURFACE_RAISED := Color(0.15, 0.175, 0.235)
const BORDER := Color(0.24, 0.28, 0.36)
const TEXT := Color(0.92, 0.94, 0.97)
const TEXT_MUTED := Color(0.62, 0.68, 0.78)
const ACCENT := Color(0.96, 0.55, 0.16)
const ACCENT_SOFT := Color(0.96, 0.55, 0.16, 0.22)
const HEADING := Color(0.98, 0.80, 0.42)
const GOOD := Color(0.30, 0.78, 0.55)
const BAD := Color(0.94, 0.36, 0.36)

## Text sizes the player can choose in the settings (index into SIZES): small, normal, large.
const SIZE_NAMES := ["Small", "Normal", "Large"]
const SIZES := [13, 15, 18]
const RADIUS := 6


static func font_size(index: int) -> int:
	return SIZES[clampi(index, 0, SIZES.size() - 1)]


## The whole Theme for the given text size choice (0 small, 1 normal, 2 large).
static func build(size_index: int = 1) -> Theme:
	var t := Theme.new()
	t.default_font_size = font_size(size_index)
	t.set_color("font_color", "Label", TEXT)
	for control in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		t.set_color("font_color", control, TEXT)
		t.set_color("font_hover_color", control, Color.WHITE)
		t.set_color("font_pressed_color", control, Color.WHITE)
		t.set_color("font_disabled_color", control, TEXT_MUTED)
	for control in ["Button", "OptionButton"]:
		t.set_stylebox("normal", control, _box(SURFACE_RAISED, BORDER, 1, 10, 6))
		t.set_stylebox("hover", control, _box(SURFACE_RAISED.lightened(0.1), ACCENT, 1, 10, 6))
		t.set_stylebox("pressed", control, _box(ACCENT.darkened(0.35), ACCENT, 1, 10, 6))
		t.set_stylebox("disabled", control, _box(SURFACE, BORDER, 1, 10, 6))
		t.set_stylebox("focus", control, _box(Color(0, 0, 0, 0), ACCENT, 2, 10, 6))
	t.set_stylebox("panel", "PanelContainer", _box(SURFACE, BORDER, 1, 12, 10))
	t.set_stylebox("panel", "PopupMenu", _box(SURFACE_RAISED, BORDER, 1, 6, 6))
	for control in ["LineEdit", "SpinBox"]:
		t.set_stylebox("normal", control, _box(SURFACE, BORDER, 1, 8, 5))
		t.set_stylebox("focus", control, _box(SURFACE, ACCENT, 2, 8, 5))
		t.set_color("font_color", control, TEXT)
	# tabs: the open tab is lifted and underlined in the accent colour
	t.set_stylebox("tab_selected", "TabContainer", _tab(SURFACE_RAISED, ACCENT))
	t.set_stylebox("tab_unselected", "TabContainer", _tab(SURFACE, Color(0, 0, 0, 0)))
	t.set_stylebox("tab_hovered", "TabContainer", _tab(SURFACE.lightened(0.08), BORDER))
	t.set_stylebox("panel", "TabContainer", _box(SURFACE, BORDER, 1, 10, 8))
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", TEXT_MUTED)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	# tables
	t.set_stylebox("panel", "Tree", _box(SURFACE, BORDER, 1, 4, 4))
	t.set_stylebox("selected", "Tree", _box(ACCENT_SOFT, ACCENT, 1, 4, 2))
	t.set_stylebox("selected_focus", "Tree", _box(ACCENT_SOFT, ACCENT, 1, 4, 2))
	t.set_stylebox("title_button_normal", "Tree", _box(SURFACE_RAISED, BORDER, 1, 6, 4))
	t.set_color("font_color", "Tree", TEXT)
	t.set_color("title_button_color", "Tree", HEADING)
	t.set_color("guide_color", "Tree", Color(0, 0, 0, 0))
	t.set_constant("v_separation", "Tree", 4)
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	return t


static func _box(fill: Color, border: Color, border_width: int, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(RADIUS)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	return s


static func _tab(fill: Color, underline: Color) -> StyleBoxFlat:
	var s := _box(fill, underline, 0, 12, 6)
	s.border_width_bottom = 3
	s.corner_radius_bottom_left = 0
	s.corner_radius_bottom_right = 0
	return s
