class_name FcPlaystyle
extends RefCounted
## A player's style summary ("Sharpshooter / Playmaker"): his two strongest composite ratings, named from data/ui/playstyle_labels.json.
## It is a DISPLAY label derived from numbers the simulation already computed (FcPlayerRatings.compute); nothing in the game reads it back.

const PATH := "res://data/ui/playstyle_labels.json"

static var _data: Dictionary = {}


static func _load() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {"minimum": 58, "labels": {}}
	return _data


## {"primary": name, "secondary": name or "", "text": sentence, "label": "A / B"} from a composites dictionary. "Balanced" when nothing
## reaches the minimum. Ties are broken by composite name, so the result is deterministic.
static func summary(composites: Dictionary) -> Dictionary:
	var data := _load()
	var labels: Dictionary = data["labels"]
	var minimum := float(data.get("minimum", 58))
	var ranked: Array = []
	for key in labels:
		if composites.has(key) and float(composites[key]) >= minimum:
			ranked.append([key, float(composites[key])])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1] or (a[1] == b[1] and str(a[0]) < str(b[0])))
	if ranked.is_empty():
		return {"primary": "Balanced", "secondary": "", "text": "No single standout skill yet.", "label": "Balanced"}
	var first: Dictionary = labels[ranked[0][0]]
	var second: Dictionary = labels[ranked[1][0]] if ranked.size() > 1 else {}
	var label := str(first["name"]) + (" / " + str(second["name"]) if not second.is_empty() else "")
	return {"primary": str(first["name"]), "secondary": str(second.get("name", "")), "text": str(first["text"]), "label": label}


## The composite keys that can be named (for tests and tools).
static func known_composites() -> Array:
	return _load()["labels"].keys()
