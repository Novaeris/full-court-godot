class_name FcCameraRig
extends RefCounted
## The camera itself (master plan B2b option B): holds the current camera {focus, zoom}, takes the shots the director asks for, lets the person
## take over and gives the camera back. Pure and driven by `advance(delta)`, so tests run it without frames or a window.
##
## Modes: AUTO (the director only; input is ignored), HYBRID (the default: the director, but any manual move takes over for
## `resume_seconds` of no input, then the camera returns to the director's latest shot; or at once with `reset()`), MANUAL (the person only,
## until `reset()`). A shot's minimum hold is respected: a request of lower or equal priority cannot take the camera until the hold ends,
## a higher one can at once. Cuts jump, eases glide (exponential smoothing); with `reduced` every move simply happens at once.

enum Mode { AUTO, HYBRID, MANUAL }

const EASE_RATE := 6.0

var mode: int = Mode.HYBRID
var resume_seconds: float = 4.0
var reduced: bool = false

var _camera: Dictionary = FcCourtProjection.default_camera()
var _target: Dictionary = FcCourtProjection.default_camera()
var _time: float = 0.0
var _hold_until: float = -1.0
var _priority: int = -1
var _manual_until: float = -1.0
var _was_overridden: bool = false
var _last_shot: Dictionary = {}


## The camera as it is now: {focus, zoom}.
func camera() -> Dictionary:
	return _camera.duplicate()


func target() -> Dictionary:
	return _target.duplicate()


## Whether the person has the camera right now (hybrid with recent input, or manual).
func is_overridden() -> bool:
	return mode == Mode.MANUAL or (mode == Mode.HYBRID and _time < _manual_until)


## The director's request. Always remembered as the latest shot (so the camera can return to it); taken only when allowed.
func request(shot: Dictionary) -> void:
	if shot.is_empty():
		return
	_last_shot = shot
	if is_overridden():
		return
	_take(shot)


func _take(shot: Dictionary) -> void:
	var priority := int(shot["priority"])
	if _time < _hold_until and priority <= _priority:
		return   # the current shot has not been held long enough for this to take it
	_target = FcCourtProjection.clamp_camera({"focus": shot["focus"], "zoom": shot["zoom"]})
	_hold_until = _time + float(shot["hold"])
	_priority = priority
	if reduced or str(shot["transition"]) == FcCameraDirector.TRANSITION_CUT:
		_camera = _target.duplicate()


## Moves the camera by hand: `pan` in court feet, `zoom_factor` multiplies the zoom. Ignored in AUTO.
func manual_move(pan: Vector2, zoom_factor: float = 1.0) -> void:
	if mode == Mode.AUTO:
		return
	var focus: Vector2 = _target["focus"]
	_target = FcCourtProjection.clamp_camera({"focus": focus + pan, "zoom": float(_target["zoom"]) * zoom_factor})
	_manual_until = _time + resume_seconds
	_was_overridden = true
	_hold_until = -1.0
	_priority = -1
	if reduced:
		_camera = _target.duplicate()


## Puts the camera at an exact place by hand (a preset button). Ignored in AUTO.
func manual_set(focus: Vector2, zoom: float) -> void:
	if mode == Mode.AUTO:
		return
	_target = FcCourtProjection.clamp_camera({"focus": focus, "zoom": zoom})
	_manual_until = _time + resume_seconds
	_was_overridden = true
	_hold_until = -1.0
	_priority = -1
	if reduced:
		_camera = _target.duplicate()


## Gives the camera back to the director: the whole court, and the director's next shot takes over (in MANUAL mode too).
func reset() -> void:
	_manual_until = -1.0
	_was_overridden = false
	_hold_until = -1.0
	_priority = -1
	_target = FcCourtProjection.default_camera()
	if mode == Mode.MANUAL:
		mode = Mode.HYBRID
	if reduced:
		_camera = _target.duplicate()


## One step of time. Returns true when the camera moved (so the viewer redraws).
func advance(delta: float) -> bool:
	_time += delta
	if mode == Mode.HYBRID and _was_overridden and _time >= _manual_until:
		_was_overridden = false   # the person stopped: back to the director's latest shot
		if not _last_shot.is_empty():
			_hold_until = -1.0
			_priority = -1
			_take(_last_shot)
	var from_focus: Vector2 = _camera["focus"]
	var to_focus: Vector2 = _target["focus"]
	var from_zoom := float(_camera["zoom"])
	var to_zoom := float(_target["zoom"])
	if from_focus.is_equal_approx(to_focus) and is_equal_approx(from_zoom, to_zoom):
		return false
	if reduced:
		_camera = _target.duplicate()
		return true
	var k := 1.0 - exp(-EASE_RATE * maxf(delta, 0.0))
	var focus := from_focus.lerp(to_focus, k)
	var zoom := lerpf(from_zoom, to_zoom, k)
	if focus.distance_to(to_focus) < 0.01 and absf(zoom - to_zoom) < 0.001:
		focus = to_focus
		zoom = to_zoom
	_camera = {"focus": focus, "zoom": zoom}
	return true
