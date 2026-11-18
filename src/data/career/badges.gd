class_name FcBadges
extends RefCounted
## The badge catalog of Career Mode (data/career/badges.json). Badges are data: a requirement block, a skill-point cost and small,
## capped effects on the simulation's composite ratings. Adding a badge never needs code.

static var _cache: Dictionary = {}


static func _load() -> Dictionary:
	if _cache.is_empty():
		var file := FileAccess.open("res://data/career/badges.json", FileAccess.READ)
		var parsed = FcChecks.parse_json(file.get_as_text()) if file != null else null
		_cache = parsed if parsed is Dictionary else {"badges": [], "bonus_cap": 4}
	return _cache


static func all() -> Array:
	return _load().get("badges", [])


static func get_badge(key: String) -> Dictionary:
	for b in all():
		if b["key"] == key:
			return b
	return {}


static func keys() -> Array:
	return all().map(func(b): return b["key"])


## The most any single composite rating can gain from badges together.
static func bonus_cap() -> int:
	return int(_load().get("bonus_cap", 4))
