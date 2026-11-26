class_name FcMatchupBanner
extends Control
## Two teams facing each other, the hero of a game preview and the Game Center: the away team on the left on its colour, the home team on
## the right on its colour, a dark centre with "AT" (or the final score once a game is played), and under each crest the name and record.
## Drawn in one node so it stays crisp at any width. Clicking it (or Enter) emits `activated`, so a dashboard can open the Game Center.

signal activated

## {"away": {"look", "name", "record", "score"?}, "home": {...}, "center": String (e.g. "AT", "FINAL"), "caption": String (date, venue),
##  "final": bool}
var data: Dictionary = {}
var _hover := false


func _init() -> void:
	custom_minimum_size = Vector2(420, 150)
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


func setup(matchup: Dictionary) -> FcMatchupBanner:
	data = matchup
	tooltip_text = describe(matchup)
	queue_redraw()
	return self


## "Dallas Ramparts (8-7) at Houston Sentinels (8-7), 2026-11-19" or with the final score.
static func describe(m: Dictionary) -> String:
	var a: Dictionary = m.get("away", {})
	var h: Dictionary = m.get("home", {})
	if bool(m.get("final", false)):
		return "%s %d at %s %d. %s" % [a.get("name", ""), int(a.get("score", 0)), h.get("name", ""), int(h.get("score", 0)), m.get("caption", "")]
	return "%s (%s) at %s (%s). %s" % [a.get("name", ""), a.get("record", ""), h.get("name", ""), h.get("record", ""), m.get("caption", "")]


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		activated.emit()
	elif event.is_action_pressed("ui_accept") and has_focus():
		accept_event()
		activated.emit()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var away: Dictionary = data.get("away", {})
	var home: Dictionary = data.get("home", {})
	var away_look: Dictionary = away.get("look", {})
	var home_look: Dictionary = home.get("look", {})
	var left := Color(away_look.get("fill", FcUiTokens.SURFACE_HIGH)).darkened(0.45)
	var right := Color(home_look.get("fill", FcUiTokens.SURFACE_HIGH)).darkened(0.45)
	var frame := StyleBoxFlat.new()
	frame.bg_color = FcUiTokens.SURFACE
	frame.set_corner_radius_all(FcUiTokens.RADIUS_CARD)
	if _hover or has_focus():
		frame.border_color = FcUiTokens.INFO if has_focus() else FcUiTokens.BORDER
		frame.set_border_width_all(2)
	FcUiTokens.elevate(frame, 2 if _hover else 1)
	draw_style_box(frame, r)
	# two colour fields slanted toward the middle
	var mid := size.x * 0.5
	var slant := size.y * 0.18
	draw_colored_polygon(PackedVector2Array([Vector2(8, 8), Vector2(mid - 40 + slant, 8), Vector2(mid - 40 - slant, size.y - 8), Vector2(8, size.y - 8)]), left)
	draw_colored_polygon(PackedVector2Array([Vector2(mid + 40 + slant, 8), Vector2(size.x - 8, 8), Vector2(size.x - 8, size.y - 8), Vector2(mid + 40 - slant, size.y - 8)]), right)
	var display := FcUiFonts.display(700)
	if display == null:
		display = ThemeDB.fallback_font
	var body := FcUiFonts.body(500, true)
	if body == null:
		body = ThemeDB.fallback_font
	var crest_px := clampf(size.y * 0.46, 40.0, 96.0)
	var name_fs := FcUiTokens.fs(FcUiTokens.TYPE_H3)
	var small := FcUiTokens.fs(FcUiTokens.TYPE_SMALL)
	var final := bool(data.get("final", false))
	for side in 2:
		var team: Dictionary = away if side == 0 else home
		var look: Dictionary = away_look if side == 0 else home_look
		var cx := size.x * (0.2 if side == 0 else 0.8)
		if not look.is_empty():
			FcTeamCrest.paint(self, Rect2(Vector2(cx - crest_px / 2.0, 14), Vector2(crest_px, crest_px)), look, true)
		var w := size.x * 0.36
		draw_string(display, Vector2(cx - w / 2.0, 14 + crest_px + name_fs + 4), str(team.get("name", "")), HORIZONTAL_ALIGNMENT_CENTER, w, name_fs, FcUiTokens.TEXT)
		var sub := str(team.get("record", ""))
		if sub != "":
			draw_string(body, Vector2(cx - w / 2.0, 14 + crest_px + name_fs + small + 10), sub, HORIZONTAL_ALIGNMENT_CENTER, w, small, FcUiTokens.TEXT_MUTED)
	# the centre: AT, or the final score
	var center_fs := FcUiTokens.fs(FcUiTokens.TYPE_DISPLAY if final else FcUiTokens.TYPE_H2)
	var center_text := "%d  –  %d" % [int(away.get("score", 0)), int(home.get("score", 0))] if final else str(data.get("center", "AT"))
	draw_string(display, Vector2(mid - 90, size.y * 0.5 + center_fs * 0.35), center_text, HORIZONTAL_ALIGNMENT_CENTER, 180, center_fs, FcUiTokens.TEXT)
	var caption := str(data.get("caption", ""))
	if caption != "":
		draw_string(body, Vector2(mid - 120, size.y - 12), caption, HORIZONTAL_ALIGNMENT_CENTER, 240, FcUiTokens.fs(FcUiTokens.TYPE_MICRO), FcUiTokens.TEXT_MUTED)
