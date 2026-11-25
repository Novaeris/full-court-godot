class_name FcPlayerMorphs
extends RefCounted
## The morph weights of a V2 player (D-075): which of the eight body types the player has and how strongly every body (fcb_) and face (fcf_) morph applies.
## PURE and DETERMINISTIC: it reads the identity from FcPlayerVisual.resolve() and the body archetype (height, mass, muscle, position) and hashes the
## stable key, never a random number, so a player looks the same in every mode, every session and every portrait, and nothing new is saved.
## Body: the type sets the base shape, mass and muscle are added on top (two centres are not twins). Face: the identity choices (face id, jaw, nose,
## mouth, brow, eye size, face width) pick the main morphs; the key adds a spread of secondary ones and a little asymmetry.

const DATA_PATH := "res://data/player_pipeline/v2_bodies.json"
const HEAD_SHAPES := ["fcf_head_oval", "fcf_head_round", "fcf_head_square", "fcf_head_rect", "fcf_head_triangle", "fcf_head_invtriangle", "fcf_head_diamond"]
## Secondary face morphs the key spreads over every player (scaled down so no face is a caricature).
const SECONDARY := ["fcf_cheekbones", "fcf_cheeks_full", "fcf_cheeks_hollow", "fcf_forehead_tall", "fcf_forehead_slope", "fcf_brow_ridge", "fcf_nose_tip_wide",
	"fcf_nose_tip_up", "fcf_nose_big", "fcf_nose_flat", "fcf_lips_full", "fcf_lips_thin", "fcf_eyes_apart", "fcf_eyes_close", "fcf_eyes_hooded", "fcf_eyes_tilt",
	"fcf_ears_big", "fcf_ears_out", "fcf_chin_wide", "fcf_chin_long", "fcf_chin_cleft", "fcf_head_long", "fcf_mouth_wide", "fcf_mouth_narrow"]
const ASYMMETRY := ["fcf_asym_jaw", "fcf_asym_nose", "fcf_asym_eye", "fcf_asym_mouth"]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {}
	return _data


## A steady value in [0, 1) for a key and a purpose.
static func unit(key: String, purpose: String) -> float:
	return float(FcPlayerVisual.fnv1a("%s|v2|%s" % [key, purpose]) % 10000) / 10000.0


## The body type name for a body archetype (FcBodyArchetype.make).
static func body_type(archetype: Dictionary) -> String:
	var mass := float(archetype.get("mass", 0.4))
	var muscle := float(archetype.get("muscle", 0.5))
	match int(archetype.get("position", 3)):
		1:
			return "lean_guard" if mass < 0.4 else "athletic_guard"
		2:
			return "athletic_guard" if mass >= 0.3 else "lean_guard"
		3:
			return "muscular_wing" if muscle > 0.6 else "standard_wing"
		4:
			return "strong_forward" if mass > 0.55 or muscle > 0.75 else "athletic_forward"
		_:
			return "heavy_center" if mass > 0.62 else "traditional_center"


