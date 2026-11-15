class_name FcPlayerRatings
extends RefCounted
## Turns a player's 28 attributes into the composite ratings the game
## simulation uses (three, mid, finishing, playmaking, perimeter_d...) and one
## "overall". The recipes live in data/simulation/ratings.json so balance
## changes need no code. Every composite is on the same 0-100 scale as an
## attribute.

const DATA_PATH := "res://data/simulation/ratings.json"

var composites: Dictionary = {}
var overall_weights: Dictionary = {}
var load_errors: Array[String] = []


static func load_default() -> FcPlayerRatings:
	var r := FcPlayerRatings.new()
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		r.load_errors.append("cannot open %s" % DATA_PATH)
		return r
	var parsed = FcChecks.parse_json(file.get_as_text())
	if not (parsed is Dictionary):
		r.load_errors.append("%s is not valid JSON" % DATA_PATH)
		return r
	r.composites = parsed.get("composites", {})
	r.overall_weights = parsed.get("overall", {})
	return r


## Every attribute key used must exist in the catalog; weights must be positive.
func validate(catalog: FcAttributeCatalog) -> Array[String]:
	var errors: Array[String] = load_errors.duplicate()
	if composites.is_empty():
		errors.append("no composites defined")
	var groups: Dictionary = composites.duplicate()
	groups["overall"] = overall_weights
	for name in groups:
		var total := 0.0
		for key in groups[name]:
			if not catalog.has_key(str(key)):
				errors.append("composite '%s' uses unknown attribute '%s'" % [name, key])
			if float(groups[name][key]) <= 0.0:
				errors.append("composite '%s' has a non-positive weight for '%s'" % [name, key])
			total += float(groups[name][key])
		if total <= 0.0:
			errors.append("composite '%s' has no weight" % name)
	return errors


## The weighted average of attributes for one recipe.
func composite_of(player: FcPlayer, recipe: Dictionary) -> float:
	var total := 0.0
	var weight := 0.0
	for key in recipe:
		var w := float(recipe[key])
		total += player.attributes.get_value(str(key)) * w
		weight += w
	return total / weight if weight > 0.0 else 50.0


func overall(player: FcPlayer) -> float:
	return composite_of(player, overall_weights)


## All composites for a player, plus "overall" and "scoring" (how dangerous he
## is as a scorer: the best of his shooting/finishing mixed with shot creation).
func compute(player: FcPlayer) -> Dictionary:
	var out := {}
	for name in composites:
		out[name] = composite_of(player, composites[name])
	out["overall"] = overall(player)
	out["scoring"] = 0.6 * maxf(out["three"], maxf(out["mid"], out["finishing"])) + 0.4 * out["creation"]
	out["stamina"] = float(player.attributes.get_value("stamina"))
	return out
