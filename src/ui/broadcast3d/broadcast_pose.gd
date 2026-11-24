class_name FcBroadcastPose
extends RefCounted
## The pure maths of a character's procedural animation (3D overhaul M2; first made in the B1c prototype), with no nodes and no assets. A pose is
## {joint name: Vector3 euler rotation in radians} plus a root offset, an "air" amount (0 on the floor, 1 fully airborne: the character keeps the
## feet on the floor unless this says otherwise) and a "grip" amount with a ball anchor (how much both hands should be on the ball, and where it is,
## which the character turns into inverse kinematics). Each state is a function of a looping phase; states blend by linear interpolation of every
## number, so a transition never pops (unit-tested for every pair).
##
## Written in ANATOMICAL terms and converted once (see _arm and _leg): "forward" raises an arm or swings a thigh towards the front, "out" lifts an
## arm away from the body, "bend" flexes an elbow or knee. The rest pose is a straight standing body with arms hanging; the left side is at +x.
## Joints: pelvis, torso, neck, head, l/r_shoulder, l/r_elbow, l/r_hand (wrist), l/r_hip, l/r_knee, l/r_foot (ankle).
##
## Animations are driven by simulation events through FcBroadcast3DRules; nothing here can change an outcome.

const STATES := [
	"idle", "walk", "run", "sprint", "stop", "turn", "jump", "land", "fall", "celebrate",
	"dribble", "dribble_run", "crossover", "hesitation", "drive", "post", "shoot", "three", "layup", "dunk",
	"defend", "shuffle", "contest", "steal", "block", "rebound", "recover", "sit", "coach", "intro",
]
const JOINTS := [
	"pelvis", "torso", "neck", "head", "l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_hand", "r_hand",
	"l_hip", "r_hip", "l_knee", "r_knee", "l_foot", "r_foot",
]
## How long one loop of each state takes, in seconds.
const CYCLE := {
	"idle": 3.0, "walk": 1.1, "run": 0.7, "sprint": 0.52, "stop": 0.8, "turn": 0.9, "jump": 1.0, "land": 0.9, "fall": 1.6, "celebrate": 1.3,
	"dribble": 0.8, "dribble_run": 0.7, "crossover": 0.9, "hesitation": 1.1, "drive": 0.6, "post": 1.4, "shoot": 1.3, "three": 1.4, "layup": 1.1, "dunk": 1.2,
	"defend": 1.0, "shuffle": 0.6, "contest": 1.0, "steal": 0.9, "block": 1.0, "rebound": 1.2, "recover": 0.7, "sit": 4.0, "coach": 3.0, "intro": 2.4,
}
## States where both hands are on the ball for part of the loop (the character solves arm IK to the ball anchor in these).
const TWO_HAND := ["shoot", "three", "dunk", "rebound", "post"]
## States in which the feet leave the floor (the character does not lock the feet to the ground while "air" is above 0).
const AIRBORNE := ["jump", "shoot", "three", "layup", "dunk", "contest", "block", "rebound"]


static func rest() -> Dictionary:
	var out := {}
	for j in JOINTS:
		out[j] = Vector3.ZERO
	return out


static func _new() -> Dictionary:
	return {"joints": rest(), "root": Vector3.ZERO, "air": 0.0, "grip": 0.0, "ball": Vector3.ZERO}


## An arm: `forward` raises it to the front (radians), `out` lifts it sideways, `bend` flexes the elbow, `twist` turns it in or out.
static func _arm(j: Dictionary, side: String, forward: float, out: float, bend: float, twist: float = 0.0) -> void:
	var sign := 1.0 if side == "l" else -1.0
	j[side + "_shoulder"] = Vector3(-forward, twist * sign, out * sign)
	j[side + "_elbow"] = Vector3(-bend, 0.0, 0.0)


## A leg: `forward` swings the thigh to the front, `bend` flexes the knee, `out` opens the thigh sideways, `toe` points the foot down.
static func _leg(j: Dictionary, side: String, forward: float, bend: float, out: float = 0.0, toe: float = 0.0) -> void:
	var sign := 1.0 if side == "l" else -1.0
	j[side + "_hip"] = Vector3(-forward, 0.0, out * sign)
	j[side + "_knee"] = Vector3(bend, 0.0, 0.0)
	j[side + "_foot"] = Vector3(toe, 0.0, 0.0)


