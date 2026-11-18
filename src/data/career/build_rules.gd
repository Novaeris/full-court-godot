class_name FcBuildRules
extends RefCounted
## The numbers behind Career Mode player builds (data/career/build_rules.json), loaded once. Kept in the data layer so
## profiles and builds can both read them; the validation logic itself lives in FcPlayerBuild (src/career).

static var _cache: Dictionary = {}


static func rules() -> Dictionary:
	if _cache.is_empty():
		var file := FileAccess.open("res://data/career/build_rules.json", FileAccess.READ)
		var parsed = FcChecks.parse_json(file.get_as_text()) if file != null else null
		_cache = parsed if parsed is Dictionary else {}
	return _cache
