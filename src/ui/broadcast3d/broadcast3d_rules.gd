class_name FcBroadcast3DRules
extends RefCounted
## The pure rules of the 3D broadcast view (decision D-070, reduced scope): where the 3D camera stands for a director's shot, what each player
## does at an event, and the body a player is drawn with. No nodes, no rendering, so every rule is unit-tested without a window.
##
## Reduced scope: the 3D camera is a broadcast camera on the near sideline (wide, ball-tracking and medium framings). It can zoom in a little
## but **never closer than MIN_DISTANCE feet to what it looks at**: the code-built characters are only convincing at broadcast and medium
## distance (docs/validation/B1C_PLAYER_MODEL_PROTOTYPE.md), so there is deliberately no 3D close-up. Close-ups stay 2D portrait cards.

const BASE_OFFSET := Vector3(0.0, 35.0, 58.0)       # from the point looked at to the camera at zoom 1 (about 70 ft away)
const MAX_ZOOM_3D := 1.8
const MIN_DISTANCE := 28.0
## Where the camera stands, from the point looked at, for each director angle (FcCameraDirector.ANGLES). "baseline" is behind the basket being
## attacked (x is multiplied by the side, +1 for the right-hand basket); "overhead" is the tactical view from high above (a little off vertical so
## the camera's up direction stays defined); "closeup" is the tight medium shot, held at MIN_DISTANCE because there is no 3D close-up (D-070).
const ANGLE_OFFSETS := {"main": Vector3(0.0, 35.0, 58.0), "baseline": Vector3(32.0, 15.0, 0.0), "overhead": Vector3(0.0, 72.0, 7.0), "closeup": Vector3(0.0, 14.0, 24.0)}
## Seconds an angle change takes to glide.
const ANGLE_BLEND_SECONDS := 0.6
const LOOK_HEIGHT := 3.4
const FOV := 42.0
## The close shot of a player (camera_pose_front): how far in front, how high, and how far round from straight in front, in degrees.
const FRONT_DISTANCE := 27.0
const FRONT_HEIGHT := 9.0
const FRONT_SWING_DEGREES := 30.0

## Heights and weights by position when only the position is known (the box score carries no body measurements). Medians of the generated
## league (tools/audit_identity.ps1), then a small steady variation from the player's id.
const BODY_BY_POSITION := {1: [187, 81], 2: [195, 90], 3: [202, 99], 4: [207, 109], 5: [213, 119]}


## The 3D camera for a 2D camera {focus (court feet), zoom}: {"position", "target"}. The target is the focus on the floor (a little above it),
## the position is back along BASE_OFFSET divided by the zoom (clamped to MAX_ZOOM_3D), so the distance to the target is always at least
## MIN_DISTANCE. A focus off the court is pulled onto it.
static func camera_pose(focus: Vector2, zoom: float, angle: String = "main", side: int = 1) -> Dictionary:
	var f := Vector2(clampf(focus.x, 0.0, FcCourtLayout.COURT_LENGTH), clampf(focus.y, 0.0, FcCourtLayout.COURT_WIDTH))
	var z := clampf(zoom, 1.0, MAX_ZOOM_3D)
	var target := Vector3(f.x, LOOK_HEIGHT, f.y)
	var offset: Vector3 = ANGLE_OFFSETS.get(angle, BASE_OFFSET) / z
	offset.x *= float(side) if angle == "baseline" else 1.0
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


