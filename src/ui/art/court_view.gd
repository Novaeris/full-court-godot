class_name FcCourtView
extends Control
## The replay court, drawn in code: the floor and lines, ten players and the ball, and a short move from the last event to this one.
## It is an ILLUSTRATION driven by the event kinds (the simulation has no real positions, see FcCourtLayout): a made three is shown
## from beyond the arc, a rebound near the basket, and so on. Drawn pictures live in src/ui/art, which the style lint exempts, so the
## floor and line colours are literals here.
##
## Reduced motion: events are shown at once with no movement (FcMotion.tween_property finishes instantly).
##
## Two views (master plan B2b option B): the BROADCAST view (default) draws the same court through FcCourtProjection as a sideline camera sees
## it, with the home team's colour on the paint and its abbreviation at centre court, depth-sorted players and a camera (FcCameraRig) that
## the replay screen drives with the director's shots and the person can pan (drag) and zoom (wheel). The FLAT view is the original top-down
## drawing and stays selectable. Both draw the same illustrative positions: nothing here is tracked play.

const FLOOR := Color("B87A43")
const FLOOR_DARK := Color("A5693A")
const LINE := Color("F4EBDD")
const BALL := Color("F28A2E")
const BALL_EDGE := Color("5A2B0C")
const MOVE_SECONDS := 0.45

signal camera_moved_by_hand

## true = the projected broadcast view, false = the flat top-down view.
var broadcast_view: bool = true
var rig := FcCameraRig.new()
var home_abbreviation: String = ""
var _projection := FcCourtProjection.new()
var _dragging: bool = false

const TRAIL_MAX := 10
## The ball's recent positions (court feet), oldest first, at most TRAIL_MAX: drawn as a fading line. These are the replay's illustrative
## positions (the simulation has no tracked ball), so the trail is an illustration of the recent play, not a tracked path.
var show_trail: bool = true
var _trail: Array[Vector2] = []

## Team colours: [home, away].
var colors: Array = [Color("39A9FF"), Color("FF8A24")]
## Progress of the current event's move, 0 to 1 (animated).
var progress: float = 1.0:
	set(value):
		progress = value
		queue_redraw()
## The current event's state (FcReplayModel.state_at) and the names to print under each player.
var state: Dictionary = {}
var names: Dictionary = {}

var _from: Dictionary = {}     # player id -> Vector2 (feet) where he was
var _to: Dictionary = {}       # where he is going
var _sides: Dictionary = {}    # player id -> 0/1
var _ball_from: Vector2 = Vector2(47, 25)
var _ball_to: Vector2 = Vector2(47, 25)
var _ball_arc: float = 0.0     # how high the ball flies on this move, in feet
var _hoop_flash: float = 0.0
var _flash_right: bool = true
var _marks: Dictionary = {}    # player id -> "foul" | "in" | "hurt" | "shooter"


func _init() -> void:
	custom_minimum_size = Vector2(320, 170)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process(true)


## Shows event `new_state`. With `animate` the players and the ball glide there; otherwise they jump.
func show_state(new_state: Dictionary, player_names: Dictionary, animate: bool = true) -> void:
	names = player_names
	var previous := _current_positions()
	var previous_ball := _ball_position()
	state = new_state
	if state.is_empty():
		queue_redraw()
		return
	_layout_event()
	_from = previous if animate and not previous.is_empty() else _to.duplicate()
	for id in _to:
		if not _from.has(id):
			_from[id] = _to[id]
	_ball_from = previous_ball if animate else _ball_to
	if animate:
		progress = 0.0
		FcMotion.tween_property(self, "progress", 1.0, MOVE_SECONDS)
	else:
		progress = 1.0
	_hoop_flash = 1.0 if int(state["entry"]["type"]) == FcGameEventLog.EV_SHOT_MADE else 0.0
	queue_redraw()


## Where each player is drawn right now (feet), mid-move included.
func _current_positions() -> Dictionary:
	var out := {}
	for id in _to:
		var a: Vector2 = _from.get(id, _to[id])
		out[id] = a.lerp(_to[id], _ease(progress))
	return out


func _ball_position() -> Vector2:
	return _ball_from.lerp(_ball_to, _ease(progress))


static func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


# --- what this event looks like ----------------------------------------------------------------------------------

