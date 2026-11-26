class_name FcCalendarGrid
extends VBoxContainer
## A month of the season as a grid (Monday first): the weekday header, then one cell per day. A cell shows the day number, the user's
## game that day (opponent crest, "vs" or "@", the result once played), how many league games there are, and up to two event chips
## (trade deadline, All-Star, playoffs). Today and the selected day are marked; days outside the month are dimmed. Clicking a day or moving
## with the arrow keys selects it (`date_selected`). It is a view: the screen decides what goes in each cell from the real schedule.

signal date_selected(iso: String)

const WEEKDAYS := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
const CELL_MIN := Vector2(96, 84)

var year: int = 2000
var month: int = 1
var selected_iso: String = ""
var today_iso: String = ""
## iso -> cell data: {"user": {"look": Dictionary, "home": bool, "opponent": String, "result": "W"|"L"|"", "score": String},
##   "games": int, "events": [{"text": String, "tone": "info"|"gold"|"danger"|"success"|"neutral"}], "dim": bool}
var cells: Dictionary = {}
var _grid := GridContainer.new()
var _cells_by_iso: Dictionary = {}


func _init() -> void:
	add_theme_constant_override("separation", FcUiTokens.SPACE_1)
	var head := GridContainer.new()
	head.columns = 7
	head.add_theme_constant_override("h_separation", FcUiTokens.SPACE_1)
	for d in WEEKDAYS:
		var l := Label.new()
		l.text = d.to_upper()
		l.theme_type_variation = "CaptionLabel"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(l)
	add_child(head)
	_grid.columns = 7
	_grid.add_theme_constant_override("h_separation", FcUiTokens.SPACE_1)
	_grid.add_theme_constant_override("v_separation", FcUiTokens.SPACE_1)
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_grid)


## Shows a month. `cell_data` is keyed by ISO date ("2026-11-19"); days without an entry are plain.
func setup(y: int, m: int, cell_data: Dictionary, selected: String = "", today: String = "") -> FcCalendarGrid:
	year = y
	month = m
	cells = cell_data
	selected_iso = selected
	today_iso = today
	_rebuild()
	return self


static func month_title(y: int, m: int) -> String:
	return "%s %d" % [MONTHS[clampi(m, 1, 12) - 1], y]


## The ISO dates shown, first to last (whole weeks, so a few days of the months before and after).
func shown_dates() -> Array[String]:
	var out: Array[String] = []
	var first := FcDate.new(year, month, 1)
	var start := first.add_days(-first.weekday())
	var last := FcDate.new(year, month, FcDate.days_in_month(year, month))
	var count := start.days_until_date(last) + 1
	count += (7 - count % 7) % 7
	for i in count:
		out.append(start.add_days(i).to_iso())
	return out


func select(iso: String, emit: bool = true) -> void:
	selected_iso = iso
	for key in _cells_by_iso:
		(_cells_by_iso[key] as _Cell).queue_redraw()
	if _cells_by_iso.has(iso) and (_cells_by_iso[iso] as _Cell).is_inside_tree() and (_cells_by_iso[iso] as _Cell).is_visible_in_tree():
		(_cells_by_iso[iso] as _Cell).grab_focus()
	if emit:
		date_selected.emit(iso)


func cell_for(iso: String) -> Control:
	return _cells_by_iso.get(iso)


func _rebuild() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_cells_by_iso.clear()
	for iso in shown_dates():
		var d := FcDate.from_iso(iso)
		var cell := _Cell.new()
		cell.grid = self
		cell.iso = iso
		cell.day = d.day
		cell.in_month = d.month == month
		cell.data = cells.get(iso, {})
		cell.custom_minimum_size = CELL_MIN
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cell.tooltip_text = _describe(iso, cell.data)
		_grid.add_child(cell)
		_cells_by_iso[iso] = cell


## A day in words (the tooltip): "2026-11-19: vs DAL, won 102-99; 7 league games; Trade deadline".
static func _describe(iso: String, data: Dictionary) -> String:
	var parts: Array = [iso]
	var user: Dictionary = data.get("user", {})
	if not user.is_empty():
		var t := "%s %s" % ["vs" if user.get("home", true) else "at", str(user.get("opponent", ""))]
		match str(user.get("result", "")):
			"W": t += ", won " + str(user.get("score", ""))
			"L": t += ", lost " + str(user.get("score", ""))
		parts.append(t)
	if int(data.get("games", 0)) > 0:
		parts.append("%d league game%s" % [int(data["games"]), "" if int(data["games"]) == 1 else "s"])
	for e in data.get("events", []):
		parts.append(str(e.get("text", "")))
	return "; ".join(parts)


