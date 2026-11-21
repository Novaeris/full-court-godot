class_name FcPlayerTraits
extends RefCounted
## EXTRA face and body variation for the high-fidelity figure (FcPlayerFigureHd), derived from the player's key by hash ONLY.
## Why this exists: FcPlayerVisual.resolve is pinned by a golden test (tests/support/player_identity_golden.json) and must not change, and
## FcPlayer must not get a new appearance field (save compatibility). So the new detail (eye shape, nose width, lip fullness, ear size,
## hairline, tattoos, undertone, age marks ...) is NEVER stored and NEVER random: it is recomputed from the same key every time, in a
## separate salt space ("|t_"), so adding it cannot change any existing identity field.
## Age: an optional input (a subject may pass its real age; Owner and Career players age every season). The same face then shows more
## lines, a higher hairline and grey temples as the player gets older; with no age given, a stable age of 19 to 38 is derived from the key.
## Every value is a small integer, so the description compares exactly (tests/unit/test_player_traits.gd).

const MIN_AGE := 18
const MAX_AGE := 45
## Skin undertone shifts (r, g, b), applied on top of the tone: 0 olive, 1 neutral, 2 golden, 3 rosy, 4 cool.
const UNDERTONES := [Vector3(-0.015, 0.012, -0.012), Vector3(0.0, 0.0, 0.0), Vector3(0.022, 0.012, -0.03), Vector3(0.03, -0.014, -0.004), Vector3(-0.022, -0.006, 0.022)]
const IRIS_COLORS := [Color("2A1A10"), Color("4A2C17"), Color("6B4423"), Color("5A5A32"), Color("3F5F7A")]


static func _h(key: String, salt: String, modulo: int) -> int:
	return FcPlayerVisual.fnv1a("%s|t_%s" % [key, salt]) % modulo


## The traits of `key` at `age` (0 or less: the key's own stable age).
static func of(key: String, age: int = 0) -> Dictionary:
	var base_age := MIN_AGE + 1 + _h(key, "age", 20)   # 19 to 38
	var shown_age := base_age if age <= 0 else clampi(age, MIN_AGE, MAX_AGE)
	var iris_roll := _h(key, "iris", 24)
	return {
		"age": shown_age,
		"forehead": _h(key, "forehead", 3),    # 0 low hairline, 2 high
		"cheek": _h(key, "cheek", 3),          # 0 lean, 2 full
		"chin": _h(key, "chin", 3),            # 0 narrow, 2 broad
		"cleft": 1 if _h(key, "cleft", 6) == 0 else 0,
		"eye_shape": _h(key, "eye_shape", 3),  # 0 almond, 1 round, 2 hooded
		"eye_tilt": _h(key, "eye_tilt", 3) - 1,
		"iris": 4 if iris_roll == 0 else (3 if iris_roll == 1 else _h(key, "iris2", 3)),
		"brow_arch": _h(key, "brow_arch", 3),
		"nose_w": _h(key, "nose_w", 3),        # 0 narrow, 2 wide
		"nose_bridge": _h(key, "nose_bridge", 3),
		"lips": _h(key, "lips", 3),            # 0 thin, 2 full
		"ear": _h(key, "ear", 3),
		"neck": _h(key, "neck", 3),
		"slope": _h(key, "slope", 3),          # shoulder slope: 0 square, 2 sloped
		"undertone": _h(key, "undertone", 5),
		"hair_variant": _h(key, "hair_variant", 3),
		"recession": _h(key, "recession", 4),  # 0 none ... 3 a lot (only shows with age)
		"tattoo": _h(key, "tattoo", 7),        # 0 left arm, 1 right arm, else none
		"sleeve": 1 if _h(key, "sleeve", 9) == 0 else 0,
		"chain": 1 if _h(key, "chain", 8) == 0 else 0,
		"earring": 1 if _h(key, "earring", 7) == 0 else 0,
		"grey": _grey_level(key, shown_age),
		"lines": clampi((shown_age - 24) / 5, 0, 3),   # 0 smooth ... 3 weathered
	}


## 0 none, 1 a few grey hairs at the temples, 2 salt and pepper, 3 mostly grey. It depends on the age and a per-key tendency (some go grey early).
static func _grey_level(key: String, age: int) -> int:
	var early := _h(key, "grey", 4)   # 0 to 3 years-of-ten shifted
	var effective := age + early * 2
	if effective < 34:
		return 0
	if effective < 39:
		return 1
	if effective < 44:
		return 2
	return 3


## The skin colour with the undertone and the existing warmth applied (a small shift, never a different skin tone).
static func skin(base: Color, warmth: int, undertone: int) -> Color:
	var shift: Vector3 = UNDERTONES[clampi(undertone, 0, UNDERTONES.size() - 1)]
	return Color(clampf(base.r + shift.x + 0.025 * warmth, 0.0, 1.0), clampf(base.g + shift.y, 0.0, 1.0), clampf(base.b + shift.z - 0.02 * warmth, 0.0, 1.0))


## Hair colour after greying (only a lighter mix at 1 to 3; the base colour is the identity's own).
static func greyed(base: Color, grey: int) -> Color:
	return base.lerp(Color(0.68, 0.68, 0.7), [0.0, 0.18, 0.45, 0.8][clampi(grey, 0, 3)])
