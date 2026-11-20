class_name FcUiTheme
extends RefCounted
## The look of the game in one place: builds the Godot Theme from the design tokens (FcUiTokens), the fonts (FcUiFonts) and a mode
## skin (FcModeSkin). Screens never set colours themselves except through this class and the tokens.
## Besides the stock controls it defines theme type-variations that the kit uses (set `theme_type_variation`):
##   Button:      PrimaryButton, DangerButton, GhostButton, IconButton, TabButton, ChipButton, SegmentButton
##   Label:       HeadingLabel (display font, gold), DisplayLabel (big numbers), NumericLabel (tabular), MutedLabel, CaptionLabel
##   Panel:       RaisedPanel, FlatPanel, ModalPanel, ToastPanel, KpiPanel, LetterheadPanel, LowerThirdPanel, ScorePanel, ChipPanel
##   LineEdit:    ErrorLineEdit;  OptionButton: ErrorOption;  ProgressBar: SuccessProgress, DangerProgress, GoldProgress

# The constants below keep the names older screens use; their values come from the tokens.
const BACKGROUND := FcUiTokens.BG
const SURFACE := FcUiTokens.SURFACE
const SURFACE_RAISED := FcUiTokens.SURFACE_RAISED
const BORDER := FcUiTokens.BORDER
const TEXT := FcUiTokens.TEXT
const TEXT_MUTED := FcUiTokens.TEXT_MUTED
const ACCENT := FcUiTokens.PRIMARY
const ACCENT_SOFT := Color(0.9608, 0.549, 0.1608, 0.22)
const HEADING := FcUiTokens.GOLD
const GOOD := FcUiTokens.SUCCESS
const BAD := FcUiTokens.DANGER

## Text sizes the player can choose in the settings (index into SIZES): small, normal, large.
const SIZE_NAMES := ["Small", "Normal", "Large"]
const SIZES := [13, 15, 18]
const RADIUS := FcUiTokens.RADIUS_CONTROL

## The accent colour of the active theme (the skin's; screens and kit components that need it read it here).
static var accent: Color = ACCENT
## The active skin's resolved properties (see FcModeSkin.resolve).
static var skin: Dictionary = FcModeSkin.resolve(FcModeSkin.NEUTRAL)


static func font_size(index: int) -> int:
	return SIZES[clampi(index, 0, SIZES.size() - 1)]


## The whole Theme for the given text size choice (0 small, 1 normal, 2 large) and skin (a FcModeSkin.resolve result; neutral when empty).
## It also records the text scale and accent, so FcUiTables.label and kit components follow the same choice.
static func build(size_index: int = 1, skin_props: Dictionary = {}) -> Theme:
	var index := clampi(size_index, 0, FcUiTokens.TEXT_SCALES.size() - 1)
	FcUiTokens.text_scale = FcUiTokens.TEXT_SCALES[index]
	skin = skin_props if not skin_props.is_empty() else FcModeSkin.resolve(FcModeSkin.NEUTRAL)
	accent = skin["accent"]
	var density: float = skin["density"]
	var pad_x := roundi(10 * density)
	var pad_y := roundi(6 * density)
	if FcUiTokens.touch_mode:
		pad_x = 14
		pad_y = 12   # every stock button, including those of screens not yet on the kit, reaches about 44 px tall
	var t := Theme.new()
	t.default_font_size = font_size(index)
	var body := FcUiFonts.body(400)
	if body != null:
		t.default_font = body
	_labels(t)
	_buttons(t, pad_x, pad_y)
	_panels(t, density)
	_fields(t)
	_switches(t)
	_tabs_and_tables(t)
	_popups_and_tooltips(t)
	_ranges_and_scrollbars(t)
	var gap := roundi(8 * density)
	t.set_constant("separation", "VBoxContainer", gap)
	t.set_constant("separation", "HBoxContainer", gap)
	t.set_constant("h_separation", "HFlowContainer", gap)
	t.set_constant("v_separation", "HFlowContainer", gap)
	return t


