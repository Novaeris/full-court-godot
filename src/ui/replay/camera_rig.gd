class_name FcCameraRig
extends RefCounted
## The camera itself (master plan B2b option B): holds the current camera {focus, zoom}, takes the shots the director asks for, lets the person
## take over and gives the camera back. Pure and driven by `advance(delta)`, so tests run it without frames or a window.
##
## Modes: AUTO (the director only; input is ignored), HYBRID (the default: the director, but any manual move takes over for
## `resume_seconds` of no input, then the camera returns to the director's latest shot; or at once with `reset()`), MANUAL (the person only,
## until `reset()`). A shot's minimum hold is respected: a request of lower or equal priority cannot take the camera until the hold ends,
## a higher one can at once. Cuts jump, eases glide (exponential smoothing); with `reduced` every move simply happens at once.
##
## Direction rules (Broadcast pass 2, M3; numbers in data/ui/broadcast_identity.json, "camera"): a shot stays up for at least min_shot_seconds
## before ANY non-critical shot may take the camera (so it never flickers); a preset cannot be taken again inside its cooldown; at most
## max_switches_per_10s non-critical switches happen in any ten seconds; a critical shot (free throws, a celebration, the final buzzer, an
## instant replay) takes the camera at once. The director `style` (calm, standard, energetic) scales holds, cooldowns and the ease speed.
## Manual input suspends all of it: manual_move/manual_set clear the rules, and the director's latest shot comes back after the idle time.

enum Mode { AUTO, HYBRID, MANUAL }

const EASE_RATE := 6.0
const NEVER := -1.0e9

var mode: int = Mode.HYBRID
var resume_seconds: float = 4.0
var reduced: bool = false
## The director style: "calm", "standard" or "energetic" (FcBroadcastStyle.camera_style).
var style: String = FcBroadcastStyle.default_camera_style()

var _camera: Dictionary = FcCourtProjection.default_camera()
var _target: Dictionary = FcCourtProjection.default_camera()
var _time: float = 0.0
var _hold_until: float = -1.0
var _priority: int = -1
var _manual_until: float = -1.0
var _was_overridden: bool = false
var _last_shot: Dictionary = {}
var _taken_at: float = NEVER
var _rate: float = EASE_RATE
var _angle: String = FcCameraDirector.ANGLE_MAIN
var _angle_side: int = 1
var _preset_taken: Dictionary = {}   # preset -> the time it was last taken
var _switches: Array[float] = []     # the times of non-critical switches, for the limit per ten seconds
var _log: Array[Dictionary] = []     # every switch taken: {t, preset, critical}, for tests and tuning


## The camera as it is now: {focus, zoom}.
func camera() -> Dictionary:
	return _camera.duplicate()


func target() -> Dictionary:
	return _target.duplicate()


## How the 3D camera should stand: {angle, side}. The 2D view ignores it.
func pose_angle() -> Dictionary:
	return {"angle": _angle, "side": _angle_side}


## Every switch the rig has taken so far, in order: {t (rig seconds), preset, critical}.
func switch_log() -> Array[Dictionary]:
	return _log.duplicate()


## Whether the person has the camera right now (hybrid with recent input, or manual).
func is_overridden() -> bool:
	return mode == Mode.MANUAL or (mode == Mode.HYBRID and _time < _manual_until)


## The director's request. Always remembered as the latest shot (so the camera can return to it); taken only when allowed.
## `jump` is a deliberate move by the person to an event (a scrub, a click in the feed, Start or End): the camera goes there at once, the direction
## rules apply only to the director following playback.
func request(shot: Dictionary, jump: bool = false) -> void:
	if shot.is_empty():
		return
	_last_shot = shot
	if is_overridden():
		return
	_take(shot, jump)


## `force` skips the direction rules (the return from manual control must never be refused, or the camera would stay where the person left it).
func _take(shot: Dictionary, force: bool = false) -> void:
	var priority := int(shot["priority"])
	var critical := bool(shot.get("critical", false))
	var preset := str(shot.get("preset", ""))
	var st := FcBroadcastStyle.camera_style(style)
	if not critical and not force:
		if _time - _taken_at < FcBroadcastStyle.min_shot_seconds() * float(st["hold"]):
			return   # the current shot has not had its minimum time: nothing that is not critical takes the camera
		if _time < _hold_until and priority <= _priority:
			return   # held against equal or lower priority
		var cooldown := FcBroadcastStyle.cooldown(preset) * float(st["cooldown"])
		if cooldown > 0.0 and _time - float(_preset_taken.get(preset, NEVER)) < cooldown:
			return   # this kind of shot was used too recently
		var recent := 0
		for t in _switches:
			if _time - t < 10.0:
				recent += 1
		if recent >= FcBroadcastStyle.max_switches_per_10s():
			return   # too many switches lately
		_switches.append(_time)
		while _switches.size() > FcBroadcastStyle.max_switches_per_10s() + 2:
			_switches.pop_front()
	_target = FcCourtProjection.clamp_camera({"focus": shot["focus"], "zoom": shot["zoom"]})
	_hold_until = _time + float(shot["hold"]) * float(st["hold"])
	_priority = priority
	_taken_at = _time
	_preset_taken[preset] = _time
	_angle = str(shot.get("angle", FcCameraDirector.ANGLE_MAIN))
	_angle_side = int(shot.get("side", 1))
	var transition := str(shot.get("transition", FcCameraDirector.TRANSITION_EASE))
	_rate = EASE_RATE * float(st["ease"]) * (FcBroadcastStyle.whip_rate_factor() if transition == FcCameraDirector.TRANSITION_WHIP else 1.0)
	_log.append({"t": _time, "preset": preset, "critical": critical})
	if reduced or transition == FcCameraDirector.TRANSITION_CUT:
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
	_taken_at = NEVER
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
	_taken_at = NEVER
	if reduced:
		_camera = _target.duplicate()


## Gives the camera back to the director: the whole court, and the director's next shot takes over (in MANUAL mode too).
func reset() -> void:
	_manual_until = -1.0
	_was_overridden = false
	_hold_until = -1.0
	_priority = -1
	_taken_at = NEVER
	_angle = FcCameraDirector.ANGLE_MAIN
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
			_taken_at = NEVER
			_take(_last_shot, true)
	var from_focus: Vector2 = _camera["focus"]
	var to_focus: Vector2 = _target["focus"]
	var from_zoom := float(_camera["zoom"])
	var to_zoom := float(_target["zoom"])
	if from_focus.is_equal_approx(to_focus) and is_equal_approx(from_zoom, to_zoom):
		return false
	if reduced:
		_camera = _target.duplicate()
		return true
	var k := 1.0 - exp(-_rate * maxf(delta, 0.0))
	var focus := from_focus.lerp(to_focus, k)
	var zoom := lerpf(from_zoom, to_zoom, k)
	if focus.distance_to(to_focus) < 0.01 and absf(zoom - to_zoom) < 0.001:
		focus = to_focus
		zoom = to_zoom
	_camera = {"focus": focus, "zoom": zoom}
	return true