## Keeps a planted foot flat on the floor whatever the leg does: the foot's own rotation cancels the pelvis, thigh and shin pitch (weight 0 to 1).
static func _flat_feet(j: Dictionary, weight: float, left: float = 1.0, right: float = 1.0) -> void:
	for pair in [["l", left], ["r", right]]:
		var s: String = pair[0]
		var pitch: float = (j["pelvis"] as Vector3).x + (j[s + "_hip"] as Vector3).x + (j[s + "_knee"] as Vector3).x
		var foot: Vector3 = j[s + "_foot"]
		j[s + "_foot"] = Vector3(foot.x - pitch * weight * float(pair[1]), foot.y, foot.z)


static func _sm(a: float, b: float, v: float) -> float:
	return smoothstep(a, b, v)


## The pose of `state` at `phase` (0 to 1 around one loop): {"joints": {...}, "root": Vector3 (feet of the body's centre, height scaled by the caller),
## "air": float, "grip": float, "ball": Vector3 (the ball anchor in body-height units, x sideways, y up, z forward, from the feet)}.
static func pose_for(state: String, phase: float) -> Dictionary:
	var out := _new()
	var j: Dictionary = out["joints"]
	var root := Vector3.ZERO
	var th := phase * TAU
	var s := sin(th)
	var c := cos(th)
	match state:
		"idle":
			j["torso"] = Vector3(0.04 + 0.015 * s, 0.0, 0.0)
			j["head"] = Vector3(-0.04, 0.0, 0.0)
			_arm(j, "l", 0.05, 0.14, 0.3)
			_arm(j, "r", 0.05, 0.14, 0.3)
			_leg(j, "l", 0.1, 0.2, 0.05)
			_leg(j, "r", 0.1, 0.2, 0.05)
			j["pelvis"] = Vector3(0.0, 0.0, 0.015 * s)
			root.y = -0.012 * (1.0 + s) - 0.01
			_flat_feet(j, 1.0)
		"walk":
			var a := 0.42
			j["torso"] = Vector3(0.05, 0.1 * c, 0.0)
			j["pelvis"] = Vector3(0.0, -0.1 * c, 0.0)
			for pair in [["l", s, c], ["r", -s, -c]]:
				var side: String = pair[0]
				_leg(j, side, a * float(pair[1]) + 0.05, 0.14 + 0.75 * pow(maxf(0.0, float(pair[2])), 1.5), 0.03)
				_arm(j, side, -0.4 * float(pair[1]), 0.08, 0.4 + 0.25 * maxf(0.0, -float(pair[1])))
			root.y = -0.025 + 0.018 * cos(2.0 * th + 0.4)
			_flat_feet(j, 0.8)
		"run", "sprint":
			var fast := state == "sprint"
			var swing := 0.78 if not fast else 0.95
			var lean := 0.2 if not fast else 0.34
			j["torso"] = Vector3(lean, -0.14 * c, 0.0)
			j["pelvis"] = Vector3(0.0, 0.1 * c, 0.0)
			j["head"] = Vector3(-lean * 0.6, 0.0, 0.0)
			for pair in [["l", s, c], ["r", -s, -c]]:
				var side: String = pair[0]
				var f: float = pair[1]
				var cc: float = pair[2]
				_leg(j, side, swing * f + 0.08, 0.28 + 1.35 * pow(maxf(0.0, cc), 1.2) * (1.0 if not fast else 1.2), 0.03, 0.2 * maxf(0.0, -f))
				_arm(j, side, -0.95 * f * (1.0 if not fast else 1.15), 0.12, 1.45)
			root.y = -0.035 + 0.045 * absf(c) + (0.02 if fast else 0.0)
			_flat_feet(j, 0.7)
		"stop":   # braking: lean back, wide braced stance, arms out, settling to idle at the end of the loop
			var settle := 1.0 - _sm(0.0, 0.12, phase) * (1.0 - _sm(0.12, 1.0, phase))
			var brace := 1.0 - settle   # braces at once, then eases back to a ready stance
			j["torso"] = Vector3(0.04 - 0.14 * brace, 0.0, 0.0)
			_arm(j, "l", 0.1, 0.5 * brace + 0.14, 0.4)
			_arm(j, "r", 0.1, 0.5 * brace + 0.14, 0.4)
			_leg(j, "l", 0.5 * brace + 0.1, 0.5 * brace + 0.2, 0.1 * brace)
			_leg(j, "r", -0.1 * brace + 0.1, 0.4 * brace + 0.2, 0.1 * brace)
			root.y = -0.07 * brace - 0.01
			_flat_feet(j, 1.0)
		"turn":   # a pivot: the body twists round the planted foot and back (a loop that returns to the start)
			var twist := sin(phase * PI)
			j["pelvis"] = Vector3(0.0, 0.7 * twist, 0.0)
			j["torso"] = Vector3(0.1, 0.35 * twist, 0.0)
			j["head"] = Vector3(-0.05, 0.3 * twist, 0.0)
			_arm(j, "l", 0.2, 0.35 * twist + 0.14, 0.7)
			_arm(j, "r", 0.2, 0.35 * twist + 0.14, 0.7)
			_leg(j, "l", 0.3, 0.55, 0.12)
			_leg(j, "r", 0.1, 0.45, 0.12)
			root.y = -0.05 - 0.01 * twist
			_flat_feet(j, 1.0)
		"jump":   # a two-footed jump: crouch, spring, hang with the arms up, land into a crouch
			var crouch := _sm(0.0, 0.25, phase) * (1.0 - _sm(0.25, 0.4, phase)) + _sm(0.8, 0.92, phase) * (1.0 - _sm(0.95, 1.0, phase))
			var up := _sm(0.25, 0.42, phase) * (1.0 - _sm(0.62, 0.82, phase))
			var arms := up
			j["torso"] = Vector3(0.18 * crouch - 0.05 * up, 0.0, 0.0)
			_arm(j, "l", 0.2 + 2.6 * arms, 0.3 * arms + 0.14, 0.3 * (1.0 - arms) + 0.2)
			_arm(j, "r", 0.2 + 2.6 * arms, 0.3 * arms + 0.14, 0.3 * (1.0 - arms) + 0.2)
			_leg(j, "l", 0.7 * crouch + 0.1 * (1.0 - up) - 0.05 * up, 1.2 * crouch + 0.2 + 0.4 * up, 0.06)
			_leg(j, "r", 0.7 * crouch + 0.1 * (1.0 - up) - 0.05 * up, 1.2 * crouch + 0.2 + 0.4 * up, 0.06)
			root.y = -0.2 * crouch + 0.3 * up
			out["air"] = up
			_flat_feet(j, 1.0 - up)
			for side in ["l", "r"]:
				j[side + "_foot"] = (j[side + "_foot"] as Vector3) + Vector3(0.8 * up, 0.0, 0.0)
		"land":   # the landing absorbed: deep crouch recovering to a ready stance
			var absorb := _sm(0.0, 0.08, phase) * (1.0 - _sm(0.08, 1.0, phase))
			j["torso"] = Vector3(0.05 + 0.3 * absorb, 0.0, 0.0)
			_arm(j, "l", 0.2, 0.3 * absorb + 0.14, 0.4 + 0.5 * absorb)
			_arm(j, "r", 0.2, 0.3 * absorb + 0.14, 0.4 + 0.5 * absorb)
			_leg(j, "l", 0.1 + 0.8 * absorb, 0.2 + 1.2 * absorb, 0.08 * absorb)
			_leg(j, "r", 0.1 + 0.8 * absorb, 0.2 + 1.2 * absorb, 0.08 * absorb)
			root.y = -0.25 * absorb - 0.01
			_flat_feet(j, 1.0)
		"fall":   # taken to the floor and getting up: a slow roll back to standing at the end of the loop
			var down := _sm(0.0, 0.3, phase) * (1.0 - _sm(0.6, 1.0, phase))
			j["torso"] = Vector3(-0.2 * down, 0.0, 0.5 * down)
			j["pelvis"] = Vector3(0.0, 0.0, -0.35 * down)
			_arm(j, "l", 0.8 * down, 0.9 * down + 0.14, 0.4)
			_arm(j, "r", 0.8 * down, 0.9 * down + 0.14, 0.4)
			_leg(j, "l", 0.9 * down + 0.1, 0.9 * down + 0.2, 0.3 * down)
			_leg(j, "r", -0.2 * down + 0.1, 0.4 * down + 0.2, 0.4 * down)
			root.y = -0.55 * down - 0.01
			_flat_feet(j, 1.0 - down)
		"celebrate":   # both fists up, a little bounce
			var bounce := 0.5 + 0.5 * sin(th * 2.0)
			j["torso"] = Vector3(-0.08, 0.0, 0.0)
			j["head"] = Vector3(-0.15, 0.0, 0.0)
			_arm(j, "l", 2.2, 0.7 + 0.1 * s, 1.1)
			_arm(j, "r", 2.2, 0.7 - 0.1 * s, 1.1)
			_leg(j, "l", 0.1, 0.35 + 0.2 * bounce, 0.1)
			_leg(j, "r", 0.1, 0.35 + 0.2 * bounce, 0.1)
			root.y = -0.03 + 0.1 * bounce
			out["air"] = 0.0
			_flat_feet(j, 1.0)
		"dribble":   # the ball is bounced with the right hand, in a low stance; the hand pumps twice per loop
			var bounce := sin(th * 2.0)
			j["torso"] = Vector3(0.3, 0.0, 0.0)
			j["head"] = Vector3(-0.22, 0.0, 0.0)
			_leg(j, "l", 0.55 + 0.1 * s, 0.85, 0.12)
			_leg(j, "r", 0.5 - 0.1 * s, 0.85, 0.12)
			_arm(j, "r", 0.55 + 0.3 * bounce, 0.18, 0.95 - 0.35 * bounce)
			_arm(j, "l", 0.5, 0.75, 0.7)   # the off arm out as a shield
			root.y = -0.085
			_flat_feet(j, 1.0)
		"dribble_run":
			var bounce := sin(th * 2.0)
			j["torso"] = Vector3(0.26, -0.1 * c, 0.0)
			j["pelvis"] = Vector3(0.0, 0.08 * c, 0.0)
			j["head"] = Vector3(-0.18, 0.0, 0.0)
			for pair in [["l", s, c], ["r", -s, -c]]:
				var side: String = pair[0]
				_leg(j, side, 0.7 * float(pair[1]) + 0.1, 0.3 + 1.2 * pow(maxf(0.0, float(pair[2])), 1.2), 0.03, 0.2 * maxf(0.0, -float(pair[1])))
			_arm(j, "r", 0.55 + 0.3 * bounce, 0.18, 0.95 - 0.35 * bounce)
			_arm(j, "l", -0.7 * s, 0.35, 1.3)
			root.y = -0.05 + 0.04 * absf(c)
			_flat_feet(j, 0.7)
		"crossover":   # the ball goes from the right hand to the left across the body, with a dip and a shoulder drop
			var cross := sin(th)
			var dip := 0.5 - 0.5 * cos(th * 2.0)
			j["torso"] = Vector3(0.3, 0.25 * cross, -0.1 * cross)
			j["head"] = Vector3(-0.2, 0.0, 0.0)
			j["pelvis"] = Vector3(0.0, -0.15 * cross, 0.04 * cross)
			_leg(j, "l", 0.5 + 0.2 * maxf(0.0, cross), 0.8 + 0.2 * dip, 0.15 + 0.1 * maxf(0.0, cross))
			_leg(j, "r", 0.5 + 0.2 * maxf(0.0, -cross), 0.8 + 0.2 * dip, 0.15 + 0.1 * maxf(0.0, -cross))
			# the working arm swings across: the right arm is on the ball for the first half, the left for the second
			_arm(j, "r", 0.6, 0.2 - 0.35 * maxf(0.0, cross), 0.9 - 0.3 * maxf(0.0, cross))
			_arm(j, "l", 0.6, 0.2 + 0.35 * minf(0.0, cross), 0.9 + 0.3 * minf(0.0, cross))
			root.y = -0.07 - 0.03 * dip
			_flat_feet(j, 1.0)
		"hesitation":   # a hitch: rise up as if to stop, then explode forward
			var hitch := sin(clampf(phase / 0.55, 0.0, 1.0) * PI)
			var burst := _sm(0.55, 0.9, phase) * (1.0 - _sm(0.9, 1.0, phase))
			j["torso"] = Vector3(0.28 - 0.25 * hitch + 0.15 * burst, 0.0, 0.0)
			_leg(j, "l", 0.45 + 0.25 * hitch - 0.2 * burst, 0.75 - 0.35 * hitch + 0.15 * burst, 0.1)
			_leg(j, "r", 0.45 - 0.1 * hitch + 0.4 * burst, 0.75 - 0.3 * hitch + 0.25 * burst, 0.1)
			_arm(j, "r", 0.55 + 0.4 * hitch, 0.2, 1.0 - 0.3 * hitch)
			_arm(j, "l", 0.4, 0.7 - 0.2 * hitch, 0.7)
			root.y = -0.08 + 0.05 * hitch
			_flat_feet(j, 1.0)
		"drive":   # a low, fast run to the rim with the ball held away from the defender
			j["torso"] = Vector3(0.38, -0.1 * c, 0.0)
			j["pelvis"] = Vector3(0.0, 0.08 * c, 0.0)
			j["head"] = Vector3(-0.3, 0.0, 0.0)
			for pair in [["l", s, c], ["r", -s, -c]]:
				var side: String = pair[0]
				_leg(j, side, 0.8 * float(pair[1]) + 0.2, 0.45 + 1.3 * pow(maxf(0.0, float(pair[2])), 1.2), 0.04, 0.2 * maxf(0.0, -float(pair[1])))
			var bounce := sin(th * 2.0)
			_arm(j, "r", 0.7 + 0.25 * bounce, 0.25, 0.9 - 0.3 * bounce)
			_arm(j, "l", 0.6 - 0.3 * s, 0.9, 0.9)
			root.y = -0.1 + 0.04 * absf(c)
			_flat_feet(j, 0.7)
		"post":   # back to the basket: a wide low stance, the seal arm out, the ball held two-handed on the hip
			var lean := sin(th * 2.0) * 0.5 + 0.5
			j["torso"] = Vector3(0.25, 0.0, 0.0)
			j["head"] = Vector3(-0.2, 0.0, 0.0)
			_leg(j, "l", 0.7, 1.0, 0.35)
			_leg(j, "r", 0.7, 1.0, 0.35)
			_arm(j, "l", 0.7, 1.15, 0.5)
			_arm(j, "r", 0.9, 0.15, 1.3)
			j["pelvis"] = Vector3(0.0, 0.0, 0.03 * s)
			root.y = -0.15 - 0.012 * lean
			out["grip"] = 0.0
			out["ball"] = Vector3(-0.07, 0.43, 0.1)
			_flat_feet(j, 1.0)
		"shoot", "three":   # a jump shot: load, rise, set the ball over the head, release with a wrist flick, land
			var deep := state == "three"
			var load := _sm(0.0, 0.3, phase) * (1.0 - _sm(0.32, 0.46, phase))
			var rise := _sm(0.3, 0.5, phase) * (1.0 - _sm(0.68, 0.9, phase))
			var release := _sm(0.5, 0.62, phase) * (1.0 - _sm(0.7, 1.0, phase))
			var raised := _sm(0.12, 0.5, phase) * (1.0 - _sm(0.62, 0.9, phase))   # arms up for the shot
			var bend_load := (0.95 if deep else 0.8) * load
			_leg(j, "l", 0.55 * load + 0.1, bend_load + 0.2 - 0.12 * rise, 0.05)
			_leg(j, "r", 0.5 * load + 0.1, bend_load + 0.2 - 0.12 * rise, 0.05)
			j["torso"] = Vector3(0.1 + 0.12 * load - 0.14 * rise, 0.0, 0.0)
			j["head"] = Vector3(-0.1 - 0.1 * raised, 0.0, 0.0)
			# the shooting arm (right): ball at the chest, up over the forehead, the elbow unfolds, the wrist flicks
			var elbow := 1.5 - 1.15 * release
			_arm(j, "r", 0.5 + 1.45 * raised + 0.25 * release, 0.06, elbow)
			_arm(j, "l", 0.45 + 1.2 * raised * (1.0 - release), 0.25 * raised, 1.35 - 0.2 * raised)
			j["r_hand"] = Vector3(-0.5 * raised + 1.1 * release, 0.0, 0.0)
			root.y = -0.1 * load + (0.26 if deep else 0.21) * rise
			out["air"] = rise
			var hold := _sm(0.08, 0.2, phase) * (1.0 - _sm(0.54, 0.6, phase))
			out["grip"] = hold
			out["ball"] = Vector3(-0.03 * raised, 0.58 + 0.42 * raised, 0.1 + 0.03 * raised)
			_flat_feet(j, 1.0 - rise)
			for side in ["l", "r"]:
				j[side + "_foot"] = (j[side + "_foot"] as Vector3) + Vector3(0.7 * rise, 0.0, 0.0)
		"layup":   # gather, two strides, the inside knee driving up, the right hand carrying the ball up to the rim
			var step := sin(clampf(phase / 0.45, 0.0, 1.0) * PI)
			var jump := sin(clampf((phase - 0.28) / 0.6, 0.0, 1.0) * PI)
			j["torso"] = Vector3(0.12 + 0.1 * (1.0 - jump) - 0.1 * jump, 0.0, 0.0)
			_leg(j, "l", 1.25 * jump - 0.4 * (1.0 - jump) * s * 0.0 + 0.15 * (1.0 - jump), 1.5 * jump + 0.25 * step, 0.05)
			_leg(j, "r", -0.25 * jump + 0.25 * step * (1.0 - jump) + 0.1, 0.3 + 0.8 * jump, 0.05)
			_arm(j, "r", 0.8 * (1.0 - jump) + 2.9 * jump, 0.12, 0.9 * (1.0 - jump) + 0.3 * jump)
			_arm(j, "l", 0.5 + 0.7 * jump, 0.5, 0.9)
			j["r_hand"] = Vector3(0.9 * _sm(0.7, 0.9, phase) * (1.0 - _sm(0.9, 1.0, phase)), 0.0, 0.0)
			root.y = -0.05 * (1.0 - jump) + 0.36 * jump
			out["air"] = jump
			_flat_feet(j, 1.0 - jump)
			for side in ["l", "r"]:
				j[side + "_foot"] = (j[side + "_foot"] as Vector3) + Vector3(0.6 * jump, 0.0, 0.0)
		"dunk":   # a two-handed dunk: launch, the ball cocked behind the head, slammed down through the rim, a hang, the landing
			var up := _sm(0.1, 0.38, phase) * (1.0 - _sm(0.72, 0.95, phase))
			var cock := _sm(0.3, 0.5, phase) * (1.0 - _sm(0.5, 0.58, phase))
			var slam := _sm(0.5, 0.6, phase) * (1.0 - _sm(0.66, 0.85, phase))
			j["torso"] = Vector3(0.1 - 0.2 * up + 0.35 * slam, 0.0, 0.0)
			_arm(j, "r", 0.9 + 2.0 * up - 0.5 * slam, 0.3 * up, 0.9 - 0.7 * up + 0.2 * slam)
			_arm(j, "l", 0.9 + 2.0 * up - 0.5 * slam, 0.3 * up, 0.9 - 0.7 * up + 0.2 * slam)
			_leg(j, "l", 0.25 * (1.0 - up) + 0.5 * up, 0.5 + 1.0 * up, 0.12)
			_leg(j, "r", 0.25 * (1.0 - up) - 0.2 * up, 0.5 + 0.7 * up, 0.12)
			root.y = -0.15 * sin(clampf(phase / 0.12, 0.0, 1.0) * PI) + 0.62 * up
			out["air"] = up
			var hold := _sm(0.05, 0.15, phase) * (1.0 - _sm(0.62, 0.7, phase))
			out["grip"] = hold
			out["ball"] = Vector3(0.0, lerpf(0.5, 1.12, up), lerpf(0.12, -0.02, cock) + 0.12 * slam)
			_flat_feet(j, 1.0 - up)
			for side in ["l", "r"]:
				j[side + "_foot"] = (j[side + "_foot"] as Vector3) + Vector3(0.6 * up, 0.0, 0.0)
		"defend":   # the defensive stance: low, wide, arms out, a small side-to-side sway
			var sway := sin(th)
			j["torso"] = Vector3(0.22, 0.0, 0.0)
			j["head"] = Vector3(-0.15, 0.0, 0.0)
			_leg(j, "l", 0.6, 1.0, 0.3)
			_leg(j, "r", 0.6, 1.0, 0.3)
			_arm(j, "l", 0.25, 1.15, 0.6)
			_arm(j, "r", 0.25, 1.15, 0.6)
			j["pelvis"] = Vector3(0.0, 0.0, 0.05 * sway)
			root.y = -0.14 + 0.015 * absf(sway)
			root.x = 0.03 * sway
			_flat_feet(j, 1.0)
		"shuffle":   # sliding sideways in the stance: the legs open and close, the arms stay wide
			var open := sin(th)
			j["torso"] = Vector3(0.22, 0.0, 0.0)
			j["head"] = Vector3(-0.15, 0.0, 0.0)
			_leg(j, "l", 0.6, 1.0, 0.3 + 0.2 * open)
			_leg(j, "r", 0.6, 1.0, 0.3 - 0.2 * open)
			_arm(j, "l", 0.25 + 0.15 * s, 1.1, 0.6)
			_arm(j, "r", 0.25 - 0.15 * s, 1.1, 0.6)
			j["pelvis"] = Vector3(0.0, 0.0, 0.06 * open)
			root.y = -0.14 + 0.02 * absf(c)
			_flat_feet(j, 1.0)
		"contest":   # a hand up at the shooter: a short hop with the right arm fully raised and the left out
			var hop := _sm(0.1, 0.35, phase) * (1.0 - _sm(0.55, 0.8, phase))
			j["torso"] = Vector3(0.12 - 0.1 * hop, 0.0, 0.0)
			_arm(j, "r", 0.3 + 2.55 * _sm(0.0, 0.3, phase) * (1.0 - _sm(0.8, 1.0, phase)), 0.15, 0.4)
			_arm(j, "l", 0.25, 1.0, 0.6)
			_leg(j, "l", 0.55 * (1.0 - hop) + 0.1, 0.9 * (1.0 - hop) + 0.3 * hop, 0.25)
			_leg(j, "r", 0.55 * (1.0 - hop) + 0.1, 0.9 * (1.0 - hop) + 0.3 * hop, 0.25)
			root.y = -0.12 * (1.0 - hop) + 0.17 * hop
			out["air"] = hop
			_flat_feet(j, 1.0 - hop)
			for side in ["l", "r"]:
				j[side + "_foot"] = (j[side + "_foot"] as Vector3) + Vector3(0.6 * hop, 0.0, 0.0)
		"steal":   # a lunging swipe at the ball with the right hand
			var reach := _sm(0.1, 0.4, phase) * (1.0 - _sm(0.55, 1.0, phase))
			j["torso"] = Vector3(0.25 + 0.3 * reach, 0.0, 0.0)
			j["head"] = Vector3(-0.2, 0.0, 0.0)
			_leg(j, "l", 0.6 + 0.6 * reach, 1.0 - 0.2 * reach, 0.25)
			_leg(j, "r", 0.5 - 0.35 * reach, 1.0 + 0.2 * reach, 0.25)
			_arm(j, "r", 0.4 + 1.1 * reach, 0.35 * reach + 0.2, 0.7 - 0.55 * reach)
			_arm(j, "l", 0.25, 1.1, 0.6)
			root.y = -0.14 - 0.03 * reach
			_flat_feet(j, 1.0)
		"block":   # a vertical leap with both arms straight up, a swat at the top
			var up := _sm(0.1, 0.35, phase) * (1.0 - _sm(0.6, 0.85, phase))
			var swat := _sm(0.3, 0.45, phase) * (1.0 - _sm(0.45, 0.6, phase))
			j["torso"] = Vector3(0.1 - 0.15 * up, 0.0, 0.0)
			_arm(j, "r", 0.3 + 2.5 * up + 0.2 * swat, 0.1, 0.25 * (1.0 - up) + 0.1)
			_arm(j, "l", 0.3 + 2.3 * up, 0.5 * up + 0.2, 0.3)
			j["r_hand"] = Vector3(0.6 * swat, 0.0, 0.0)
			_leg(j, "l", 0.5 * (1.0 - up) + 0.1, 0.9 * (1.0 - up) + 0.4 * up, 0.15)
			_leg(j, "r", 0.5 * (1.0 - up) - 0.1 * up, 0.9 * (1.0 - up) + 0.5 * up, 0.15)
			root.y = -0.12 * (1.0 - up) + 0.34 * up
			out["air"] = up
			_flat_feet(j, 1.0 - up)
			for side in ["l", "r"]:
				j[side + "_foot"] = (j[side + "_foot"] as Vector3) + Vector3(0.7 * up, 0.0, 0.0)
		"rebound":   # a jump with both hands up and wide, pulling the ball down to the chest, landing wide
			var up := _sm(0.1, 0.35, phase) * (1.0 - _sm(0.52, 0.72, phase))
			var pull := _sm(0.4, 0.6, phase) * (1.0 - _sm(0.9, 1.0, phase))
			j["torso"] = Vector3(0.12 - 0.12 * up + 0.2 * pull, 0.0, 0.0)
			_arm(j, "l", 0.4 + 2.3 * up * (1.0 - pull) + 0.5 * pull, 0.5 * up + 0.2, 0.35 + 1.0 * pull)
			_arm(j, "r", 0.4 + 2.3 * up * (1.0 - pull) + 0.5 * pull, 0.5 * up + 0.2, 0.35 + 1.0 * pull)
			_leg(j, "l", 0.5 * (1.0 - up) + 0.1, 0.9 * (1.0 - up) + 0.4 * up, 0.25)
			_leg(j, "r", 0.5 * (1.0 - up) + 0.1, 0.9 * (1.0 - up) + 0.4 * up, 0.25)
			root.y = -0.1 * (1.0 - up) + 0.32 * up - 0.06 * pull
			out["air"] = up
			out["grip"] = _sm(0.3, 0.5, phase) * (1.0 - _sm(0.95, 1.0, phase))
			out["ball"] = Vector3(0.0, lerpf(1.1, 0.62, pull), 0.18)
			_flat_feet(j, 1.0 - up)
			for side in ["l", "r"]:
				j[side + "_foot"] = (j[side + "_foot"] as Vector3) + Vector3(0.7 * up, 0.0, 0.0)
		"recover":   # sprinting back on defence: an upright, quick run with the arms pumping and the head up
			j["torso"] = Vector3(0.1, -0.12 * c, 0.0)
			j["pelvis"] = Vector3(0.0, 0.1 * c, 0.0)
			for pair in [["l", s, c], ["r", -s, -c]]:
				var side: String = pair[0]
				_leg(j, side, 0.8 * float(pair[1]) + 0.05, 0.28 + 1.3 * pow(maxf(0.0, float(pair[2])), 1.2), 0.03, 0.2 * maxf(0.0, -float(pair[1])))
				_arm(j, side, -0.9 * float(pair[1]), 0.15, 1.4)
			root.y = -0.03 + 0.04 * absf(c)
			_flat_feet(j, 0.7)
		"sit":   # seated on the bench, hands on the knees, glancing about; the ground contact lowers the hips onto the seat height
			j["torso"] = Vector3(0.1 + 0.02 * s, 0.0, 0.0)
			j["head"] = Vector3(-0.1, 0.35 * sin(th * 1.0 + 0.5) * 0.6, 0.0)
			j["neck"] = Vector3(0.0, 0.2 * sin(th + 0.5), 0.0)
			_arm(j, "l", 0.35, 0.1, 1.05)
			_arm(j, "r", 0.35, 0.1, 1.05)
			_leg(j, "l", 1.5, 1.55, 0.06)
			_leg(j, "r", 1.5, 1.55, 0.06)
			root.y = -0.2
			_flat_feet(j, 1.0)
		"coach":   # standing on the sideline with the arms folded, watching the play
			j["torso"] = Vector3(0.05, 0.0, 0.0)
			j["head"] = Vector3(-0.05, 0.3 * sin(th), 0.0)
			_arm(j, "l", 0.6, -0.15, 2.3)
			_arm(j, "r", 0.55, -0.15, 2.3)
			_leg(j, "l", 0.12, 0.18, 0.12)
			_leg(j, "r", 0.1, 0.18, 0.12)
			root.y = -0.015
			_flat_feet(j, 1.0)
		"intro":   # being introduced: standing tall, chin up, one arm raised to the crowd and waving, a little rise onto the toes
			var wave := sin(th * 2.0)
			j["torso"] = Vector3(-0.05, 0.0, 0.0)
			j["head"] = Vector3(-0.12, 0.15 * sin(th), 0.0)
			_arm(j, "r", 2.1 + 0.08 * wave, 0.45 + 0.15 * wave, 0.35 + 0.15 * wave)
			_arm(j, "l", 0.12, 0.2, 0.3)
			_leg(j, "l", 0.1, 0.12, 0.08)
			_leg(j, "r", 0.08, 0.12, 0.08)
			root.y = -0.01
			_flat_feet(j, 1.0)
		_:
			pass
	out["root"] = root
	if not (state in AIRBORNE):
		out["air"] = 0.0
	return out


