class_name FcArchetypes
extends RefCounted
## The archetype catalog of Career Mode (data/career/archetypes.json). Archetypes are recommendations: starting
## bonus points and the positions they suit, never limits. New archetypes are added in the data file only.

static var _cache: Array = []


static func all() -> Array:
	if _cache.is_empty():
		var file := FileAccess.open("res://data/career/archetypes.json", FileAccess.READ)
		var parsed = FcChecks.parse_json(file.get_as_text()) if file != null else null
		if parsed is Dictionary:
			_cache = parsed.get("archetypes", [])
	return _cache


## The archetype with this key, or {} if there is none.
static func get_archetype(key: String) -> Dictionary:
	for a in all():
		if a["key"] == key:
			return a
	return {}


static func keys() -> Array:
	return all().map(func(a): return a["key"])
