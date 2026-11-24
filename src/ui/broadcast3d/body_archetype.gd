class_name FcBodyArchetype
extends RefCounted
## The BODY of a 3D player as a plain record of proportions (3D overhaul, M1). PURE and DETERMINISTIC: it depends only on what the game already
## knows (the identity from FcPlayerVisual.resolve, the height and weight, the position) and a stable key, never on a random number and never on
## stored data, so a player always has the same body and nothing new is saved. Every value that is a length is a FRACTION OF THE BODY HEIGHT, so
## the builder scales one skeleton and one mesh recipe to any height (a 5 ft 11 guard and a 7 ft 2 centre are the same kit with different numbers).
##
## What differs between players (docs/plans/3D_FIDELITY_PLAN.md): height, mass (weight for the height), muscle, shoulder and chest size, wingspan
## (arm length), leg length, head size, neck and hand size. Position nudges them the way real positions differ (guards lean and quick, centres
## broad with long arms); the key adds a small steady personal variation so two players of one position are still two people.

const DEFAULT_HEIGHT_CM := 198.0
const DEFAULT_WEIGHT_KG := 95.0
## Typical body-mass index of a basketball player; mass 0 is a lean body, 1 a heavy one.
const BMI_LEAN := 20.0
const BMI_HEAVY := 29.0


## Position number (1 point guard .. 5 centre) from the abbreviation the visual subject carries; 3 when unknown.
static func position_number(abbreviation: String) -> int:
	match abbreviation.to_upper():
		"PG": return 1
		"SG": return 2
		"SF": return 3
		"PF": return 4
		"C": return 5
		"G": return 2
		"F": return 3
	return 3


## A steady value in [0, 1) for a key and a purpose (the same FNV-1a hash the rest of the visual system uses).
static func unit(key: String, purpose: String) -> float:
	return float(FcPlayerVisual.fnv1a("%s|3d|%s" % [key, purpose]) % 10000) / 10000.0


## The body for a resolved visual (FcPlayerVisual.resolve result). Returns a Dictionary of plain numbers (see the keys below).
static func make(visual: Dictionary) -> Dictionary:
	var identity: Dictionary = visual["identity"]
	var body: Dictionary = visual.get("body_in", {})
	var key := str(visual.get("key", ""))
	var height_cm := float(body.get("height_cm", DEFAULT_HEIGHT_CM))
	var weight_kg := float(body.get("weight_kg", DEFAULT_WEIGHT_KG))
	var position := position_number(str(body.get("position", "")))
	var build := int(identity.get("build", 1))
	var bmi := weight_kg / pow(height_cm / 100.0, 2.0)
	var mass := clampf((bmi - BMI_LEAN) / (BMI_HEAVY - BMI_LEAN), 0.0, 1.0)
	var pos_t := float(position - 1) / 4.0   # 0 guard .. 1 centre
	var vary := func(purpose: String, amount: float) -> float: return (unit(key, purpose) - 0.5) * 2.0 * amount
	var height_feet := height_cm / 30.48
	# the width factor the first 3D prototype used (kept: it is tested and the viewer reads it)
	var width_scale := clampf(weight_kg / (height_cm * 0.48), 0.78, 1.3) * (0.95 + 0.05 * float(build))
	var muscle := clampf(0.25 + 0.2 * float(build) + 0.25 * pos_t + vary.call("muscle", 0.12), 0.0, 1.0)
	var bulk := mass * 0.7 + muscle * 0.3   # overall thickness of limbs and torso, 0 to 1
	var props: Dictionary = identity.get("proportions", {})
	return {
		"height_feet": height_feet,
		"width_scale": width_scale,
		"mass": mass,
		"muscle": muscle,
		"bulk": bulk,
		"position": position,
		# lengths, fractions of the height
		"wingspan": 1.0 + 0.018 + 0.026 * pos_t + vary.call("wingspan", 0.02),            # arm span over height: guards about 1.02, bigs about 1.06
		"leg_ratio": 1.0 - 0.018 * pos_t + vary.call("legs", 0.012),                         # relative leg length (bigs a little longer in the torso)
		"head_h": clampf(0.127 - (height_feet - 6.5) * 0.012 + vary.call("head", 0.004), 0.112, 0.138),   # head height; taller players have relatively smaller heads
		"neck_r": 0.030 + 0.010 * bulk + 0.003 * pos_t,
		"shoulder_x": 0.108 + 0.012 * bulk + 0.006 * pos_t + vary.call("shoulders", 0.004),   # half the distance between the shoulder joints
		"chest_rx": 0.086 + 0.020 * bulk + 0.004 * pos_t,
		"chest_rz": 0.054 + 0.012 * bulk,
		"waist_rx": 0.070 + 0.014 * bulk,
		"waist_rz": 0.050 + 0.010 * bulk,
		"hip_rx": 0.084 + 0.014 * bulk,
		"hip_rz": 0.056 + 0.010 * bulk,
		"arm_r": 0.025 + 0.008 * bulk + 0.003 * muscle,    # upper arm radius
		"forearm_r": 0.020 + 0.005 * bulk + 0.002 * muscle,
		"thigh_r": 0.047 + 0.011 * bulk + 0.003 * muscle,
		"calf_r": 0.030 + 0.006 * bulk + 0.003 * muscle,
		"hand": 0.92 + 0.12 * pos_t + vary.call("hand", 0.04),   # hand size factor
		"foot": 0.94 + 0.10 * pos_t + vary.call("foot", 0.03),
		# the face: the 2D identity already carries these (docs: FcPlayerVisual.proportions), so the 3D head and the 2D portrait agree
		"face_w": float(props.get("face_w", 84)) / 84.0,
		"jaw": int(props.get("jaw", 0)),
		"eye_gap": float(props.get("eye_gap", 35)) / 35.0,
		"eye_size": float(props.get("eye_size", 100)) / 100.0,
		"brow": int(props.get("brow", 1)),
		"nose": int(props.get("nose", 1)),
		"mouth": int(props.get("mouth", 1)),
		"headband": int(props.get("accessory", 0)) == 1,
		"shoe": int(FcPlayerVisual.fnv1a(key + "|shoe") % 4),
	}


## A short text of the main numbers, for the showcase and tests.
static func describe(archetype: Dictionary) -> String:
	return "%.2f ft, mass %.2f, muscle %.2f, wingspan x%.3f, shoulders %.3f, head %.3f" % [archetype["height_feet"], archetype["mass"], archetype["muscle"], archetype["wingspan"], archetype["shoulder_x"], archetype["head_h"]]
