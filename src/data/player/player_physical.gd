class_name FcPlayerPhysical
extends RefCounted
## Body measurements. Metric units internally; the UI converts for display.
## Note: these are measurements, not ratings. Speed/strength/etc. live in the
## attribute system; height and wingspan will feed into simulation formulas.

enum Handedness { RIGHT = 0, LEFT = 1, BOTH = 2 }

const MIN_HEIGHT_CM := 150
const MAX_HEIGHT_CM := 250
const MIN_WEIGHT_KG := 50
const MAX_WEIGHT_KG := 200

var height_cm: int = 198
var weight_kg: int = 95
var wingspan_cm: int = 203
var handedness: int = Handedness.RIGHT


func validate() -> Array[String]:
	var errors: Array[String] = []
	if height_cm < MIN_HEIGHT_CM or height_cm > MAX_HEIGHT_CM:
		errors.append("height %d cm is out of range" % height_cm)
	if weight_kg < MIN_WEIGHT_KG or weight_kg > MAX_WEIGHT_KG:
		errors.append("weight %d kg is out of range" % weight_kg)
	if wingspan_cm < MIN_HEIGHT_CM or wingspan_cm > MAX_HEIGHT_CM + 20:
		errors.append("wingspan %d cm is out of range" % wingspan_cm)
	if handedness < Handedness.RIGHT or handedness > Handedness.BOTH:
		errors.append("invalid handedness %d" % handedness)
	return errors


func to_dict() -> Dictionary:
	return {
		"height_cm": height_cm, "weight_kg": weight_kg,
		"wingspan_cm": wingspan_cm, "handedness": handedness,
	}


static func from_dict(data: Dictionary) -> FcPlayerPhysical:
	var p := FcPlayerPhysical.new()
	p.height_cm = int(data.get("height_cm", p.height_cm))
	p.weight_kg = int(data.get("weight_kg", p.weight_kg))
	p.wingspan_cm = int(data.get("wingspan_cm", p.wingspan_cm))
	p.handedness = int(data.get("handedness", p.handedness))
	return p