## {morph name: weight 0..1} for a player.
static func weights(identity: Dictionary, archetype: Dictionary, key: String) -> Dictionary:
	var out := {}
	var types: Dictionary = data().get("types", {})
	var body: Dictionary = types.get(body_type(archetype), {})
	for m in body:
		out[m] = float(body[m])
	var mass := float(archetype.get("mass", 0.4))
	var muscle := float(archetype.get("muscle", 0.5))
	_add(out, "fcb_mass_up" if mass > 0.5 else "fcb_mass_down", absf(mass - 0.5) * 0.8)
	_add(out, "fcb_muscle_up" if muscle > 0.5 else "fcb_muscle_down", absf(muscle - 0.5) * 0.6)
	# face: the identity choices first
	var props: Dictionary = identity.get("proportions", {})
	var face_index := clampi(int(str(identity.get("face", "face_1")).trim_prefix("face_")) - 1, 0, 5)
	var shape: String = HEAD_SHAPES[(face_index + FcPlayerVisual.fnv1a(key + "|v2shape")) % HEAD_SHAPES.size()]
	out[shape] = 0.3 + 0.4 * unit(key, "shape")
	match int(props.get("jaw", 0)):
		0: _add(out, "fcf_head_round", 0.25)
		1: _add(out, "fcf_jaw_wide", 0.5 + 0.4 * unit(key, "jaw")); _add(out, "fcf_head_square", 0.25)
		2: _add(out, "fcf_jaw_narrow", 0.4 + 0.4 * unit(key, "jaw")); _add(out, "fcf_chin_out", 0.4)
	match int(props.get("nose", 0)):
		0: _add(out, "fcf_nose_narrow", 0.3 + 0.5 * unit(key, "nose"))
		1: _add(out, "fcf_nose_wide", 0.4 + 0.5 * unit(key, "nose"))
		2: _add(out, "fcf_nose_long", 0.3 + 0.4 * unit(key, "nose")); _add(out, "fcf_nose_hump", 0.5 * unit(key, "hump"))
	match int(props.get("mouth", 1)):
		0: _add(out, "fcf_mouth_wide", 0.35)
		2: _add(out, "fcf_mouth_corners_down", 0.3 + 0.3 * unit(key, "mouth"))
	match int(props.get("brow", 1)):
		0: _add(out, "fcf_brows_angled", 0.4)
		2: _add(out, "fcf_brows_low", 0.5); _add(out, "fcf_brow_ridge", 0.4)
	var eye := int(props.get("eye_size", 100))
	if eye > 100:
		_add(out, "fcf_eyes_big", 0.5)
	elif eye < 100:
		_add(out, "fcf_eyes_small", 0.5)
	var fw := float(props.get("face_w", 86))
	_add(out, "fcf_head_wide" if fw > 86 else "fcf_head_narrow", absf(fw - 86.0) / 6.0 * 0.45)
	# the key spreads secondary morphs and a little asymmetry
	for m in SECONDARY:
		if unit(key, m) < 0.38:
			_add(out, m, 0.15 + 0.5 * unit(key, m + "|w"))
	for m in ASYMMETRY:
		_add(out, m, 0.35 * unit(key, m))
	for m in out.keys():
		out[m] = clampf(float(out[m]), 0.0, 1.0)
	return out


static func _add(out: Dictionary, name: String, amount: float) -> void:
	out[name] = float(out.get(name, 0.0)) + amount


## The V2 part meshes a player wears: hair style, facial hair, headband and equipment, chosen from the identity and the key (deterministic).
static func parts(identity: Dictionary, key: String) -> Array[String]:
	var out: Array[String] = []
	var hair: Array = (data().get("hair", {}) as Dictionary).get(str(identity.get("hair", "short")), [])
	if not hair.is_empty():
		out.append(str(hair[FcPlayerVisual.fnv1a(key + "|v2hair") % hair.size()]))
	var facial: Array = (data().get("facial_hair", {}) as Dictionary).get(str(identity.get("facial_hair", "none")), [])
	if not facial.is_empty():
		out.append(str(facial[FcPlayerVisual.fnv1a(key + "|v2facial") % facial.size()]))
	if int((identity.get("proportions", {}) as Dictionary).get("accessory", 0)) == 1:
		out.append("acc_headband")
	var equip: Dictionary = data().get("equipment", {})
	for piece in ["equip_armsleeve", "equip_kneesleeve", "equip_wristband"]:
		if FcPlayerVisual.fnv1a(key + "|" + piece) % 100 < int(equip.get(piece, 0)):
			if piece == "equip_armsleeve":
				out.append(piece + ("_r" if FcPlayerVisual.fnv1a(key + "|sleeve_side") % 3 > 0 else "_l"))
			else:
				out.append(piece + "_l")
				out.append(piece + "_r")
	return out


## The iris texture name for an identity (eye colour is not stored: it follows the skin tone and the key).
static func eye_color(identity: Dictionary, key: String) -> String:
	var table: Dictionary = data().get("eye_colors_by_tone", {})
	var choices: Array = table.get(str(identity.get("skin", "tone_3")), ["brown"])
	return str(choices[FcPlayerVisual.fnv1a(key + "|v2eye") % choices.size()])


## The brow mesh for an identity (thin, medium, thick, or the key's fourth style).
static func brow(identity: Dictionary, key: String) -> String:
	var brows: Array = data().get("brows", ["brow_001"])
	var b := int((identity.get("proportions", {}) as Dictionary).get("brow", 1))
	if FcPlayerVisual.fnv1a(key + "|v2brow") % 5 == 0:
		return str(brows[brows.size() - 1])
	return str(brows[clampi(b, 0, brows.size() - 1)])
