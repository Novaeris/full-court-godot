class_name FcCameraDirector
extends RefCounted
## Decides where a broadcast camera should look at each event of a replay (master plan B2b option B; Broadcast pass 2 M3, D-071). Pure: it reads
## the timeline and the recorded event only, and returns a shot as data
##   {preset, focus (court feet), zoom, hold (seconds), priority, transition, angle, side, critical, reason}
## that a viewer applies. It does not know whether the viewer is the 2D court or the 3D one; only the court coordinates of FcCourtLayout are
## shared. The positions are the replay's illustrative ones (the simulation has no tracked positions), so a shot frames "the basket" or "the
## ball area", never a claim about where a player really stood.
##
## Presets (what the shot is FOR): wide (the main broadcast angle), ball, shooter, basket, free_throw, baseline (end-line view of the attacked
## basket), overhead (tactical view), closeup (a medium close-up: the 3D camera is never nearer than 28 ft, D-070, so this is a tight medium
## shot), celebration (after a notable basket), stoppage (a recorded whistle) and replay (an instant replay, see replay_shot_for).
## Angles (how the 3D camera stands, see FcBroadcast3DRules.camera_pose): main, baseline, overhead, closeup. `side` is +1 when the offence attacks
## the right-hand basket, -1 for the left: the baseline camera stands behind the basket being attacked, so possession decides it.
##
## Priorities (highest first): free throws, a celebrated basket, a made shot, a block or steal, a foul, a rebound, a miss, a substitution,
## period markers, the rest. FcCameraRig enforces holds, interruption rules, cooldowns and the switch limit; a `critical` shot (free throws,
## a celebration, the final buzzer, an instant replay) may interrupt a shot that has not yet had its minimum time.
## After a rebound, a steal or a whistle the reconstruction is clock-compressed (docs/validation/B2_PASS2_RECONSTRUCTION_TIMING.md), so a slow
## follow-shot would show movement that never happened: those events use a whip (a fast move) instead of a slow ease.

const PRESET_WIDE := "wide"
const PRESET_MAIN := PRESET_WIDE   # the main broadcast angle is the wide shot
const PRESET_BALL := "ball"
const PRESET_SHOOTER := "shooter"
const PRESET_BASKET := "basket"
const PRESET_FREE_THROW := "free_throw"
const PRESET_BASELINE := "baseline"
const PRESET_OVERHEAD := "overhead"
const PRESET_CLOSEUP := "closeup"
const PRESET_CELEBRATION := "celebration"
const PRESET_STOPPAGE := "stoppage"
const PRESET_REPLAY := "replay"
const PRESETS := [PRESET_WIDE, PRESET_BALL, PRESET_SHOOTER, PRESET_BASKET, PRESET_FREE_THROW, PRESET_BASELINE, PRESET_OVERHEAD, PRESET_CLOSEUP,
	PRESET_CELEBRATION, PRESET_STOPPAGE, PRESET_REPLAY]

const ANGLE_MAIN := "main"
const ANGLE_BASELINE := "baseline"
const ANGLE_OVERHEAD := "overhead"
const ANGLE_CLOSEUP := "closeup"
const ANGLES := [ANGLE_MAIN, ANGLE_BASELINE, ANGLE_OVERHEAD, ANGLE_CLOSEUP]
## The angles an instant replay cycles through (M4 lets the viewer pick one).
const REPLAY_ANGLES := [ANGLE_MAIN, ANGLE_BASELINE, ANGLE_OVERHEAD]

const TRANSITION_CUT := "cut"
const TRANSITION_EASE := "ease"
const TRANSITION_WHIP := "whip"
const TRANSITIONS := [TRANSITION_CUT, TRANSITION_EASE, TRANSITION_WHIP]

const FREE_THROW_LINE_FROM_BASKET := 15.0
## A scoring run this long (unanswered points) makes the next basket a celebration.
const CELEBRATION_RUN := 8