## A blend of two poses: weight 0 is `a`, 1 is `b`. Every joint, the root, the air and grip amounts and the ball anchor move linearly, so a blend never jumps.
static func blend(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var w := clampf(weight, 0.0, 1.0)
	var joints := {}
	for name in JOINTS:
		joints[name] = (a["joints"][name] as Vector3).lerp(b["joints"][name], w)
	return {"joints": joints, "root": (a["root"] as Vector3).lerp(b["root"], w), "air": lerpf(float(a["air"]), float(b["air"]), w),
		"grip": lerpf(float(a["grip"]), float(b["grip"]), w), "ball": (a["ball"] as Vector3).lerp(b["ball"], w)}


## The largest single-joint rotation difference (radians, over any axis) between two poses: the "pop" measure used to find a bad transition.
static func largest_joint_change(a: Dictionary, b: Dictionary) -> float:
	var worst := 0.0
	for name in JOINTS:
		var d: Vector3 = (a["joints"][name] as Vector3) - (b["joints"][name] as Vector3)
		worst = maxf(worst, maxf(absf(d.x), maxf(absf(d.y), absf(d.z))))
	return worst


## The distance the body should travel per second in `state` so the feet do not slide: one full stride loop (left and right step) covers about
## 1.3 body heights when running (a 6.5 ft player runs at about 12 ft/s, well under the reconstruction's 22 ft/s limit), a little more when sprinting
## and less when walking. 0 for the standing states.
static func ground_speed(state: String, height_feet: float) -> float:
	var stride := 0.0   # body heights covered by one loop
	match state:
		"run", "dribble_run", "recover":
			stride = 1.3
		"drive":
			stride = 1.1
		"sprint":
			stride = 1.5
		"walk":
			stride = 0.8
	return stride * height_feet / float(CYCLE[state]) if stride > 0.0 else 0.0