static func _labels(t: Theme) -> void:
	t.set_color("font_color", "Label", TEXT)
	t.set_type_variation("HeadingLabel", "Label")
	t.set_color("font_color", "HeadingLabel", HEADING)
	var heading := FcUiFonts.display(600)
	if heading != null:
		t.set_font("font", "HeadingLabel", heading)
	t.set_type_variation("DisplayLabel", "Label")
	var big := FcUiFonts.display(700)
	if big != null:
		t.set_font("font", "DisplayLabel", big)
	t.set_type_variation("NumericLabel", "Label")
	var numeric := big if str(skin.get("numerals", "body")) == "display" else FcUiFonts.body(500, true)
	if numeric != null:
		t.set_font("font", "NumericLabel", numeric)
	t.set_type_variation("MutedLabel", "Label")
	t.set_color("font_color", "MutedLabel", TEXT_MUTED)
	t.set_type_variation("CaptionLabel", "Label")
	t.set_color("font_color", "CaptionLabel", TEXT_MUTED)
	var caption := FcUiFonts.body(600)
	if caption != null:
		t.set_font("font", "CaptionLabel", caption)


static func _buttons(t: Theme, pad_x: int, pad_y: int) -> void:
	for control in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		t.set_color("font_color", control, TEXT)
		t.set_color("font_hover_color", control, Color.WHITE)
		t.set_color("font_pressed_color", control, Color.WHITE)
		t.set_color("font_hover_pressed_color", control, Color.WHITE)
		t.set_color("font_focus_color", control, Color.WHITE)
		t.set_color("font_disabled_color", control, FcUiTokens.TEXT_DISABLED)
		t.set_color("icon_normal_color", control, TEXT)
		t.set_color("icon_hover_color", control, Color.WHITE)
		t.set_color("icon_pressed_color", control, Color.WHITE)
		t.set_color("icon_disabled_color", control, FcUiTokens.TEXT_DISABLED)
	# icons are imported at 2x for sharpness; this keeps them at text size (20 px) inside buttons
	t.set_constant("icon_max_width", "Button", 20)
	t.set_constant("icon_max_width", "OptionButton", 20)
	for control in ["Button", "OptionButton"]:
		t.set_stylebox("normal", control, _box(SURFACE_RAISED, BORDER, 1, pad_x, pad_y))
		t.set_stylebox("hover", control, _box(SURFACE_RAISED.lightened(0.1), accent, 1, pad_x, pad_y))
		t.set_stylebox("pressed", control, _box(accent.darkened(0.45), accent, 1, pad_x, pad_y))
		t.set_stylebox("hover_pressed", control, _box(accent.darkened(0.35), accent, 1, pad_x, pad_y))
		t.set_stylebox("disabled", control, _box(SURFACE, BORDER, 1, pad_x, pad_y))
		t.set_stylebox("focus", control, _focus_ring())
	# an error state for dropdowns (a red outline)
	t.set_type_variation("ErrorOption", "OptionButton")
	t.set_stylebox("normal", "ErrorOption", _box(SURFACE_RAISED, FcUiTokens.DANGER, 2, pad_x, pad_y))
	# solid buttons: dark text on the bright fill keeps at least 4.5:1 contrast
	_solid(t, "PrimaryButton", accent, pad_x, pad_y)
	_solid(t, "DangerButton", FcUiTokens.DANGER, pad_x, pad_y)
	# ghost: no fill until hovered
	t.set_type_variation("GhostButton", "Button")
	t.set_stylebox("normal", "GhostButton", _box(FcUiTokens.TRANSPARENT, FcUiTokens.TRANSPARENT, 1, pad_x, pad_y))
	t.set_stylebox("disabled", "GhostButton", _box(FcUiTokens.TRANSPARENT, FcUiTokens.TRANSPARENT, 1, pad_x, pad_y))
	t.set_stylebox("hover", "GhostButton", _box(SURFACE_RAISED, BORDER, 1, pad_x, pad_y))
	# icon: a square ghost button
	t.set_type_variation("IconButton", "GhostButton")
	t.set_stylebox("normal", "IconButton", _box(FcUiTokens.TRANSPARENT, FcUiTokens.TRANSPARENT, 1, 6, 6))
	t.set_stylebox("hover", "IconButton", _box(SURFACE_RAISED, BORDER, 1, 6, 6))
	t.set_stylebox("pressed", "IconButton", _box(accent.darkened(0.45), accent, 1, 6, 6))
	t.set_stylebox("disabled", "IconButton", _box(FcUiTokens.TRANSPARENT, FcUiTokens.TRANSPARENT, 1, 6, 6))
	# tabs: the open tab is underlined in the accent colour
	t.set_type_variation("TabButton", "Button")
	var tab_normal := _tab(FcUiTokens.TRANSPARENT, FcUiTokens.TRANSPARENT)
	var tab_hover := _tab(SURFACE, BORDER)
	var tab_open := _tab(SURFACE_RAISED, accent)
	for state in ["normal", "disabled"]:
		t.set_stylebox(state, "TabButton", tab_normal)
	t.set_stylebox("hover", "TabButton", tab_hover)
	t.set_stylebox("pressed", "TabButton", tab_open)
	t.set_stylebox("hover_pressed", "TabButton", tab_open)
	t.set_color("font_color", "TabButton", TEXT_MUTED)
	# the bottom navigation bar (mobile): icon over label, the open item in the accent colour with a bar on top
	t.set_type_variation("NavButton", "Button")
	var nav_rest := _box(FcUiTokens.TRANSPARENT, FcUiTokens.TRANSPARENT, 0, 4, 6, 0)
	var nav_open := _box(SURFACE_RAISED, accent, 0, 4, 6, 0)
	nav_open.border_width_top = 3
	for state in ["normal", "disabled"]:
		t.set_stylebox(state, "NavButton", nav_rest)
	t.set_stylebox("hover", "NavButton", _box(SURFACE, FcUiTokens.TRANSPARENT, 0, 4, 6, 0))
	t.set_stylebox("pressed", "NavButton", nav_open)
	t.set_stylebox("hover_pressed", "NavButton", nav_open)
	t.set_color("font_color", "NavButton", TEXT_MUTED)
	t.set_color("icon_normal_color", "NavButton", TEXT_MUTED)
	for color_name in ["font_pressed_color", "font_hover_pressed_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		t.set_color(color_name, "NavButton", accent)
	t.set_constant("icon_max_width", "NavButton", 24)
	t.set_constant("h_separation", "NavButton", 2)
	# chips and segmented choices: pill-shaped toggles
	for variation in ["ChipButton", "SegmentButton"]:
		t.set_type_variation(variation, "Button")
		var radius := 999 if variation == "ChipButton" else FcUiTokens.RADIUS_CONTROL
		t.set_stylebox("normal", variation, _box(SURFACE, BORDER, 1, 12, 4, radius))
		t.set_stylebox("hover", variation, _box(SURFACE_RAISED, accent, 1, 12, 4, radius))
		t.set_stylebox("pressed", variation, _box(accent, accent, 1, 12, 4, radius))
		t.set_stylebox("hover_pressed", variation, _box(accent.lightened(0.12), accent, 1, 12, 4, radius))
		t.set_stylebox("disabled", variation, _box(SURFACE, BORDER, 1, 12, 4, radius))
		t.set_color("font_pressed_color", variation, FcUiContrast.readable_on(accent))
		t.set_color("font_hover_pressed_color", variation, FcUiContrast.readable_on(accent))


static func _solid(t: Theme, variation: String, fill: Color, pad_x: int, pad_y: int) -> void:
	t.set_type_variation(variation, "Button")
	var ink := FcUiContrast.readable_on(fill)
	t.set_stylebox("normal", variation, _box(fill, fill, 1, pad_x, pad_y))
	t.set_stylebox("hover", variation, _box(fill.lightened(0.12), fill.lightened(0.12), 1, pad_x, pad_y))
	t.set_stylebox("pressed", variation, _box(fill.darkened(0.18), fill.darkened(0.18), 1, pad_x, pad_y))
	t.set_stylebox("hover_pressed", variation, _box(fill.darkened(0.1), fill.darkened(0.1), 1, pad_x, pad_y))
	t.set_stylebox("disabled", variation, _box(SURFACE_RAISED, BORDER, 1, pad_x, pad_y))
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		t.set_color(color_name, variation, ink)


static func _panels(t: Theme, density: float) -> void:
	var pad := roundi(10 * density)
	t.set_stylebox("panel", "PanelContainer", _box(SURFACE, BORDER, 1, roundi(12 * density), pad, FcUiTokens.RADIUS_PANEL))
	var variants := {
		"RaisedPanel": FcUiTokens.elevate(_box(SURFACE_RAISED, BORDER, 1, 14, 12, FcUiTokens.RADIUS_PANEL), 1),
		"FlatPanel": _box(SURFACE, FcUiTokens.TRANSPARENT, 0, 12, 10, FcUiTokens.RADIUS_PANEL),
		"ModalPanel": FcUiTokens.elevate(_box(SURFACE_RAISED, BORDER, 1, 20, 18, FcUiTokens.RADIUS_MODAL), 3),
		"ToastPanel": FcUiTokens.elevate(_box(SURFACE_RAISED, BORDER, 1, 14, 10, FcUiTokens.RADIUS_CONTROL), 2),
		"ChipPanel": _box(SURFACE_RAISED, BORDER, 1, 10, 2, 999),
	}
	for name in variants:
		t.set_type_variation(name, "PanelContainer")
		t.set_stylebox("panel", name, variants[name])
	var kpi := _box(SURFACE_RAISED, accent, 0, 14, 10, FcUiTokens.RADIUS_PANEL)
	kpi.border_width_top = 3   # an accent bar on top only
	t.set_type_variation("KpiPanel", "PanelContainer")
	t.set_stylebox("panel", "KpiPanel", kpi)
	var letterhead := _box(FcUiTokens.TRANSPARENT, accent, 0, 4, 10, 0)
	letterhead.border_width_bottom = 3
	t.set_type_variation("LetterheadPanel", "PanelContainer")
	t.set_stylebox("panel", "LetterheadPanel", letterhead)
	var third := _box(Color(SURFACE.r, SURFACE.g, SURFACE.b, 0.94), accent, 0, 16, 8, 2)
	third.border_width_left = 6
	t.set_type_variation("LowerThirdPanel", "PanelContainer")
	t.set_stylebox("panel", "LowerThirdPanel", third)
	var nav_bar := _box(SURFACE, BORDER, 0, 0, 0, 0)
	nav_bar.border_width_top = 1
	t.set_type_variation("NavBarPanel", "PanelContainer")
	t.set_stylebox("panel", "NavBarPanel", nav_bar)
	t.set_type_variation("ScorePanel", "PanelContainer")
	t.set_stylebox("panel", "ScorePanel", FcUiTokens.elevate(_box(FcUiTokens.BG, BORDER, 1, 12, 6, 8), 1))


## Check boxes and switches: no box around them (the state is shown by the icon), a soft highlight on hover, the focus ring.
static func _switches(t: Theme) -> void:
	for control in ["CheckBox", "CheckButton"]:
		var rest := _box(FcUiTokens.TRANSPARENT, FcUiTokens.TRANSPARENT, 0, 6, 4)
		var over := _box(SURFACE_RAISED, FcUiTokens.TRANSPARENT, 0, 6, 4)
		for state in ["normal", "pressed", "disabled"]:
			t.set_stylebox(state, control, rest)
		for state in ["hover", "hover_pressed"]:
			t.set_stylebox(state, control, over)
		t.set_stylebox("focus", control, _focus_ring())
		t.set_constant("h_separation", control, 10)
	t.set_icon("checked", "CheckButton", _switch_icon(true, true))
	t.set_icon("unchecked", "CheckButton", _switch_icon(false, true))
	t.set_icon("checked_disabled", "CheckButton", _switch_icon(true, false))
	t.set_icon("unchecked_disabled", "CheckButton", _switch_icon(false, false))


## A drawn switch (a rounded track with a round knob): the accent colour when on, slate when off, dim when disabled.
static func _switch_icon(on: bool, enabled: bool) -> Texture2D:
	var w := 40
	var h := 22
	var r := h / 2.0
	var track := accent if on else BORDER.lightened(0.25)
	var knob := FcUiTokens.TEXT
	if not enabled:
		track = Color(track, 0.45)
		knob = FcUiTokens.TEXT_DISABLED
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var knob_x := w - r if on else r
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var edge := p.distance_to(Vector2(clampf(p.x, r, w - r), r)) - r
			var px := Color(track.r, track.g, track.b, track.a * clampf(0.5 - edge, 0.0, 1.0))
			var knob_edge := p.distance_to(Vector2(knob_x, r)) - (r - 3.0)
			px = px.blend(Color(knob.r, knob.g, knob.b, knob.a * clampf(0.5 - knob_edge, 0.0, 1.0)))
			img.set_pixel(x, y, px)
	return ImageTexture.create_from_image(img)


static func _fields(t: Theme) -> void:
	for control in ["LineEdit", "SpinBox"]:
		t.set_stylebox("normal", control, _box(SURFACE, BORDER, 1, 8, 5))
		t.set_stylebox("focus", control, _box(SURFACE, accent, 2, 8, 5))
		t.set_stylebox("read_only", control, _box(SURFACE, BORDER, 1, 8, 5))
		t.set_color("font_color", control, TEXT)
		t.set_color("font_placeholder_color", control, TEXT_MUTED)
		t.set_color("caret_color", control, accent)
	t.set_type_variation("ErrorLineEdit", "LineEdit")
	t.set_stylebox("normal", "ErrorLineEdit", _box(SURFACE, FcUiTokens.DANGER, 2, 8, 5))
	t.set_stylebox("focus", "ErrorLineEdit", _box(SURFACE, FcUiTokens.DANGER, 2, 8, 5))


static func _tabs_and_tables(t: Theme) -> void:
	t.set_stylebox("tab_selected", "TabContainer", _tab(SURFACE_RAISED, accent))
	t.set_stylebox("tab_unselected", "TabContainer", _tab(SURFACE, FcUiTokens.TRANSPARENT))
	t.set_stylebox("tab_hovered", "TabContainer", _tab(SURFACE.lightened(0.08), BORDER))
	t.set_stylebox("panel", "TabContainer", _box(SURFACE, BORDER, 1, 10, 8, FcUiTokens.RADIUS_PANEL))
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", TEXT_MUTED)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_stylebox("panel", "Tree", _box(SURFACE, BORDER, 1, 4, 4, 4))
	t.set_stylebox("selected", "Tree", _box(ACCENT_SOFT, accent, 1, 4, 2, 4))
	t.set_stylebox("selected_focus", "Tree", _box(ACCENT_SOFT, accent, 1, 4, 2, 4))
	t.set_stylebox("title_button_normal", "Tree", _box(SURFACE_RAISED, BORDER, 1, 6, 4))
	t.set_color("font_color", "Tree", TEXT)
	t.set_color("title_button_color", "Tree", HEADING)
	t.set_color("guide_color", "Tree", FcUiTokens.TRANSPARENT)
	t.set_constant("v_separation", "Tree", 4)


static func _popups_and_tooltips(t: Theme) -> void:
	t.set_stylebox("panel", "PopupMenu", FcUiTokens.elevate(_box(SURFACE_RAISED, BORDER, 1, 6, 6), 2))
	t.set_stylebox("hover", "PopupMenu", _box(ACCENT_SOFT, FcUiTokens.TRANSPARENT, 0, 6, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("panel", "TooltipPanel", FcUiTokens.elevate(_box(FcUiTokens.BG, BORDER, 1, 10, 6), 2))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", FcUiTokens.TYPE_SMALL)
	t.set_stylebox("panel", "AcceptDialog", FcUiTokens.elevate(_box(SURFACE_RAISED, BORDER, 1, 14, 12, FcUiTokens.RADIUS_MODAL), 3))


static func _ranges_and_scrollbars(t: Theme) -> void:
	var track := _box(SURFACE_RAISED, BORDER, 1, 0, 3, 4)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", _box(accent, accent, 0, 0, 3, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(accent.lightened(0.15), accent, 0, 0, 3, 4))
	t.set_stylebox("background", "ProgressBar", _box(SURFACE_RAISED, BORDER, 1, 0, 0, 5))
	t.set_stylebox("fill", "ProgressBar", _box(accent, accent, 0, 0, 0, 5))
	for pair in [["SuccessProgress", FcUiTokens.SUCCESS], ["DangerProgress", FcUiTokens.DANGER], ["GoldProgress", FcUiTokens.GOLD]]:
		t.set_type_variation(pair[0], "ProgressBar")
		t.set_stylebox("fill", pair[0], _box(pair[1], pair[1], 0, 0, 0, 5))
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, _box(FcUiTokens.TRANSPARENT, FcUiTokens.TRANSPARENT, 0, 0, 0, 4))
		t.set_stylebox("grabber", bar, _box(BORDER, BORDER, 0, 0, 0, 4))
		t.set_stylebox("grabber_highlight", bar, _box(TEXT_MUTED, TEXT_MUTED, 0, 0, 0, 4))
		t.set_stylebox("grabber_pressed", bar, _box(accent, accent, 0, 0, 0, 4))


static func _box(fill: Color, border: Color, border_width: int, pad_x: int, pad_y: int, radius: int = FcUiTokens.RADIUS_CONTROL) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	return s


static func _focus_ring() -> StyleBoxFlat:
	var s := _box(FcUiTokens.TRANSPARENT, TEXT, 2, 10, 6)
	s.set_expand_margin_all(1)
	return s


static func _tab(fill: Color, underline: Color) -> StyleBoxFlat:
	var s := _box(fill, underline, 0, 12, 6)
	s.border_width_bottom = 3
	s.corner_radius_bottom_left = 0
	s.corner_radius_bottom_right = 0
	return s