## The shot for event `index` of the timeline ({} for an empty game).
static func shot_for(timeline: FcBroadcastTimeline, index: int) -> Dictionary:
	if timeline == null or timeline.is_empty():
		return {}
	index = clampi(index, 0, timeline.size() - 1)
	var state := timeline.model.state_at(index)
	var e: Dictionary = state["entry"]
	var right: bool = state["attacks_right"]
	var side := 1 if right else -1
	var hoop := FcCourtLayout.basket(right)
	var ball_area := (FcCourtLayout.formation(right)["offense"] as Array)[0] as Vector2
	var follow_up := _follows_compressed_step(timeline, index)
	var move := TRANSITION_WHIP if follow_up else TRANSITION_EASE
	match int(e["type"]):
		FcGameEventLog.EV_FREE_THROW:
			var ft := Vector2(hoop.x + (-FREE_THROW_LINE_FROM_BASKET if right else FREE_THROW_LINE_FROM_BASKET), FcCourtLayout.COURT_WIDTH / 2.0)
			return _shot(PRESET_FREE_THROW, ft, 2.2, 2.5, 100, TRANSITION_CUT, ANGLE_BASELINE, side, true, "free throw")
		FcGameEventLog.EV_SHOT_MADE:
			var spot := FcCourtLayout.shot_spot(int(e["x"]), int(e["index"]), right)
			if _is_celebration(timeline, index, e):
				return _shot(PRESET_CELEBRATION, spot.lerp(hoop, 0.3), 2.2, 2.4, 95, TRANSITION_CUT, ANGLE_CLOSEUP, side, true, "celebration")
			return _shot(PRESET_SHOOTER, spot.lerp(hoop, 0.5), 1.8, 2.0, 90, TRANSITION_CUT, ANGLE_MAIN, side, false, "made shot")
		FcGameEventLog.EV_SHOT_BLOCKED:
			var blocked_at := FcCourtLayout.shot_spot(int(e["x"]), int(e["index"]), right)
			return _shot(PRESET_BASELINE, blocked_at.lerp(hoop, 0.2), 1.8, 1.5, 80, move, ANGLE_BASELINE, side, false, "block")
		FcGameEventLog.EV_TURNOVER:
			var steal := int(e["b"]) != 0
			return _shot(PRESET_BALL, ball_area, 1.5, 1.5, 80 if steal else 40, TRANSITION_WHIP if steal else move, ANGLE_MAIN, side, false, "steal" if steal else "turnover")
		FcGameEventLog.EV_FOUL:
			return _shot(PRESET_CLOSEUP, ball_area, 1.8, 1.2, 70, move, ANGLE_CLOSEUP, side, false, "foul")
		FcGameEventLog.EV_REBOUND:
			return _shot(PRESET_BASKET, hoop, 1.7, 1.0, 60, TRANSITION_WHIP, ANGLE_MAIN, side, false, "rebound")
		FcGameEventLog.EV_SHOT_MISSED:
			# a miss at the rim is seen from behind the basket the offence attacks; any other miss from the main angle
			if int(e["x"]) == FcGameEventLog.SHOT_RIM:
				return _shot(PRESET_BASELINE, hoop, 1.7, 1.0, 55, move, ANGLE_BASELINE, side, false, "miss")
			return _shot(PRESET_BASKET, hoop, 1.7, 1.0, 55, move, ANGLE_MAIN, side, false, "miss")
		FcGameEventLog.EV_SUBSTITUTION:
			return _shot(PRESET_STOPPAGE, _centre(), 1.0, 1.5, 30, move, ANGLE_OVERHEAD, side, false, "substitution")
		FcGameEventLog.EV_PERIOD_START, FcGameEventLog.EV_PERIOD_END:
			return _shot(PRESET_OVERHEAD, _centre(), 1.0, 1.5, 20, move, ANGLE_OVERHEAD, side, false, "period")
		FcGameEventLog.EV_GAME_END:
			return _shot(PRESET_WIDE, _centre(), 1.0, 2.0, 100, move, ANGLE_MAIN, side, true, "final buzzer")
	return _shot(PRESET_WIDE, _centre(), 1.0, 0.6, 10, move, ANGLE_MAIN, side, false, "play")


## The shot of an instant replay of event `index` from replay angle `variant` (0 main, 1 baseline, 2 overhead, then around). A replay is critical
## (it takes the camera at once) and glides, so the picture reads as a deliberate second look.
static func replay_shot_for(timeline: FcBroadcastTimeline, index: int, variant: int = 0) -> Dictionary:
	var base := shot_for(timeline, index)
	if base.is_empty():
		return {}
	var angle: String = REPLAY_ANGLES[posmod(variant, REPLAY_ANGLES.size())]
	var zoom := 1.0 if angle == ANGLE_OVERHEAD else minf(float(base["zoom"]), 1.8)
	return _shot(PRESET_REPLAY, base["focus"], zoom, 1.5, 100, TRANSITION_EASE, angle, int(base["side"]), true, "replay")


## Whether a made basket is worth a celebration shot: a three-pointer, the end of a run, a milestone or a lead change.
static func _is_celebration(timeline: FcBroadcastTimeline, index: int, e: Dictionary) -> bool:
	if int(e["x"]) == FcGameEventLog.SHOT_THREE:
		return true
	var snap := timeline.snapshot(index)
	var run: Dictionary = snap["run"]
	if int(run["side"]) == int(e["side"]) and int(run["points"]) >= CELEBRATION_RUN:
		return true
	if not (snap["milestone"] as Dictionary).is_empty():
		return true
	if index > 0 and int(snap["lead_changes"]) > int(timeline.snapshot(index - 1)["lead_changes"]):
		return true
	return false


## Whether the event comes right after a step the reconstruction has to compress (a rebound, a steal or turnover, or a whistle: 33% to 88% of
## those steps are compressed), where a slow follow-shot would be dishonest.
static func _follows_compressed_step(timeline: FcBroadcastTimeline, index: int) -> bool:
	if index <= 0:
		return false
	match int(timeline.model.entries[index - 1]["type"]):
		FcGameEventLog.EV_REBOUND, FcGameEventLog.EV_TURNOVER, FcGameEventLog.EV_FOUL, FcGameEventLog.EV_SUBSTITUTION, FcGameEventLog.EV_PERIOD_START, FcGameEventLog.EV_PERIOD_END:
			return true
	return false


static func _centre() -> Vector2:
	return Vector2(FcCourtLayout.COURT_LENGTH / 2.0, FcCourtLayout.COURT_WIDTH / 2.0)


static func _shot(preset: String, focus: Vector2, zoom: float, hold: float, priority: int, transition: String, angle: String = ANGLE_MAIN, side: int = 1, critical: bool = false, reason: String = "") -> Dictionary:
	var cam := FcCourtProjection.clamp_camera({"focus": focus, "zoom": zoom})
	return {"preset": preset, "focus": cam["focus"], "zoom": cam["zoom"], "hold": hold, "priority": priority, "transition": transition,
		"angle": angle, "side": side, "critical": critical, "reason": reason}