## The one-off ACTION a player performs at an event (3D overhaul M2), or "" when the event gives them none. Roles: "actor" (the player in the event's
## `a` column), "partner" (the `b` column: the blocker of a block, the thief of a steal, the passer of a basket), "contester" (the defender nearest the
## shooter), "ball", "defender", "other". `variant` is a steady number (the actor's id) that chooses between equal actions, so a rim shot is a layup for
## some players and a dunk for others, the same every time. Presentation only: the event already happened, this only chooses how to draw it.
static func action_for(entry_type: int, shot_kind: int, role: String, variant: int) -> String:
	match entry_type:
		FcGameEventLog.EV_SHOT_MADE, FcGameEventLog.EV_SHOT_MISSED, FcGameEventLog.EV_SHOT_BLOCKED:
			if role == "actor":
				if shot_kind == FcGameEventLog.SHOT_RIM:
					return "dunk" if entry_type == FcGameEventLog.EV_SHOT_MADE and variant % 4 == 0 else "layup"
				return "three" if shot_kind == FcGameEventLog.SHOT_THREE else "shoot"
			if role == "partner":
				return "block" if entry_type == FcGameEventLog.EV_SHOT_BLOCKED else "celebrate"
			if role == "contester":
				return "contest"
			if role == "celebrant" and entry_type == FcGameEventLog.EV_SHOT_MADE:
				return "celebrate"
		FcGameEventLog.EV_FREE_THROW:
			if role == "actor":
				return "shoot"
		FcGameEventLog.EV_REBOUND:
			if role == "actor":
				return "rebound"
		FcGameEventLog.EV_TURNOVER:
			if role == "actor":
				return "stop"
			if role == "partner":
				return "steal"
	return ""


## How fast a character travels (feet per second) to cover `distance` in about half a second, within the reconstruction's own limit.
static func travel_speed_for(distance: float) -> float:
	return clampf(distance * 2.4, 3.0, FcReconstructor.PLAYER_SPEED_LIMIT * 0.9)


## The movement state for a player of `role` travelling at `speed` feet per second: a walk, a run or a sprint for anyone, a dribble, a drive for the
## ball handler, a shuffle or a recovery sprint for a defender.
static func motion_for(role: String, speed: float) -> String:
	if role == "ball":
		return "dribble" if speed < 4.0 else ("drive" if speed > 14.0 else "dribble_run")
	if role == "defender" or role == "contester":
		return "shuffle" if speed < 9.0 else "recover"
	if speed < 5.5:
		return "walk"
	return "run" if speed < 13.5 else "sprint"


## The animation playback factor that makes a stride match the speed travelled (so the feet do not slide), kept within a believable range.
static func playback_for(state: String, speed: float, height_feet: float) -> float:
	var natural := FcBroadcastPose.ground_speed(state, height_feet)
	if natural <= 0.0:
		return 1.0
	return clampf(speed / natural, 0.55, 1.6)


## The 3D camera for a CLOSE shot of one player (3D overhaul M5): in front of the player, a third of a turn off the line he faces, a little above his head,
## so his face and number can be seen instead of his side or back. Still never nearer than MIN_DISTANCE to what it looks at (D-070): the offset is
## scaled up until it is. `subject_yaw` is the player's facing in degrees (FcBroadcast3DRules.facing_yaw's convention: 0 faces +z, 90 faces +x).
## The target is the subject's chest.
static func camera_pose_front(focus: Vector2, zoom: float, subject_yaw: float) -> Dictionary:
	var f := Vector2(clampf(focus.x, 0.0, FcCourtLayout.COURT_LENGTH), clampf(focus.y, 0.0, FcCourtLayout.COURT_WIDTH))
	var z := clampf(zoom, 1.0, MAX_ZOOM_3D)
	var target := Vector3(f.x, 4.2, f.y)
	var yaw := deg_to_rad(subject_yaw + FRONT_SWING_DEGREES)
	var ground := FRONT_DISTANCE / z
	var offset := Vector3(sin(yaw) * ground, FRONT_HEIGHT / z, cos(yaw) * ground)
	if offset.length() < MIN_DISTANCE:
		offset = offset.normalized() * MIN_DISTANCE
	return {"position": target + offset, "target": target}


## The yaw (degrees) a character must turn to face a point `from` looks at when it stands at `at` (for introductions: the player turns to the camera).
static func yaw_towards(at: Vector3, point: Vector3) -> float:
	return facing_yaw(Vector2(at.x, at.z), Vector2(point.x, point.z))