static func tone_color(tone: String) -> Color:
	match tone:
		"gold": return FcUiTokens.GOLD
		"danger": return FcUiTokens.DANGER
		"success": return FcUiTokens.SUCCESS
		"info": return FcUiTokens.INFO
		"primary": return FcUiTokens.PRIMARY
	return FcUiTokens.STEEL


func _move(from_iso: String, days: int) -> void:
	var target := FcDate.from_iso(from_iso).add_days(days).to_iso()
	if _cells_by_iso.has(target):
		select(target)


## One day of the grid, drawn in a single node.
class _Cell extends Control:
	var grid: FcCalendarGrid
	var iso: String = ""
	var day: int = 1
	var in_month: bool = true
	var data: Dictionary = {}
	var _hover := false

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void:
			_hover = true
			queue_redraw())
		mouse_exited.connect(func() -> void:
			_hover = false
			queue_redraw())
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			grid.select(iso)
			accept_event()
		elif event.is_action_pressed("ui_accept"):
			grid.select(iso)
			accept_event()
		elif event.is_action_pressed("ui_right"):
			grid._move(iso, 1)
			accept_event()
		elif event.is_action_pressed("ui_left"):
			grid._move(iso, -1)
			accept_event()
		elif event.is_action_pressed("ui_down"):
			grid._move(iso, 7)
			accept_event()
		elif event.is_action_pressed("ui_up"):
			grid._move(iso, -7)
			accept_event()

	func _draw() -> void:
		var selected := grid.selected_iso == iso
		var today := grid.today_iso == iso
		var dim := not in_month or bool(data.get("dim", false))
		var box := StyleBoxFlat.new()
		box.bg_color = FcUiTokens.SURFACE_HIGH if (_hover or selected) else (FcUiTokens.SURFACE if dim else FcUiTokens.SURFACE_RAISED)
		box.set_corner_radius_all(FcUiTokens.RADIUS_CONTROL)
		if selected or has_focus():
			box.border_color = FcUiTokens.INFO
			box.set_border_width_all(2)
		elif today:
			box.border_color = FcUiTokens.PRIMARY
			box.set_border_width_all(2)
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		var display := FcUiFonts.display(700)
		if display == null:
			display = ThemeDB.fallback_font
		var body := FcUiFonts.body(500, true)
		if body == null:
			body = ThemeDB.fallback_font
		var ink := FcUiTokens.TEXT_DISABLED if dim else FcUiTokens.TEXT
		var micro := FcUiTokens.fs(FcUiTokens.TYPE_MICRO)
		draw_string(display, Vector2(8, 6 + FcUiTokens.fs(FcUiTokens.TYPE_H3)), str(day), HORIZONTAL_ALIGNMENT_LEFT, -1, FcUiTokens.fs(FcUiTokens.TYPE_H3), FcUiTokens.PRIMARY if today else ink)
		var games := int(data.get("games", 0))
		if games > 0:
			draw_string(body, Vector2(size.x - 40, 18), "%d gm" % games, HORIZONTAL_ALIGNMENT_RIGHT, 32, micro, FcUiTokens.TEXT_MUTED)
		var y := 30.0
		var user: Dictionary = data.get("user", {})
		if not user.is_empty():
			var look: Dictionary = user.get("look", {})
			if not look.is_empty():
				FcTeamCrest.paint(self, Rect2(Vector2(8, y), Vector2(22, 22)), look, false)
			var line := "%s %s" % ["vs" if user.get("home", true) else "@", str(user.get("opponent", ""))]
			draw_string(body, Vector2(34, y + 16), line, HORIZONTAL_ALIGNMENT_LEFT, size.x - 40, FcUiTokens.fs(FcUiTokens.TYPE_SMALL), ink)
			var result := str(user.get("result", ""))
			if result != "":
				var c := FcUiTokens.SUCCESS if result == "W" else FcUiTokens.DANGER
				draw_string(body, Vector2(8, y + 36), "%s %s" % [result, str(user.get("score", ""))], HORIZONTAL_ALIGNMENT_LEFT, size.x - 12, micro, c)
				y += 18
			y += 26
		for e in (data.get("events", []) as Array).slice(0, 2):
			if y + 16 > size.y:
				break
			var c := FcCalendarGrid.tone_color(str(e.get("tone", "")))
			var chip := StyleBoxFlat.new()
			chip.bg_color = Color(c, 0.22)
			chip.set_corner_radius_all(4)
			draw_style_box(chip, Rect2(Vector2(6, y), Vector2(size.x - 12, 16)))
			draw_string(body, Vector2(10, y + 12), str(e.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, size.x - 18, micro, c.lightened(0.25))
			y += 19