func _layout_event() -> void:
	var entry: Dictionary = state["entry"]
	var type: int = entry["type"]
	var offense: int = state["offense_side"]
	var period: int = state["period"]
	# a defensive rebound belongs to the possession that just ended: draw it at the basket that was being attacked
	if type == FcGameEventLog.EV_REBOUND and int(entry["x"]) == 0:
		offense = 1 - offense
	var right := FcCourtLayout.attacks_right(offense, period)
	var shape := FcCourtLayout.formation(right)
	_to = {}
	_sides = {}
	_marks = {}
	var order: Array = []
	for side in 2:
		order.append(FcCourtLayout.order_by_position(state["on_court"][side], state["positions"]))
	for slot in 5:
		var o_id = order[offense][slot] if slot < order[offense].size() else null
		var d_id = order[1 - offense][slot] if slot < order[1 - offense].size() else null
		if o_id != null:
			_to[o_id] = shape["offense"][slot]
			_sides[o_id] = offense
		if d_id != null:
			_to[d_id] = shape["defense"][slot]
			_sides[d_id] = 1 - offense
	var hoop := FcCourtLayout.basket(right)
	var a: int = entry["a"]
	var b: int = entry["b"]
	var handler = _first_of(order[offense], 0)   # a player id, or 0 when nobody is listed
	var ball := _to.get(handler, Vector2(47, 25)) as Vector2
	_ball_arc = 0.0
	_flash_right = right
	match type:
		FcGameEventLog.EV_SHOT_MADE, FcGameEventLog.EV_SHOT_MISSED, FcGameEventLog.EV_SHOT_BLOCKED:
			var spot := FcCourtLayout.shot_spot(int(entry["x"]), int(entry["index"]), right)
			_to[a] = spot
			_sides[a] = int(entry["side"])
			_marks[a] = "shooter"
			if type == FcGameEventLog.EV_SHOT_BLOCKED:
				_to[b] = spot.lerp(hoop, 0.2)
				_ball_arc = 2.0
				ball = spot.lerp(hoop, 0.2)
			else:
				_ball_arc = 9.0 if int(entry["x"]) != FcGameEventLog.SHOT_RIM else 4.0
				ball = hoop if type == FcGameEventLog.EV_SHOT_MADE else hoop + Vector2(-2.5 if right else 2.5, 1.5)
		FcGameEventLog.EV_FREE_THROW:
			var line := Vector2(hoop.x + (-15.0 if right else 15.0), 25.0)
			_to[a] = line
			_sides[a] = int(entry["side"])
			_marks[a] = "shooter"
			_ball_arc = 7.0
			ball = hoop
		FcGameEventLog.EV_REBOUND:
			if a != 0:
				var near := hoop + Vector2(-3.0 if right else 3.0, (FcCourtLayout.unit(int(entry["index"]), 5) - 0.5) * 8.0)
				if int(entry["x"]) == 0:
					near = FcCourtLayout.basket(FcCourtLayout.attacks_right(offense, period)) + Vector2(-3.0 if right else 3.0, 2.0)
				_to[a] = near
				ball = near
		FcGameEventLog.EV_TURNOVER:
			var thief: int = b if b != 0 else int(_first_of(order[1 - offense], 0))
			ball = _to.get(thief, ball) as Vector2
			_marks[a] = "foul"   # the player who lost the ball is ringed in the warning colour
		FcGameEventLog.EV_FOUL:
			_marks[a] = "foul"
		FcGameEventLog.EV_SUBSTITUTION:
			_marks[a] = "in"
		FcGameEventLog.EV_INJURY:
			_marks[a] = "hurt"
	_ball_to = ball
	_remember_ball(ball)


static func _first_of(list: Array, index: int) -> Variant:
	return list[index] if index < list.size() else 0


# --- drawing -----------------------------------------------------------------------------------------------------------------

func _draw() -> void:
	if broadcast_view:
		_draw_broadcast()
		return
	_draw_flat()


