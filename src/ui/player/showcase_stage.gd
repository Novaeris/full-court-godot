class_name FcShowcaseStage
extends Control
## Shows a player on a stage: a spotlight in the team's colour, a pedestal, and the whole player standing on it. The player is drawn from
## the SAME resolved visual as everywhere else (FcPlayerVisual.resolve), so the showcase never disagrees with a list or a card.
## Poses: the stage asks the resolver which poses exist and uses the best available. Today that is only "idle" (a gentle bob); pose sprites
## (tier 3) and richer rendering such as a 3D model in a viewport (tier 4) are reserved slots behind this same interface and are NOT built,
## so nothing here depends on them. With reduced motion there is no bob.

var visual: Dictionary = {}
var subject: Dictionary = {}
var pose: String = "idle"
var bob: float = 0.0:
	set(v):
		bob = v
		queue_redraw()
var _tween: Tween = null


func _init() -> void:
	custom_minimum_size = Vector2(220, 300)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(player_subject: Dictionary, pixels_wide: int = 220) -> FcShowcaseStage:
	subject = player_subject
	visual = FcPlayerVisual.resolve(player_subject)
	custom_minimum_size = Vector2(pixels_wide, pixels_wide * 1.36)
	pose = "idle"
	queue_redraw()
	return self


## The poses available for this player (only "idle" until pose sprites exist).
func poses() -> Array:
	return visual.get("poses", ["idle"])


## Chooses a pose; an unavailable one falls back to "idle".
func set_pose(name: String) -> String:
	pose = name if name in poses() else "idle"
	queue_redraw()
	return pose


func _ready() -> void:
	_start_idle()


func _start_idle() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if FcMotion.reduced or not is_inside_tree():
		bob = 0.0
		return
	_tween = create_tween().set_loops()
	_tween.tween_property(self, "bob", 1.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "bob", 0.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _draw() -> void:
	if visual.is_empty():
		return
	var primary: Color = visual["uniform"]["primary"]
	# spotlight cone and glow behind the player
	draw_polygon(PackedVector2Array([Vector2(size.x * 0.5, 0), Vector2(size.x * 0.95, size.y * 0.9), Vector2(size.x * 0.05, size.y * 0.9)]), PackedColorArray([Color(primary.lightened(0.3), 0.14), Color(primary.lightened(0.3), 0.0), Color(primary.lightened(0.3), 0.0)]))
	draw_circle(Vector2(size.x / 2.0, size.y * 0.5), size.x * 0.42, Color(primary, 0.12))
	# the pedestal
	var base_y := size.y * 0.92
	draw_set_transform(Vector2(size.x / 2.0, base_y), 0.0, Vector2(1.0, 0.22))
	draw_circle(Vector2.ZERO, size.x * 0.4, Color(FcUiTokens.SURFACE_RAISED, 1.0))
	draw_circle(Vector2.ZERO, size.x * 0.4 - 3, Color(primary, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var lift := -4.0 * bob
	FcPlayerFigure.draw(self, Rect2(size.x * 0.18, size.y * 0.04 + lift, size.x * 0.64, size.y * 0.86), visual, true)
