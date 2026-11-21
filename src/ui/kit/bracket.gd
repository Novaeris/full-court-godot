class_name FcBracket
extends Control
## A tournament bracket drawn as columns of matches joined by connector lines: each match is a box with its two sides, the winner marked with a
## check and the loser dimmed, the score, and an accent edge for the match you are in. The rounds come from FcDynastyTournament.bracket_view
## (or any list of {"round_name", "matches": [{"a", "b", "score", "winner", "played", "you"}]}); it draws exactly those and invents nothing.
## On touch layouts `build()` returns a stack of match panels instead (a wide drawing does not fit a phone). Everything is also available as
## text (`summary()`, the tooltip) so the picture is never the only carrier of meaning.

const BOX_W := 176.0
const BOX_H := 56.0
const GAP_X := 44.0
const GAP_Y := 14.0
const TITLE_H := 28.0

var rounds: Array = []
var _centers: Array = []


func _init(round_list: Array = []) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_rounds(round_list)


## The bracket as a drawing on wide layouts, or a stack of match panels when `compact` (touch layouts).
static func build(round_list: Array, compact: bool = false) -> Control:
	if not compact:
		return FcBracket.new(round_list)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	for round_view in round_list:
		stack.add_child(FcUiTables.label(str(round_view["round_name"]), FcUiTokens.TYPE_H3, true))
		for m in round_view["matches"]:
			var panel := FcPanel.new("", FcPanel.Variant.FLAT if not bool(m.get("you", false)) else FcPanel.Variant.RAISED)
			if bool(m.get("you", false)):
				panel.set_accent(FcUiTheme.accent)
			for side in ["a", "b"]:
				var mark := "✓ " if bool(m.get("played", false)) and str(m.get("winner", "")) == str(m[side]) else ""
				panel.add(FcUiTables.label(mark + str(m[side]), FcUiTokens.TYPE_BODY))
			if str(m.get("score", "")) != "":
				var score := FcUiTables.label(str(m["score"]), FcUiTokens.TYPE_SMALL)
				score.theme_type_variation = "MutedLabel"
				panel.add(score)
			stack.add_child(panel)
	return stack


func set_rounds(round_list: Array) -> void:
	rounds = round_list
	_layout()
	tooltip_text = summary()
	queue_redraw()


## Every match in words: "Semifinal: Harbor vs Sky (84-79), winner Harbor".
func summary() -> String:
	var lines: Array = []
	for round_view in rounds:
		for m in round_view["matches"]:
			var line := "%s: %s vs %s" % [round_view["round_name"], m["a"], m["b"]]
			if str(m.get("score", "")) != "":
				line += " (%s)" % str(m["score"])
			if bool(m.get("played", false)) and str(m.get("winner", "")) != "":
				line += ", winner %s" % str(m["winner"])
			lines.append(line)
	return "\n".join(lines)


func match_count() -> int:
	var n := 0
	for round_view in rounds:
		n += (round_view["matches"] as Array).size()
	return n


## The vertical centre of every match box: the first round stacks, later rounds sit between the two matches that feed them.
func _layout() -> void:
	_centers = []
	var height := 0.0
	for r in rounds.size():
		var matches: Array = rounds[r]["matches"]
		var col: Array = []
		for i in matches.size():
			var y: float
			if r == 0 or _centers[r - 1].is_empty():
				y = TITLE_H + BOX_H / 2.0 + float(i) * (BOX_H + GAP_Y)
			else:
				var prev: Array = _centers[r - 1]
				var a := 2 * i
				var b := 2 * i + 1
				if b < prev.size():
					y = (float(prev[a]) + float(prev[b])) / 2.0
				elif a < prev.size():
					y = float(prev[a])
				else:
					y = TITLE_H + BOX_H / 2.0 + float(i) * (BOX_H + GAP_Y)
			col.append(y)
			height = maxf(height, y + BOX_H / 2.0)
		_centers.append(col)
	custom_minimum_size = Vector2(maxf(0.0, float(rounds.size()) * (BOX_W + GAP_X) - GAP_X), height + 4.0)


func _draw() -> void:
	if rounds.is_empty():
		return
	var font := get_theme_font("font", "Label")
	var fs := FcUiTokens.fs(FcUiTokens.TYPE_SMALL)
	var check := FcUiIcons.texture("check")
	for r in rounds.size():
		var x := float(r) * (BOX_W + GAP_X)
		var title := str(rounds[r]["round_name"])
		draw_string(font, Vector2(x, TITLE_H - 10.0), title, HORIZONTAL_ALIGNMENT_LEFT, BOX_W, fs, FcUiTokens.GOLD)
		var matches: Array = rounds[r]["matches"]
		for i in matches.size():
			var cy: float = _centers[r][i]
			if r > 0:   # the join from the two feeding matches into this one
				var prev: Array = _centers[r - 1]
				var mid_x := x - GAP_X / 2.0
				var line := FcUiTokens.BORDER
				for feed in [2 * i, 2 * i + 1]:
					if feed < prev.size():
						draw_line(Vector2(x - GAP_X, float(prev[feed])), Vector2(mid_x, float(prev[feed])), line, 2.0)
						draw_line(Vector2(mid_x, float(prev[feed])), Vector2(mid_x, cy), line, 2.0)
				draw_line(Vector2(mid_x, cy), Vector2(x, cy), line, 2.0)
			_draw_match(matches[i], Rect2(x, cy - BOX_H / 2.0, BOX_W, BOX_H), font, fs, check)


func _draw_match(m: Dictionary, rect: Rect2, font: Font, fs: int, check: Texture2D) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = FcUiTokens.SURFACE_RAISED
	box.border_color = FcUiTheme.accent if bool(m.get("you", false)) else FcUiTokens.BORDER
	box.set_border_width_all(2 if bool(m.get("you", false)) else 1)
	box.set_corner_radius_all(FcUiTokens.RADIUS_CONTROL)
	draw_style_box(box, rect)
	var played := bool(m.get("played", false))
	var winner := str(m.get("winner", ""))
	for k in 2:
		var side := str(m["a"] if k == 0 else m["b"])
		var won := played and winner == side
		var color := FcUiTokens.TEXT if (won or not played) else FcUiTokens.TEXT_MUTED
		var y := rect.position.y + 20.0 + float(k) * 20.0
		draw_string(font, Vector2(rect.position.x + 10.0, y), side, HORIZONTAL_ALIGNMENT_LEFT, BOX_W - 56.0, fs, color)
		if won and check != null:
			draw_texture_rect(check, Rect2(rect.end.x - 24.0, y - 13.0, 14.0, 14.0), false, FcUiTokens.SUCCESS)
	var score := str(m.get("score", ""))
	if score != "":
		draw_string(font, Vector2(rect.end.x - 10.0 - font.get_string_size(score, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2).x, rect.end.y - 4.0), score, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, FcUiTokens.TEXT_MUTED)
