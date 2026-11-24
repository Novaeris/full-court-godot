class_name FcHandPoses
extends RefCounted
## Reusable hand poses for the optional x_ finger bones of an imported player (data/player_pipeline/hand_poses.json): relaxed, open, ball grip, shooting,
## dribbling, catching. PURE maths: it chooses the pose a hand should hold in an animation state, blends it toward the ball grip by how firmly the hands
## are on the ball, and returns one rotation per finger bone in the SAME world-aligned frame the pose library uses (the character turns it into a bone
## rotation with FcRigRetarget). Presentation only: it never changes a game, and a body without finger bones simply ignores it.
## Frame: at rest the fingers point straight down and the palm faces the thigh (left hand at +X, right at -X), so a finger FLEXES by turning about the
## front-to-back axis toward the palm, and SPREADS by turning about the left-right axis toward the front (thumb and index) or the back (little finger).

const DATA_PATH := "res://data/player_pipeline/hand_poses.json"
const DIGITS := ["thumb", "index", "middle", "ring", "pinky"]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {}
	return _data


## The name of the extension bone for a side ("l" or "r"), digit and joint (1 proximal, 2 distal).
static func bone_name(side: String, digit: String, joint: int) -> String:
	return "x_%s_%s_%d" % [side, digit, joint]


## The pose a hand holds in `state` when it is not on the ball.
static func pose_name(state: String, side: String) -> String:
	var table: Dictionary = data().get("states", {})
	if state in ["dribble", "dribble_run", "crossover", "hesitation"]:
		return "dribbling" if side == "r" else "relaxed"
	if state == "dribble_l":
		return "dribbling" if side == "l" else "relaxed"
	if state in ["shoot", "three"]:
		return "shooting" if side == "r" else "ball_grip"
	for name in table:
		if name == "default" or name == "dribbling" or name == "shooting":
			continue
		if state in (table[name] as Array):
			return name
	return str(table.get("default", "relaxed"))


## {digit: [proximal curl, distal curl, spread]} for a named pose.
static func digits(name: String) -> Dictionary:
	var poses: Dictionary = data().get("poses", {})
	return poses.get(name, poses.get("relaxed", {}))


## The digits of a hand in `state`: its own pose blended toward the ball grip by `grip` (0 to 1, how firmly the hands are on the ball).
static func blended(state: String, side: String, grip: float) -> Dictionary:
	var own := digits(pose_name(state, side))
	var target := digits("ball_grip")
	var out := {}
	var t := clampf(grip, 0.0, 1.0)
	for digit in DIGITS:
		var a: Array = own[digit]
		var b: Array = target[digit]
		out[digit] = [lerpf(a[0], b[0], t), lerpf(a[1], b[1], t), lerpf(a[2], b[2], t)]
	return out


## Rotation of every finger bone: {bone name: Quaternion} in the world-aligned pose frame (see the class comment).
static func finger_rotations(state: String, side: String, grip: float) -> Dictionary:
	var sign := 1.0 if side == "l" else -1.0
	var out := {}
	var shape := blended(state, side, grip)
	for digit in DIGITS:
		var d: Array = shape[digit]
		var curl_a := Quaternion(Vector3.BACK, -sign * float(d[0]))
		var spread := Quaternion(Vector3.RIGHT, -float(d[2]))
		out[bone_name(side, digit, 1)] = curl_a * spread
		out[bone_name(side, digit, 2)] = Quaternion(Vector3.BACK, -sign * float(d[1]))
	return out
