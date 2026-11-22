class_name FcBroadcastPose
extends RefCounted
## The pure maths (promoted from the B1c prototype into the game for B4) of a character's procedural animation, with no nodes and no assets.
## A pose is {joint name: Vector3 euler rotation in radians} plus a root offset; each state is a function of a looping phase. States blend by
## linear interpolation of every joint, which is how the prototype checks the plan's "animation blending" question (no popping at a transition).
## Joints: pelvis, torso, head, l_shoulder, r_shoulder, l_elbow, r_elbow, l_hip, r_hip, l_knee, r_knee.

const STATES := ["idle", "run", "dribble", "shoot", "layup", "defend"]
const JOINTS := ["pelvis", "torso", "head", "l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_hip", "r_hip", "l_knee", "r_knee"]
## How long one loop of each state takes, in seconds.
const CYCLE := {"idle": 3.0, "run": 0.7, "dribble": 0.8, "shoot": 1.3, "layup": 1.1, "defend": 1.0}


static func rest() -> Dictionary:
	var out := {}
	for j in JOINTS:
		out[j] = Vector3.ZERO
	return out


## The pose of `state` at `phase` (0 to 1 around one loop): {"joints": {...}, "root": Vector3 (feet of the body's centre, height scaled by the caller)}.
static func pose_for(state: String, phase: float) -> Dictionary:
	var j := rest()
	var root := Vector3.ZERO
	var s := sin(phase * TAU)
	var c := cos(phase * TAU)
	match state:
		"idle":
			j["torso"] = Vector3(0.03 * s, 0.0, 0.0)
			j["l_shoulder"] = Vector3(0.05, 0.0, 0.12)
			j["r_shoulder"] = Vector3(0.05, 0.0, -0.12)
			j["l_elbow"] = Vector3(-0.2, 0.0, 0.0)
			j["r_elbow"] = Vector3(-0.2, 0.0, 0.0)
			j["l_hip"] = Vector3(-0.08, 0.0, 0.0)
			j["r_hip"] = Vector3(-0.08, 0.0, 0.0)
			j["l_knee"] = Vector3(0.16, 0.0, 0.0)
			j["r_knee"] = Vector3(0.16, 0.0, 0.0)
			root.y = -0.012 * (1.0 + s)
		"run":
			j["pelvis"] = Vector3(0.0, 0.1 * s, 0.0)
			j["torso"] = Vector3(0.18, -0.12 * s, 0.0)
			j["l_hip"] = Vector3(0.85 * s, 0.0, 0.0)
			j["r_hip"] = Vector3(-0.85 * s, 0.0, 0.0)
			j["l_knee"] = Vector3(maxf(0.0, -c) * 1.2 + 0.2, 0.0, 0.0)
			j["r_knee"] = Vector3(maxf(0.0, c) * 1.2 + 0.2, 0.0, 0.0)
			j["l_shoulder"] = Vector3(-0.8 * s, 0.0, 0.1)
			j["r_shoulder"] = Vector3(0.8 * s, 0.0, -0.1)
			j["l_elbow"] = Vector3(-1.1, 0.0, 0.0)
			j["r_elbow"] = Vector3(-1.1, 0.0, 0.0)
			root.y = -0.025 + 0.03 * absf(c)
		"dribble":
			var bounce := sin(phase * TAU * 2.0)
			j["torso"] = Vector3(0.28, 0.0, 0.0)
			j["l_hip"] = Vector3(0.45 + 0.25 * s, 0.0, 0.0)
			j["r_hip"] = Vector3(0.45 - 0.25 * s, 0.0, 0.0)
			j["l_knee"] = Vector3(0.7, 0.0, 0.0)
			j["r_knee"] = Vector3(0.7, 0.0, 0.0)
			j["r_shoulder"] = Vector3(0.5 + 0.35 * bounce, 0.0, -0.15)
			j["r_elbow"] = Vector3(-0.9 - 0.3 * bounce, 0.0, 0.0)
			j["l_shoulder"] = Vector3(0.2, 0.0, 0.75)
			j["l_elbow"] = Vector3(-0.6, 0.0, 0.0)
			root.y = -0.07
		"shoot":
			var rise := clampf(phase / 0.45, 0.0, 1.0)         # crouch, then up
			var release := clampf((phase - 0.45) / 0.2, 0.0, 1.0)
			var down := clampf((phase - 0.7) / 0.3, 0.0, 1.0)
			var crouch := sin(clampf(phase / 0.35, 0.0, 1.0) * PI) * 0.7 * (1.0 - down)
			j["l_knee"] = Vector3(0.2 + crouch, 0.0, 0.0)
			j["r_knee"] = Vector3(0.2 + crouch, 0.0, 0.0)
			j["l_hip"] = Vector3(-0.1 - crouch * 0.5, 0.0, 0.0)
			j["r_hip"] = Vector3(-0.1 - crouch * 0.5, 0.0, 0.0)
			var raised := rise * (1.0 - down)    # 0 at the start and end of the loop (ready position), 1 with the arms up
			var arm := -2.5 * raised
			j["r_shoulder"] = Vector3(arm, 0.0, -0.1)
			j["l_shoulder"] = Vector3(arm * 0.7, 0.0, 0.25)
			j["r_elbow"] = Vector3(-1.6 * (1.0 - raised) - 0.2 + 1.2 * release * (1.0 - down), 0.0, 0.0)
			j["l_elbow"] = Vector3(-1.0 * (1.0 - raised) - 0.2, 0.0, 0.0)
			j["torso"] = Vector3(-0.1 * raised, 0.0, 0.0)
			root.y = 0.22 * sin(clampf((phase - 0.3) / 0.45, 0.0, 1.0) * PI) - 0.05 * crouch
		"layup":
			var step := sin(clampf(phase / 0.5, 0.0, 1.0) * PI)
			var jump := sin(clampf((phase - 0.25) / 0.6, 0.0, 1.0) * PI)
			j["l_hip"] = Vector3(-1.25 * jump + 0.5 * (1.0 - jump) * s, 0.0, 0.0)
			j["l_knee"] = Vector3(1.5 * jump + 0.2, 0.0, 0.0)
			j["r_hip"] = Vector3(0.3 * jump - 0.5 * (1.0 - jump) * s, 0.0, 0.0)
			j["r_knee"] = Vector3(0.2 + 0.3 * step, 0.0, 0.0)
			j["r_shoulder"] = Vector3(-2.9 * jump + 0.4 * (1.0 - jump), 0.0, -0.1)
			j["r_elbow"] = Vector3(-0.3 - 0.4 * (1.0 - jump), 0.0, 0.0)
			j["l_shoulder"] = Vector3(-0.8 * jump, 0.0, 0.5)
			j["l_elbow"] = Vector3(-0.8, 0.0, 0.0)
			j["torso"] = Vector3(0.1 + 0.1 * (1.0 - jump), 0.0, 0.0)
			root.y = 0.34 * jump
		"defend":
			var shuffle := sin(phase * TAU)
			j["torso"] = Vector3(0.2, 0.0, 0.0)
			j["l_hip"] = Vector3(-0.55, 0.0, 0.0)
			j["r_hip"] = Vector3(-0.55, 0.0, 0.0)
			j["l_knee"] = Vector3(0.95, 0.0, 0.0)
			j["r_knee"] = Vector3(0.95, 0.0, 0.0)
			j["l_shoulder"] = Vector3(-0.3, 0.0, 1.25)
			j["r_shoulder"] = Vector3(-0.3, 0.0, -1.25)
			j["l_elbow"] = Vector3(-0.5, 0.0, 0.0)
			j["r_elbow"] = Vector3(-0.5, 0.0, 0.0)
			j["pelvis"] = Vector3(0.0, 0.0, 0.05 * shuffle)
			root.y = -0.1 + 0.015 * absf(shuffle)
			root.x = 0.08 * shuffle
		_:
			pass
	return {"joints": j, "root": root}


