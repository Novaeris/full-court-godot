class_name FcTeamHeader
extends Control
## The franchise hero header (the HQ, a team page): a full-width band in the team's colour that fades into the background, a large crest,
## the team name in display type with a subtitle line (season, date, phase), and up to four stat pills on the right (record, rank,
## streak...). Drawn in one node; the pills are plain text so nothing depends on colour alone.

## {"look": Dictionary, "name": String, "subtitle": String, "eyebrow": String (small line above the name), "pills": [{"label", "value"}]}
var data: Dictionary = {}


func _init() -> void:
	custom_minimum_size = Vector2(480, 132)
	mouse_filter = Control.MOUSE_FILTER_PASS


func setup(header: Dictionary) -> FcTeamHeader:
	data = header
	var pills: Array = []
	for p in header.get("pills", []):
		pills.append("%s %s" % [p.get("label", ""), p.get("value", "")])
	tooltip_text = "%s. %s. %s" % [header.get("name", ""), header.get("subtitle", ""), ", ".join(pills)]
	queue_redraw()
	return self


func _draw() -> void:
	var look: Dictionary = data.get("look", {})
	var fill := Color(look.get("fill", FcUiTokens.SURFACE_HIGH))
	var trim := Color(look.get("trim", FcUiTokens.PRIMARY))
	var box := StyleBoxFlat.new()
	box.bg_color = FcUiTokens.SURFACE
	box.set_corner_radius_all(FcUiTokens.RADIUS_CARD)
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	# the team-colour band: strong at the crest, fading to the surface on the right (vertex colours, so it draws on the first frame)
	var solid := Color(fill.darkened(0.2), 0.95)
	var clear := Color(fill.darkened(0.55), 0.0)
	var knee := size.x * 0.55
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(knee, 0), Vector2(knee, size.y), Vector2(0, size.y)]), PackedColorArray([solid, Color(solid, 0.55), Color(solid, 0.55), solid]))
	draw_polygon(PackedVector2Array([Vector2(knee, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(knee, size.y)]), PackedColorArray([Color(solid, 0.55), clear, clear, Color(solid, 0.55)]))
	draw_rect(Rect2(Vector2(0, size.y - 4), Vector2(size.x, 4)), trim)
	var crest_px := clampf(size.y - 28.0, 56.0, 120.0)
	if not look.is_empty():
		FcTeamCrest.paint(self, Rect2(Vector2(18, (size.y - crest_px) / 2.0 - 2), Vector2(crest_px, crest_px)), look, true)
	var display := FcUiFonts.display(700)
	if display == null:
		display = ThemeDB.fallback_font
	var body := FcUiFonts.body(500)
	if body == null:
		body = ThemeDB.fallback_font
	var x := 36.0 + crest_px
	var name_fs := FcUiTokens.fs(FcUiTokens.TYPE_DISPLAY_XL)
	var small := FcUiTokens.fs(FcUiTokens.TYPE_SMALL)
	var top := size.y * 0.5 - name_fs * 0.5
	if str(data.get("eyebrow", "")) != "":
		draw_string(body, Vector2(x, top - 4), str(data["eyebrow"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, FcUiTokens.fs(FcUiTokens.TYPE_MICRO), Color(FcUiTokens.TEXT, 0.8))
	var pills: Array = data.get("pills", [])
	var pill_w := 112.0
	var pills_w := pill_w * pills.size()
	var name_w := maxf(120.0, size.x - x - pills_w - 24.0)
	draw_string(display, Vector2(x, top + name_fs * 0.82), str(data.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, name_w, name_fs, FcUiTokens.TEXT)
	draw_string(body, Vector2(x, top + name_fs + small + 6), str(data.get("subtitle", "")), HORIZONTAL_ALIGNMENT_LEFT, name_w, small, Color(FcUiTokens.TEXT, 0.82))
	var px := size.x - pills_w - 12.0
	var value_fs := FcUiTokens.fs(FcUiTokens.TYPE_H1)
	for p in pills:
		var pill := StyleBoxFlat.new()
		pill.bg_color = Color(FcUiTokens.BG, 0.55)
		pill.set_corner_radius_all(FcUiTokens.RADIUS_CONTROL)
		var pr := Rect2(Vector2(px + 4, size.y * 0.5 - 34), Vector2(pill_w - 8, 68))
		draw_style_box(pill, pr)
		draw_string(body, pr.position + Vector2(10, 18), str(p.get("label", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, pr.size.x - 16, FcUiTokens.fs(FcUiTokens.TYPE_MICRO), FcUiTokens.TEXT_MUTED)
		draw_string(display, pr.position + Vector2(10, 54), str(p.get("value", "")), HORIZONTAL_ALIGNMENT_LEFT, pr.size.x - 16, value_fs, FcUiTokens.TEXT)
		px += pill_w
