class_name FcAttributeDef
extends RefCounted
## Describes ONE kind of rating (e.g. "three_point"): its key, label, category,
## and allowed range. Definitions live in JSON files under data/definitions/,
## so attributes can be added or rebalanced without changing code.
## This class holds no player values; see FcAttributeSet for those.

var key: String = ""
var display_name: String = ""
var category: String = ""
var description: String = ""
var min_value: int = 0
var max_value: int = 100
var default_value: int = 50


func validate() -> Array[String]:
	var errors: Array[String] = []
	if not FcChecks.is_snake_key(key):
		errors.append("attribute key '%s' must be lowercase snake_case" % key)
	if FcChecks.is_blank(display_name):
		errors.append("attribute '%s' needs a display name" % key)
	if FcChecks.is_blank(category):
		errors.append("attribute '%s' needs a category" % key)
	if min_value > max_value:
		errors.append("attribute '%s' has min > max" % key)
	if default_value < min_value or default_value > max_value:
		errors.append("attribute '%s' default is outside its range" % key)
	return errors


func to_dict() -> Dictionary:
	return {
		"key": key, "name": display_name, "category": category,
		"description": description, "min": min_value, "max": max_value,
		"default": default_value,
	}


static func from_dict(data: Dictionary) -> FcAttributeDef:
	var d := FcAttributeDef.new()
	d.key = str(data.get("key", ""))
	d.display_name = str(data.get("name", ""))
	d.category = str(data.get("category", ""))
	d.description = str(data.get("description", ""))
	d.min_value = int(data.get("min", 0))
	d.max_value = int(data.get("max", 100))
	d.default_value = int(data.get("default", 50))
	return d