func _draw_flat() -> void:
	var scale_px := minf(size.x / FcCourtLayout.COURT_LENGTH, size.y / FcCourtLayout.COURT_WIDTH)
	var origin := (size - Vector2(FcCourtLayout.COURT_LENGTH, FcCourtLayout.COURT_WIDTH) * scale_px) / 2.0
	_draw_floor(origin, scale_px)
	if state.is_empty():
		return
	_draw_trail({})
	var current := _current_positions()
	var font := ThemeDB.fallback_font
	var radius := 1.9 * scale_px
	var font_px := clampi(roundi(1.7 * scale_px), 9, 15)
	for id in current:
		var spot: Vector2 = origin + (current[id] as Vector2) * scale_px
		var side: int = _sides.get(id, 0)
		var color: Color = colors[side]
		draw_circle(spot, radius, color)
		var mark: String = _marks.get(id, "")
		var ring := FcUiTokens.TEXT if mark == "shooter" else (FcUiTokens.WARNING if mark == "foul" else (FcUiTokens.DANGER if mark == "hurt" else (FcUiTokens.SUCCESS if mark == "in" else Color(0, 0, 0, 0.45))))
		draw_arc(spot, radius, 0.0, TAU, 28, ring, 2.5 if mark != "" else 1.5, true)
		var text := str(names.get(id, "?"))
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
		draw_string(font, spot + Vector2(-width / 2.0, radius + font_px + 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, LINE)
	_draw_ball(origin, scale_px)


# --- the broadcast view ------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	rig.reduced = FcMotion.reduced
	if rig.advance(delta) and broadcast_view:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not broadcast_view or rig.mode == FcCameraRig.Mode.AUTO:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			rig.manual_move(Vector2.ZERO, 1.15)
			camera_moved_by_hand.emit()
			accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			rig.manual_move(Vector2.ZERO, 1.0 / 1.15)
			camera_moved_by_hand.emit()
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_projection.view_size = size
		var cam := rig.camera()
		var before := _projection.unproject(motion.position - motion.relative, cam)
		var after := _projection.unproject(motion.position, cam)
		rig.manual_move(before - after, 1.0)   # drag the court under the pointer
		camera_moved_by_hand.emit()
		accept_event()


## The ball's recent path, oldest first (at most TRAIL_MAX points).
func trail_points() -> Array[Vector2]:
	return _trail.duplicate()


func _remember_ball(at: Vector2) -> void:
	if not _trail.is_empty() and _trail[_trail.size() - 1].is_equal_approx(at):
		return
	_trail.append(at)
	while _trail.size() > TRAIL_MAX:
		_trail.pop_front()


## Forgets the path (after a jump or a scrub, where the earlier positions are no longer "just before").
func clear_trail() -> void:
	_trail.clear()
	queue_redraw()


func _draw_trail(cam: Dictionary) -> void:
	if not show_trail or _trail.size() < 2:
		return
	for i in range(1, _trail.size()):
		var a := _trail[i - 1]
		var b := _trail[i]
		var fade := float(i) / float(_trail.size())
		var from_point := _pp(a.x, a.y, 3.0, cam) if broadcast_view else _flat_point(a)
		var to_point := _pp(b.x, b.y, 3.0, cam) if broadcast_view else _flat_point(b)
		draw_line(from_point, to_point, Color(BALL.r, BALL.g, BALL.b, 0.15 + 0.6 * fade), 1.5 + 2.0 * fade, true)


func _flat_point(feet: Vector2) -> Vector2:
	var scale_px := minf(size.x / FcCourtLayout.COURT_LENGTH, size.y / FcCourtLayout.COURT_WIDTH)
	var origin := (size - Vector2(FcCourtLayout.COURT_LENGTH, FcCourtLayout.COURT_WIDTH) * scale_px) / 2.0
	return origin + feet * scale_px


func set_flat(flat: bool) -> void:
	broadcast_view = not flat
	queue_redraw()


func _draw_broadcast() -> void:
	_projection.view_size = size
	var cam := rig.camera()
	var corners := _projection.corners(cam)
	draw_rect(Rect2(Vector2.ZERO, size), Color("0E1626"))   # the arena beyond the sidelines
	draw_colored_polygon(corners, FLOOR)
	for i in range(0, 10, 2):   # floorboards: every other tenth of the length a shade darker
		var x0 := FcCourtLayout.COURT_LENGTH * i / 10.0
		var x1 := FcCourtLayout.COURT_LENGTH * (i + 1) / 10.0
		draw_colored_polygon(PackedVector2Array([_pp(x0, 0, 0, cam), _pp(x1, 0, 0, cam), _pp(x1, FcCourtLayout.COURT_WIDTH, 0, cam), _pp(x0, FcCourtLayout.COURT_WIDTH, 0, cam)]), FLOOR_DARK)
	var branding: Color = colors[0]
	for right in [false, true]:   # the home team's colour in both paints, and its mark at centre court
		var base_x := FcCourtLayout.COURT_LENGTH if right else 0.0
		var dir := -1.0 if right else 1.0
		var paint := PackedVector2Array([_pp(base_x, 17, 0, cam), _pp(base_x + dir * 19.0, 17, 0, cam), _pp(base_x + dir * 19.0, 33, 0, cam), _pp(base_x, 33, 0, cam)])
		draw_colored_polygon(paint, Color(branding.r, branding.g, branding.b, 0.45))
	_draw_centre_mark(cam, branding)
	_line_loop([Vector2(0, 0), Vector2(FcCourtLayout.COURT_LENGTH, 0), Vector2(FcCourtLayout.COURT_LENGTH, FcCourtLayout.COURT_WIDTH), Vector2(0, FcCourtLayout.COURT_WIDTH)], cam, 2.0)
	_line_path([Vector2(FcCourtLayout.COURT_LENGTH / 2.0, 0), Vector2(FcCourtLayout.COURT_LENGTH / 2.0, FcCourtLayout.COURT_WIDTH)], cam, 2.0)
	for right in [false, true]:
		_draw_end(right, cam)
	if state.is_empty():
		return
	_draw_trail(cam)
	var current := _current_positions()
	var ordered: Array = current.keys()
	ordered.sort_custom(func(a, b) -> bool: return (current[a] as Vector2).y < (current[b] as Vector2).y)   # far players first, so near ones cover them
	var font := ThemeDB.fallback_font
	for id in ordered:
		var at: Vector2 = current[id]
		var side: int = _sides.get(id, 0)
		var radius := _projection.pixels_at(1.9, at.y, cam)
		var feet := _pp(at.x, at.y, 0.0, cam)
		draw_set_transform(feet, 0.0, Vector2(1.0, 0.35))
		draw_circle(Vector2.ZERO, radius, Color(0, 0, 0, 0.3))   # the shadow, flattened
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var body := _pp(at.x, at.y, 3.0, cam)
		draw_circle(body, radius, colors[side])
		var mark: String = _marks.get(id, "")
		var ring := FcUiTokens.TEXT if mark == "shooter" else (FcUiTokens.WARNING if mark == "foul" else (FcUiTokens.DANGER if mark == "hurt" else (FcUiTokens.SUCCESS if mark == "in" else Color(0, 0, 0, 0.45))))
		draw_arc(body, radius, 0.0, TAU, 28, ring, 2.5 if mark != "" else 1.5, true)
		var font_px := clampi(roundi(radius * 0.9), 9, 15)
		var text := str(names.get(id, "?"))
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
		draw_string(font, body + Vector2(-width / 2.0, radius + font_px + 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, LINE)
	var t := _ease(progress)
	var ball := _ball_position()
	var lift := sin(t * PI) * _ball_arc
	var ball_screen := _pp(ball.x, ball.y, 3.0 + lift, cam)
	var ball_radius := _projection.pixels_at(0.95, ball.y, cam)
	draw_circle(_pp(ball.x, ball.y, 0.0, cam), ball_radius * 0.8, Color(0, 0, 0, 0.25))
	draw_circle(ball_screen, ball_radius, BALL)
	draw_arc(ball_screen, ball_radius, 0.0, TAU, 20, BALL_EDGE, 1.5, true)
	if _hoop_flash > 0.0 and progress > 0.6:
		var hoop := FcCourtLayout.basket(_flash_right)
		draw_arc(_pp(hoop.x, hoop.y, 10.0, cam), _projection.pixels_at(2.4, hoop.y, cam), 0.0, TAU, 28, FcUiTokens.GOLD, 3.0, true)


func _pp(x: float, y: float, z: float, cam: Dictionary) -> Vector2:
	return _projection.project(x, y, z, cam)


func _line_path(points: Array, cam: Dictionary, width: float) -> void:
	var out := PackedVector2Array()
	for p in points:
		out.append(_pp((p as Vector2).x, (p as Vector2).y, 0.0, cam))
	draw_polyline(out, LINE, width, true)


func _line_loop(points: Array, cam: Dictionary, width: float) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	_line_path(closed, cam, width)


func _arc_points(centre: Vector2, radius: float, from_angle: float, to_angle: float, steps: int) -> Array:
	var out: Array = []
	for i in steps + 1:
		var a := lerpf(from_angle, to_angle, float(i) / steps)
		var p := centre + Vector2.from_angle(a) * radius
		out.append(Vector2(clampf(p.x, 0.0, FcCourtLayout.COURT_LENGTH), clampf(p.y, 0.0, FcCourtLayout.COURT_WIDTH)))
	return out


## The corners of a circle as a fillable polygon (court feet): `steps` distinct points, never the first one again at the end. A full-circle arc
## repeats its start point, and a polygon with a repeated vertex cannot be triangulated (the engine logged "Invalid polygon data" on every frame).
static func circle_polygon(centre: Vector2, radius: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in maxi(3, steps):
		out.append(centre + Vector2.from_angle(TAU * k / maxi(3, steps)) * radius)
	return out


func _draw_centre_mark(cam: Dictionary, branding: Color) -> void:
	var centre := Vector2(FcCourtLayout.COURT_LENGTH / 2.0, FcCourtLayout.COURT_WIDTH / 2.0)
	var ring := _arc_points(centre, 6.0, 0.0, TAU, 40)
	var polygon := PackedVector2Array()
	for p in circle_polygon(centre, 6.0, 40):
		polygon.append(_pp(p.x, p.y, 0.0, cam))
	draw_colored_polygon(polygon, Color(branding.r, branding.g, branding.b, 0.3))
	_line_path(ring, cam, 2.0)
	if home_abbreviation != "":
		var font := ThemeDB.fallback_font
		var px := clampi(roundi(_projection.pixels_at(4.0, centre.y, cam)), 10, 40)
		var at := _pp(centre.x, centre.y, 0.0, cam)
		var width := font.get_string_size(home_abbreviation, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_string(font, at + Vector2(-width / 2.0, px * 0.35), home_abbreviation, HORIZONTAL_ALIGNMENT_LEFT, -1, px, LINE)


func _draw_end(right: bool, cam: Dictionary) -> void:
	var length := FcCourtLayout.COURT_LENGTH
	var width := FcCourtLayout.COURT_WIDTH
	var dir := -1.0 if right else 1.0
	var base_x := length if right else 0.0
	var hoop := FcCourtLayout.basket(right)
	_line_loop([Vector2(base_x, width / 2.0 - 8.0), Vector2(base_x + dir * 19.0, width / 2.0 - 8.0), Vector2(base_x + dir * 19.0, width / 2.0 + 8.0), Vector2(base_x, width / 2.0 + 8.0)], cam, 1.5)
	_line_path(_arc_points(Vector2(base_x + dir * 19.0, width / 2.0), 6.0, 0.0, TAU, 32), cam, 1.5)
	_line_path(_arc_points(hoop, 4.0, -PI / 2.0 if not right else PI / 2.0, PI / 2.0 if not right else 3.0 * PI / 2.0, 16), cam, 1.5)
	var corner_x := sqrt(FcCourtLayout.THREE_POINT_DISTANCE * FcCourtLayout.THREE_POINT_DISTANCE - FcCourtLayout.CORNER_THREE_DISTANCE * FcCourtLayout.CORNER_THREE_DISTANCE)
	var arc_half := asin(FcCourtLayout.CORNER_THREE_DISTANCE / FcCourtLayout.THREE_POINT_DISTANCE)
	var run_end := hoop.x + dir * corner_x
	for y in [3.0, width - 3.0]:
		_line_path([Vector2(base_x, y), Vector2(run_end, y)], cam, 1.5)
	var centre_angle := PI if right else 0.0
	_line_path(_arc_points(hoop, FcCourtLayout.THREE_POINT_DISTANCE, centre_angle - arc_half, centre_angle + arc_half, 24), cam, 1.5)
	var backboard_from := _pp(base_x + dir * 4.0, width / 2.0 - 3.0, 9.0, cam)
	var backboard_to := _pp(base_x + dir * 4.0, width / 2.0 + 3.0, 9.0, cam)
	draw_line(backboard_from, backboard_to, LINE, 3.0)
	draw_circle(_pp(hoop.x, hoop.y, 10.0, cam), _projection.pixels_at(0.75, hoop.y, cam), BALL)   # the rim, ten feet up


func _draw_ball(origin: Vector2, scale_px: float) -> void:
	var t := _ease(progress)
	var at := _ball_position()
	var lift := sin(t * PI) * _ball_arc
	var spot := origin + Vector2(at.x, at.y - lift) * scale_px
	draw_circle(origin + at * scale_px + Vector2(0, 2), 0.8 * scale_px, Color(0, 0, 0, 0.25))   # its shadow on the floor
	draw_circle(spot, 0.95 * scale_px, BALL)
	draw_arc(spot, 0.95 * scale_px, 0.0, TAU, 20, BALL_EDGE, 1.5, true)
	if _hoop_flash > 0.0 and progress > 0.6:
		var hoop := origin + FcCourtLayout.basket(_flash_right) * scale_px
		draw_arc(hoop, 2.4 * scale_px, 0.0, TAU, 28, FcUiTokens.GOLD, 3.0, true)


func _draw_floor(origin: Vector2, s: float) -> void:
	var length := FcCourtLayout.COURT_LENGTH
	var width := FcCourtLayout.COURT_WIDTH
	draw_rect(Rect2(origin, Vector2(length, width) * s), FLOOR)
	for i in range(0, 10, 2):   # floorboards: every other tenth of the length a shade darker
		draw_rect(Rect2(origin + Vector2(i * length / 10.0 * s, 0), Vector2(length / 10.0 * s, width * s)), FLOOR_DARK)
	draw_rect(Rect2(origin, Vector2(length, width) * s), LINE, false, 2.0)
	draw_line(origin + Vector2(length / 2.0, 0) * s, origin + Vector2(length / 2.0, width) * s, LINE, 2.0)
	draw_arc(origin + Vector2(length / 2.0, width / 2.0) * s, 6.0 * s, 0.0, TAU, 40, LINE, 2.0, true)
	for right in [false, true]:
		var dir := -1.0 if right else 1.0
		var base_x := length if right else 0.0
		var hoop := FcCourtLayout.basket(right)
		var paint := Rect2(origin + Vector2(base_x if not right else base_x - 19.0, width / 2.0 - 8.0) * s, Vector2(19.0, 16.0) * s)
		draw_rect(paint, LINE, false, 2.0)
		draw_arc(origin + Vector2(base_x + dir * 19.0, width / 2.0) * s, 6.0 * s, 0.0, TAU, 32, LINE, 1.5, true)
		draw_arc(origin + hoop * s, 4.0 * s, -PI / 2.0 if not right else PI / 2.0, PI / 2.0 if not right else 3.0 * PI / 2.0, 16, LINE, 1.5, true)
		# the three-point line: straight corner runs, then an arc around the basket
		var corner_x := sqrt(FcCourtLayout.THREE_POINT_DISTANCE * FcCourtLayout.THREE_POINT_DISTANCE - FcCourtLayout.CORNER_THREE_DISTANCE * FcCourtLayout.CORNER_THREE_DISTANCE)
		var arc_half := asin(FcCourtLayout.CORNER_THREE_DISTANCE / FcCourtLayout.THREE_POINT_DISTANCE)
		var run_end := hoop.x + dir * corner_x
		for y in [3.0, width - 3.0]:
			draw_line(origin + Vector2(base_x, y) * s, origin + Vector2(run_end, y) * s, LINE, 1.5)
		var centre_angle := PI if right else 0.0   # the arc bulges toward centre court
		draw_arc(origin + hoop * s, FcCourtLayout.THREE_POINT_DISTANCE * s, centre_angle - arc_half, centre_angle + arc_half, 24, LINE, 1.5, true)
		draw_circle(origin + hoop * s, 0.75 * s, LINE)
		draw_line(origin + Vector2(base_x + dir * 4.0, width / 2.0 - 3.0) * s, origin + Vector2(base_x + dir * 4.0, width / 2.0 + 3.0) * s, LINE, 3.0)
