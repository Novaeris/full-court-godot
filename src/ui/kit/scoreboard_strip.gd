class_name FcScoreboardStrip
extends ScrollContainer
## The league scoreboard of one day, as a row of compact game boxes (the ticker under a broadcast): both crests and abbreviations, the
## score once a game is final (winner in bold colour) or "Upcoming" before, and an optional note ("OT", "Game 3"). The user's game is
## marked. Clicking a box (or Enter on it) emits `game_selected` with the game's id. It shows what it is given: a game with no stored
## score is never shown with one.

signal game_selected(game_id: int)

const BOX_SIZE := Vector2(176, 70)

var _row := HBoxContainer.new()
var games: Array = []


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	custom_minimum_size = Vector2(0, BOX_SIZE.y + 14)
	_row.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	add_child(_row)


## Each game: {"id": int, "away": {"look": Dictionary, "abbr": String, "score": int}, "home": {...}, "final": bool, "note": String,
## "user": bool}. An empty list shows `empty_text`.
func set_games(game_list: Array, empty_text: String = "No games on this day") -> FcScoreboardStrip:
	games = game_list
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	if game_list.is_empty():
		var l := Label.new()
		l.text = empty_text
		l.theme_type_variation = "MutedLabel"
		_row.add_child(l)
		return self
	for g in game_list:
		var box := _GameBox.new()
		box.data = g
		box.custom_minimum_size = BOX_SIZE
		box.tooltip_text = describe(g)
		box.pressed.connect(func() -> void: game_selected.emit(int(g.get("id", 0))))
		_row.add_child(box)
	return self


func box_count() -> int:
	return games.size()


## A game in words: "DAL 99 at HOU 102, final" or "DAL at HOU, upcoming".
static func describe(g: Dictionary) -> String:
	var a: Dictionary = g.get("away", {})
	var h: Dictionary = g.get("home", {})
	if bool(g.get("final", false)):
		return "%s %d at %s %d, final%s" % [a.get("abbr", ""), int(a.get("score", 0)), h.get("abbr", ""), int(h.get("score", 0)), (" (%s)" % g["note"]) if str(g.get("note", "")) != "" else ""]
	return "%s at %s, upcoming%s" % [a.get("abbr", ""), h.get("abbr", ""), (" (%s)" % g["note"]) if str(g.get("note", "")) != "" else ""]


class _GameBox extends Button:
	var data: Dictionary = {}

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = FcUiTokens.SURFACE_HIGH if is_hovered() else FcUiTokens.SURFACE_RAISED
		box.set_corner_radius_all(FcUiTokens.RADIUS_CONTROL)
		if bool(data.get("user", false)):
			box.border_color = FcUiTokens.PRIMARY
			box.border_width_left = 3
		if has_focus():
			box.border_color = FcUiTokens.INFO
			box.set_border_width_all(2)
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		var body := FcUiFonts.body(600, true)
		if body == null:
			body = ThemeDB.fallback_font
		var fs := FcUiTokens.fs(FcUiTokens.TYPE_SMALL)
		var final := bool(data.get("final", false))
		var sides := [data.get("away", {}), data.get("home", {})]
		var scores: Array[int] = [int(sides[0].get("score", 0)), int(sides[1].get("score", 0))]
		for i in 2:
			var s: Dictionary = sides[i]
			var y := 8.0 + i * 24.0
			var look: Dictionary = s.get("look", {})
			if not look.is_empty():
				FcTeamCrest.paint(self, Rect2(Vector2(8, y), Vector2(20, 20)), look, false)
			var won: bool = final and scores[i] > scores[1 - i]
			var ink := FcUiTokens.TEXT if (won or not final) else FcUiTokens.TEXT_MUTED
			draw_string(body, Vector2(34, y + 15), str(s.get("abbr", "")), HORIZONTAL_ALIGNMENT_LEFT, 60, fs, ink)
			if final:
				draw_string(body, Vector2(size.x - 70, y + 15), str(scores[i]), HORIZONTAL_ALIGNMENT_RIGHT, 40, fs, FcUiTokens.PRIMARY if won else ink)
		var status := "Final" if final else "Upcoming"
		if str(data.get("note", "")) != "":
			status += " · " + str(data["note"])
		draw_string(body, Vector2(8, size.y - 6), status.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, FcUiTokens.fs(FcUiTokens.TYPE_MICRO), FcUiTokens.TEXT_MUTED)
