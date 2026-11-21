class_name FcPlayerPortrait
extends Control
## A player's picture in a list, a card, a post-game line, a trade or a comparison: the head-and-shoulders figure (or portrait art, or
## the monogram) in a rounded frame in the team's colour. It asks FcPlayerVisual.resolve for the look, like every other place a player
## appears, so one player is one face everywhere. `visual` is the resolved description (tests compare it across screens).

var visual: Dictionary = {}
var subject: Dictionary = {}
## "bust" (head and shoulders, the default) or "head" (cropped to the head, for small row portraits).
var crop: String = "bust"


func _init() -> void:
	custom_minimum_size = Vector2(48, 48)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## `subject` as in FcPlayerVisual.resolve (build it with FcPlayerPresentation, never by hand in a screen).
func setup(player_subject: Dictionary, pixels: int = 48, portrait_crop: String = "bust") -> FcPlayerPortrait:
	subject = player_subject
	crop = portrait_crop
	clip_contents = true
	visual = FcPlayerVisual.resolve(player_subject)
	custom_minimum_size = Vector2(pixels, pixels)
	tooltip_text = str(player_subject.get("name", ""))
	queue_redraw()
	return self


func _draw() -> void:
	if visual.is_empty():
		return
	var uniform: Dictionary = visual["uniform"]
	var well := StyleBoxFlat.new()
	well.bg_color = Color(uniform["primary"]).darkened(0.55)
	well.set_corner_radius_all(int(size.x * 0.18))
	draw_style_box(well, Rect2(Vector2.ZERO, size))
	# the figure is clipped to the frame by drawing it inside a slightly smaller rectangle
	var inner := Rect2(Vector2(size.x * 0.06, size.y * 0.1), size * Vector2(0.88, 0.9))
	if crop == "head":
		FcPlayerFigure.draw_headshot(self, Rect2(Vector2(size.x * 0.04, size.y * 0.04), size * Vector2(0.92, 0.92)), visual)
	else:
		FcPlayerFigure.draw(self, inner, visual)
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = uniform["primary"]
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(int(size.x * 0.18))
	draw_style_box(ring, Rect2(Vector2.ZERO, size))
