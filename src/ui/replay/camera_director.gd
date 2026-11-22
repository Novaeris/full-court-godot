class_name FcCameraDirector
extends RefCounted
## Decides where a broadcast camera should look at each event of a replay (master plan B2b option B). Pure: it reads the timeline and the
## recorded event only, and returns a shot as data {preset, focus (court feet), zoom, hold (seconds), priority, transition} that a viewer
## applies. It is written once and does not know whether the viewer is the 2D court or, later, a 3D one; only the court coordinates of
## FcCourtLayout are shared. The positions are the replay's illustrative ones (the simulation has no tracked positions), so a shot frames
## "the basket" or "the ball area", never a claim about where a player really stood.
##
## Priorities (highest first): free throws, a made shot, a block or steal, a foul, a rebound, a miss, a substitution, period markers, the rest.
## A shot has a minimum hold: a lower-priority event cannot take the camera until it ends (FcCameraRig enforces that).

const PRESET_WIDE := "wide"
const PRESET_BALL := "ball"
const PRESET_SHOOTER := "shooter"
const PRESET_BASKET := "basket"
const PRESET_FREE_THROW := "free_throw"

const TRANSITION_CUT := "cut"
const TRANSITION_EASE := "ease"

const FREE_THROW_LINE_FROM_BASKET := 15.0


## The shot for event `index` of the timeline ({} for an empty game).
static func shot_for(timeline: FcBroadcastTimeline, index: int) -> Dictionary:
	if timeline == null or timeline.is_empty():
		return {}
	index = clampi(index, 0, timeline.size() - 1)
	var state := timeline.model.state_at(index)
	var e: Dictionary = state["entry"]
	var right: bool = state["attacks_right"]
	var hoop := FcCourtLayout.basket(right)
	var ball_area := (FcCourtLayout.formation(right)["offense"] as Array)[0] as Vector2
	match int(e["type"]):
		FcGameEventLog.EV_FREE_THROW:
			return _shot(PRESET_FREE_THROW, Vector2(hoop.x + (-FREE_THROW_LINE_FROM_BASKET if right else FREE_THROW_LINE_FROM_BASKET), FcCourtLayout.COURT_WIDTH / 2.0), 2.2, 2.5, 100, TRANSITION_CUT)
		FcGameEventLog.EV_SHOT_MADE:
			var spot := FcCourtLayout.shot_spot(int(e["x"]), int(e["index"]), right)
			return _shot(PRESET_SHOOTER, spot.lerp(hoop, 0.5), 1.8, 2.0, 90, TRANSITION_CUT)
		FcGameEventLog.EV_SHOT_BLOCKED:
			var blocked_at := FcCourtLayout.shot_spot(int(e["x"]), int(e["index"]), right)
			return _shot(PRESET_BASKET, blocked_at.lerp(hoop, 0.2), 1.8, 1.5, 80, TRANSITION_EASE)
		FcGameEventLog.EV_TURNOVER:
			return _shot(PRESET_BALL, ball_area, 1.5, 1.5, 80 if int(e["b"]) != 0 else 40, TRANSITION_EASE)
		FcGameEventLog.EV_FOUL:
			return _shot(PRESET_BALL, ball_area, 1.4, 1.2, 70, TRANSITION_EASE)
		FcGameEventLog.EV_REBOUND:
			return _shot(PRESET_BASKET, hoop, 1.7, 1.0, 60, TRANSITION_EASE)
		FcGameEventLog.EV_SHOT_MISSED:
			return _shot(PRESET_BASKET, hoop, 1.7, 1.0, 55, TRANSITION_EASE)
		FcGameEventLog.EV_SUBSTITUTION:
			return _shot(PRESET_WIDE, _centre(), 1.0, 0.8, 30, TRANSITION_EASE)
		FcGameEventLog.EV_PERIOD_START, FcGameEventLog.EV_PERIOD_END, FcGameEventLog.EV_GAME_END:
			return _shot(PRESET_WIDE, _centre(), 1.0, 1.5, 20, TRANSITION_EASE)
	return _shot(PRESET_WIDE, _centre(), 1.0, 0.6, 10, TRANSITION_EASE)


static func _centre() -> Vector2:
	return Vector2(FcCourtLayout.COURT_LENGTH / 2.0, FcCourtLayout.COURT_WIDTH / 2.0)


static func _shot(preset: String, focus: Vector2, zoom: float, hold: float, priority: int, transition: String) -> Dictionary:
	var cam := FcCourtProjection.clamp_camera({"focus": focus, "zoom": zoom})
	return {"preset": preset, "focus": cam["focus"], "zoom": cam["zoom"], "hold": hold, "priority": priority, "transition": transition}
