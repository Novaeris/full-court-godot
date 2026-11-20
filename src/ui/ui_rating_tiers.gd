class_name FcUiRatingTiers
extends RefCounted
## Maps a rating (0 to 99) to a tier name and colour, from data/ui/rating_tiers.json so the ramp can be rebalanced without code.

const DEFAULT_PATH := "res://data/ui/rating_tiers.json"

var _tiers: Array[Dictionary] = []


## Loads the tiers. A missing or invalid file leaves a single neutral tier (the UI keeps working).
static func load_default(path: String = DEFAULT_PATH) -> FcUiRatingTiers:
	var out := FcUiRatingTiers.new()
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text) if text != "" else null
	if parsed is Dictionary:
		for t in parsed.get("tiers", []):
			if t is Dictionary and t.has("min") and FcChecks.is_hex_color("#" + str(t.get("color", ""))):
				out._tiers.append({"min": int(t["min"]), "name": str(t.get("name", "")), "color": Color("#" + str(t["color"]))})
		out._tiers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["min"] < b["min"])
	if out._tiers.is_empty():
		out._tiers.append({"min": 0, "name": "", "color": FcUiTokens.TEXT_MUTED})
	return out


## The tier a rating falls in: {"min", "name", "color"}.
func tier_for(value: int) -> Dictionary:
	var chosen: Dictionary = _tiers[0]
	for t in _tiers:
		if value >= int(t["min"]):
			chosen = t
	return chosen


func color_for(value: int) -> Color:
	return tier_for(value)["color"]


func tier_count() -> int:
	return _tiers.size()


## Every tier's colour (tests check each one is readable).
func colors() -> Array[Color]:
	var out: Array[Color] = []
	for t in _tiers:
		out.append(t["color"])
	return out