## A blend of two poses: weight 0 is `a`, 1 is `b`. Every joint and the root move linearly, so a blend never jumps.
static func blend(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var w := clampf(weight, 0.0, 1.0)
	var joints := {}
	for name in JOINTS:
		joints[name] = (a["joints"][name] as Vector3).lerp(b["joints"][name], w)
	return {"joints": joints, "root": (a["root"] as Vector3).lerp(b["root"], w)}


## The largest single-joint rotation difference (radians, over any axis) between two poses: the "pop" measure used to find a bad transition.
static func largest_joint_change(a: Dictionary, b: Dictionary) -> float:
	var worst := 0.0
	for name in JOINTS:
		var d: Vector3 = (a["joints"][name] as Vector3) - (b["joints"][name] as Vector3)
		worst = maxf(worst, maxf(absf(d.x), maxf(absf(d.y), absf(d.z))))
	return worst


## The distance the body should travel per second in `state` so the feet do not slide: one full stride loop (left and right step) covers about
## 1.3 body heights, so a 6.5 ft player runs at about 12 ft/s, a brisk run and well under the reconstruction's 22 ft/s limit (a sprint would
## shorten the loop). 0 for the standing states.
static func ground_speed(state: String, height_feet: float) -> float:
	return 1.3 * height_feet / float(CYCLE["run"]) if state == "run" else 0.0
