class_name FcCourtProjection
extends RefCounted
## Maps a point on the court (feet, the convention of FcCourtLayout: x along the 94 ft length, y across the 50 ft width, z up) to a point on
## the screen as a broadcast camera on the near sideline would see it (master plan B2b option B): the far sideline is narrower than the near
## one, depth goes up the screen, height lifts a point up. A fixed pseudo-perspective (no real 3D camera), pure maths, no nodes, so it can be
## tested without a window and reused by the 2D viewer today and any viewer later. The flat top-down view stays available (`flat = true`).
##
## A camera is {"focus": Vector2 (feet), "zoom": float}: the focus point is shown at the centre of the view and `zoom` 1.0 fits the whole court.

const COURT_LENGTH := FcCourtLayout.COURT_LENGTH
const COURT_WIDTH := FcCourtLayout.COURT_WIDTH
## How wide the far sideline is compared with the near one (1.0 would be flat).
const FAR_SCALE := 0.66
## How much of the view's height the court occupies at zoom 1 (the rest is room for the lifted ball and the graphic strip).
const COURT_HEIGHT_SHARE := 0.78
## Height in feet becomes this many court-feet of upward shift on the screen at the near sideline (scaled by depth like everything else).
const LIFT := 0.55
const MIN_ZOOM := 1.0
const MAX_ZOOM := 3.5

var view_size: Vector2 = Vector2(520, 280)
var flat: bool = false


func _init(size: Vector2 = Vector2(520, 280), flat_view: bool = false) -> void:
	view_size = size
	flat = flat_view


static func default_camera() -> Dictionary:
	return {"focus": Vector2(COURT_LENGTH / 2.0, COURT_WIDTH / 2.0), "zoom": 1.0}


## A camera clamped to something sensible: the zoom in range and the focus on the court.
static func clamp_camera(camera: Dictionary) -> Dictionary:
	var focus: Vector2 = camera.get("focus", Vector2(COURT_LENGTH / 2.0, COURT_WIDTH / 2.0))
	return {"focus": Vector2(clampf(focus.x, 0.0, COURT_LENGTH), clampf(focus.y, 0.0, COURT_WIDTH)), "zoom": clampf(float(camera.get("zoom", 1.0)), MIN_ZOOM, MAX_ZOOM)}


## How much a width at depth `y` is scaled (1.0 at the near sideline, FAR_SCALE at the far one; always 1.0 in the flat view).
func scale_at(y: float) -> float:
	if flat:
		return 1.0
	return lerpf(FAR_SCALE, 1.0, clampf(y / COURT_WIDTH, 0.0, 1.0))


## The screen point of court point (x, y) at height z feet, for `camera`.
func project(x: float, y: float, z: float = 0.0, camera: Dictionary = {}) -> Vector2:
	var cam := clamp_camera(camera if not camera.is_empty() else default_camera())
	var focus: Vector2 = cam["focus"]
	var zoom: float = cam["zoom"]
	return view_size / 2.0 + (_base(x, y, z) - _base(focus.x, focus.y, 0.0)) * zoom


## The court point (x, y) under a screen point, for a point on the floor (z = 0): the inverse of `project` for the floor.
func unproject(screen: Vector2, camera: Dictionary = {}) -> Vector2:
	var cam := clamp_camera(camera if not camera.is_empty() else default_camera())
	var focus: Vector2 = cam["focus"]
	var zoom: float = cam["zoom"]
	var base_point := (screen - view_size / 2.0) / zoom + _base(focus.x, focus.y, 0.0)
	var span := _base_height()
	var y := clampf((base_point.y - _base_top()) / span * COURT_WIDTH, 0.0, COURT_WIDTH)
	var x := (base_point.x - view_size.x / 2.0) / (_feet_to_pixels() * scale_at(y)) + COURT_LENGTH / 2.0
	return Vector2(x, y)


## The four corners of the floor on the screen, far-left, far-right, near-right, near-left.
func corners(camera: Dictionary = {}) -> PackedVector2Array:
	return PackedVector2Array([project(0.0, 0.0, 0.0, camera), project(COURT_LENGTH, 0.0, 0.0, camera), project(COURT_LENGTH, COURT_WIDTH, 0.0, camera), project(0.0, COURT_WIDTH, 0.0, camera)])


## A drawing size in pixels for something `feet` long on the floor at depth `y` (a player's radius, the ball).
func pixels_at(feet: float, y: float, camera: Dictionary = {}) -> float:
	var cam := clamp_camera(camera if not camera.is_empty() else default_camera())
	return feet * _feet_to_pixels() * scale_at(y) * float(cam["zoom"])


# --- the fixed base view (before the camera's pan and zoom) -----------------------------------------------------------------

## Pixels per foot along the length at the near sideline, so the near edge fits the view width at zoom 1.
func _feet_to_pixels() -> float:
	return view_size.x / COURT_LENGTH


func _base_height() -> float:
	return view_size.y * COURT_HEIGHT_SHARE if not flat else minf(view_size.y, view_size.x * COURT_WIDTH / COURT_LENGTH)


func _base_top() -> float:
	return (view_size.y - _base_height()) * 0.55


func _base(x: float, y: float, z: float) -> Vector2:
	var depth := clampf(y, 0.0, COURT_WIDTH) / COURT_WIDTH
	var sx := view_size.x / 2.0 + (x - COURT_LENGTH / 2.0) * _feet_to_pixels() * scale_at(y)
	var sy := _base_top() + depth * _base_height()
	sy -= z * LIFT * _feet_to_pixels() * scale_at(y)
	return Vector2(sx, sy)
