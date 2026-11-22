class_name FcBroadcast3DRules
extends RefCounted
## The pure rules of the 3D broadcast view (decision D-070, reduced scope): where the 3D camera stands for a director's shot, what each player
## does at an event, and the body a player is drawn with. No nodes, no rendering, so every rule is unit-tested without a window.
##
## Reduced scope: the 3D camera is a broadcast camera on the near sideline (wide, ball-tracking and medium framings). It can zoom in a little
## but **never closer than MIN_DISTANCE feet to what it looks at**: the code-built characters are only convincing at broadcast and medium
## distance (docs/validation/B1C_PLAYER_MODEL_PROTOTYPE.md), so there is deliberately no 3D close-up. Close-ups stay 2D portrait cards.

const BASE_OFFSET := Vector3(0.0, 40.0, 57.0)       # from the point looked at to the camera at zoom 1 (about 70 ft away)
const MAX_ZOOM_3D := 1.8
const MIN_DISTANCE := 28.0
const LOOK_HEIGHT := 3.0
const FOV := 42.0

## Heights and weights by position when only the position is known (the box score carries no body measurements). Medians of the generated
## league (tools/audit_identity.ps1), then a small steady variation from the player's id.
const BODY_BY_POSITION := {1: [187, 81], 2: [195, 90], 3: [202, 99], 4: [207, 109], 5: [213, 119]}


## The 3D camera for a 2D camera {focus (court feet), zoom}: {"position", "target"}. The target is the focus on the floor (a little above it),
## the position is back along BASE_OFFSET divided by the zoom (clamped to MAX_ZOOM_3D), so the distance to the target is always at least
## MIN_DISTANCE. A focus off the court is pulled onto it.
static func camera_pose(focus: Vector2, zoom: float) -> Dictionary:
	var f := Vector2(clampf(focus.x, 0.0, FcCourtLayout.COURT_LENGTH), clampf(focus.y, 0.0, FcCourtLayout.COURT_WIDTH))
	var z := clampf(zoom, 1.0, MAX_ZOOM_3D)
	var target := Vector3(f.x, LOOK_HEIGHT, f.y)
	var offset := BASE_OFFSET / z
	if offset.length() < MIN_DISTANCE:
		offset = offset.normalized() * MIN_DISTANCE
	return {"position": target + offset, "target": target}


## The yaw (degrees) that turns a character whose front is +z towards the court direction `to` from `from` (court feet, x along the length).
static func facing_yaw(from: Vector2, to: Vector2) -> float:
	var d := to - from
	if d.length() < 0.001:
		return 0.0
	return rad_to_deg(atan2(d.x, d.y))


## The body (height cm, weight kg) a player is drawn with: the position's median plus a steady variation from the id (up to +-5 cm, +-6 kg).
static func body_for(player_id: int, position: int) -> Array:
	var base: Array = BODY_BY_POSITION.get(position, BODY_BY_POSITION[3])
	var h := FcCourtLayout.unit(player_id, 11) - 0.5
	var w := FcCourtLayout.unit(player_id, 12) - 0.5
	return [int(base[0]) + roundi(h * 10.0), int(base[1]) + roundi(w * 12.0)]


## What a player does at an event. `role` is "actor" (the player named by the event), "ball" (holds the ball), "defender", "other".
static func state_for(entry_type: int, shot_kind: int, role: String, moving: bool) -> String:
	if role == "actor":
		match entry_type:
			FcGameEventLog.EV_SHOT_MADE, FcGameEventLog.EV_SHOT_MISSED, FcGameEventLog.EV_SHOT_BLOCKED:
				return "layup" if shot_kind == FcGameEventLog.SHOT_RIM else "shoot"
			FcGameEventLog.EV_FREE_THROW:
				return "shoot"
			FcGameEventLog.EV_REBOUND:
				return "layup"
			FcGameEventLog.EV_TURNOVER:
				return "run"
	if moving:
		return "run"
	if role == "ball":
		return "dribble"
	if role == "defender":
		return "defend"
	return "idle"


## How fast a character is allowed to travel towards its target (feet per second): never above the reconstruction's own limit.
static func travel_speed(state: String, height_feet: float) -> float:
	return minf(FcBroadcastPose.ground_speed("run", height_feet) * (1.4 if state == "run" else 1.0), FcReconstructor.PLAYER_SPEED_LIMIT)
