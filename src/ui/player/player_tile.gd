class_name FcPlayerTile
extends Control
## The Owner and Career player card: a portrait tile in one node (so a roster of 15 or a draft board of 60 is cheap), the same size family
## as the Dynasty collectible cards (SMALL 112x160 and MEDIUM 150x214 match FcCardFace). It shows the player's figure from the SAME resolved
## visual as everywhere else, the name, position and team letters, and the rating in the rating-tier colour (data/ui/rating_tiers.json).
## Owner and Career never use rarity: rarity is a collectible idea, a rating tier is a performance idea (the two colour sets stay apart).
## It is a view of a presentation dictionary (FcPlayerPresentation); it changes nothing.

signal activated

const SIZE_SMALL := Vector2(112, 160)
const SIZE_MEDIUM := Vector2(150, 214)

var vm: Dictionary = {}
var visual: Dictionary = {}
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()
var _hover := false


func _init() -> void:
	custom_minimum_size = SIZE_SMALL
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


## `view_model` is a FcPlayerPresentation dictionary (needs subject, name, position, overall; team is optional).
func setup(view_model: Dictionary, tile_size: Vector2 = SIZE_SMALL) -> FcPlayerTile:
	vm = view_model
	visual = FcPlayerVisual.resolve(view_model["subject"])
	custom_minimum_size = tile_size
	tooltip_text = "%s, %s, %d overall" % [str(vm.get("name", "?")), str(vm.get("position", "")), int(vm.get("overall", 0))]
	queue_redraw()
	return self


func _set_hover(on: bool) -> void:
	_hover = on
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		activated.emit()
	elif event.is_action_pressed("ui_accept") and has_focus():
		accept_event()
		activated.emit()


func _draw() -> void:
	if vm.is_empty():
		return
	var s := size.x / 150.0   # everything is designed at 150 px wide and scaled
	var overall := int(vm.get("overall", 0))
	var tier := FcRatingBadge.tier_color(overall)
	var frame := StyleBoxFlat.new()
	frame.bg_color = FcUiTokens.SURFACE_RAISED
	frame.border_color = FcUiTokens.INFO if selected else tier
	frame.set_border_width_all(3 if (selected or has_focus()) else 2)
	frame.set_corner_radius_all(int(12 * s))
	FcUiTokens.elevate(frame, 2 if _hover else 1)
	draw_style_box(frame, Rect2(Vector2.ZERO, size))
	# the figure on a team-colour well with a soft light behind it
	var uniform: Dictionary = visual["uniform"]
	var art := Rect2(Vector2(6, 6) * s, Vector2(size.x - 12 * s, size.y * 0.62))
	var well := StyleBoxFlat.new()
	well.bg_color = Color(uniform["primary"]).darkened(0.55)
	well.set_corner_radius_all(int(8 * s))
	draw_style_box(well, art)
	draw_circle(art.get_center() + Vector2(0, art.size.y * 0.1), art.size.x * 0.42, Color(uniform["primary"], 0.28))
	FcPlayerFigure.draw(self, Rect2(art.position + Vector2(art.size.x * 0.06, art.size.y * 0.04), art.size * Vector2(0.88, 0.96)), visual)
	# the rating, top left, in its tier colour
	var badge := StyleBoxFlat.new()
	badge.bg_color = FcUiTokens.BG
	badge.border_color = tier
	badge.set_border_width_all(2)
	badge.set_corner_radius_all(int(8 * s))
	draw_style_box(badge, Rect2(Vector2(10, 10) * s, Vector2(40, 30) * s))
	var display := FcUiFonts.display(700)
	if display == null:
		display = ThemeDB.fallback_font
	var fs := int(24 * s)
	var num := str(overall)
	var w := display.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(display, Vector2(10 * s + (40 * s - w) / 2.0, 10 * s + 25 * s), num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tier)
	# name, then position and team
	var body := FcUiFonts.body(600)
	if body == null:
		body = ThemeDB.fallback_font
	var name_fs := int(15 * s)
	draw_string(display, Vector2(10 * s, art.end.y + 22 * s), _fit(str(vm.get("name", "?")), display, name_fs, size.x - 20 * s), HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs, FcUiTokens.TEXT)
	var pos := str(vm.get("position", ""))
	if str(vm.get("secondary", "")) != "":
		pos += "/" + str(vm["secondary"])
	var team := str(vm.get("team", {}).get("abbreviation", "")) if vm.get("team") is Dictionary else ""
	var line := pos if team == "" else "%s  ·  %s" % [pos, team]
	var small_fs := int(11 * s)
	draw_string(body, Vector2(10 * s, art.end.y + 38 * s), _fit(line, body, small_fs, size.x - 20 * s), HORIZONTAL_ALIGNMENT_LEFT, -1, small_fs, FcUiTokens.TEXT_MUTED)


## `text` shortened with an ellipsis until it fits `width` pixels at font size `fs`.
static func _fit(text: String, font: Font, fs: int, width: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width:
		return text
	var out := text
	while out.length() > 1 and font.get_string_size(out + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		out = out.substr(0, out.length() - 1)
	return out + "…"
