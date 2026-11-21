class_name FcTeamCrest
extends Control
## A team's crest: a shape in the team colours with a rim, an inner trim line, an emblem and (when big enough) the team letters.
## Sizes: below 32 px only the shape, rim and emblem are drawn (a simplified mark that stays clear when tiny); from 40 px the inner trim
## line is added; from 64 px the abbreviation sits under the emblem. It asks FcTeamLook.resolve for the look, so one team is one
## crest in every table, header, score bug, bracket and card. `look` is the resolved description (tests compare it across screens).

var look: Dictionary = {}
var show_text: bool = true


func _init() -> void:
	custom_minimum_size = Vector2(32, 32)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## `team_subject` as in FcTeamLook (build it with FcTeamLook.subject / subject_for_team); an already resolved look is accepted too.
func setup(team_subject: Dictionary, pixels: int = 48, with_text: bool = true) -> FcTeamCrest:
	look = team_subject if team_subject.has("shape") else FcTeamLook.resolve(team_subject)
	show_text = with_text
	custom_minimum_size = Vector2(pixels, pixels)
	tooltip_text = str(look.get("city", "")) + (" " if str(look.get("city", "")) != "" else "") + str(look.get("nickname", ""))
	queue_redraw()
	return self


func _draw() -> void:
	if look.is_empty():
		return
	paint(self, Rect2(Vector2.ZERO, size), look, show_text)


## Draws a crest into `rect` on any canvas item (a table cell, a card, a custom control) without needing a node of its own.
static func paint(canvas: CanvasItem, rect: Rect2, team_look: Dictionary, with_text: bool = true) -> void:
	var pixels := minf(rect.size.x, rect.size.y)
	var center := rect.get_center()
	var r := pixels / 2.0 * 0.96
	var outline := FcTeamEmblems.shape_points(str(team_look["shape"]))
	var ink: Color = team_look["ink"]
	var fill: Color = team_look["fill"]
	canvas.draw_colored_polygon(_scaled(outline, center, r), ink)
	var rim := clampf(2.2 / maxf(r, 1.0) + 0.04, 0.07, 0.16)
	canvas.draw_colored_polygon(_scaled(outline, center, r * (1.0 - rim)), fill)
	if pixels >= 40.0:
		var line := _scaled(outline, center, r * 0.76)
		line.append(line[0])
		canvas.draw_polyline(line, team_look["trim"], maxf(1.0, pixels * 0.025), true)
	var text := str(team_look.get("abbreviation", ""))
	var with_letters := with_text and pixels >= 64.0 and text != ""
	var emblem_center := center + Vector2(0, -r * (0.2 if with_letters else 0.0))
	var emblem_radius := r * (0.4 if with_letters else (0.5 if pixels >= 40.0 else 0.58))
	FcTeamEmblems.draw(canvas, str(team_look["emblem"]), emblem_center, emblem_radius, ink, fill)
	if with_letters:
		var font := FcUiFonts.display(700)
		if font == null:
			font = ThemeDB.fallback_font
		var fs := int(r * 0.34)
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		canvas.draw_string(font, Vector2(center.x - width / 2.0, center.y + r * (0.5 if str(team_look["shape"]) == "banner" else 0.62)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


static func _scaled(pts: PackedVector2Array, center: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = center + pts[i] * r
	return out
