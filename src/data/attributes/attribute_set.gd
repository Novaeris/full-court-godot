class_name FcAttributeSet
extends RefCounted
## The VALUES of one entity's ratings (e.g. one player's basketball attributes),
## checked against an FcAttributeCatalog. Values never exist for keys the
## catalog does not define, and never outside the allowed range.
##
## Save compatibility: to_dict() writes every value. from_dict() ignores keys
## that no longer exist, rejects out-of-range values (both recorded in
## `load_warnings`), and fills attributes added later with their defaults.

var load_warnings: Array[String] = []

var _catalog: FcAttributeCatalog
var _values: Dictionary = {}


func _init(catalog: FcAttributeCatalog) -> void:
	_catalog = catalog


func get_catalog() -> FcAttributeCatalog:
	return _catalog


## Rejects unknown keys (ERR_DOES_NOT_EXIST) and out-of-range values
## (ERR_PARAMETER_RANGE_ERROR). Nothing changes on error.
func set_value(key: String, value: int) -> Error:
	var def := _catalog.get_def(key)
	if def == null:
		return ERR_DOES_NOT_EXIST
	if value < def.min_value or value > def.max_value:
		return ERR_PARAMETER_RANGE_ERROR
	_values[key] = value
	return OK


## Like set_value but forces the value into range. Still rejects unknown keys.
func set_clamped(key: String, value: int) -> Error:
	var def := _catalog.get_def(key)
	if def == null:
		return ERR_DOES_NOT_EXIST
	_values[key] = clampi(value, def.min_value, def.max_value)
	return OK


## The stored value, or the catalog default if never set. -1 for unknown keys.
func get_value(key: String) -> int:
	var def := _catalog.get_def(key)
	if def == null:
		return -1
	return int(_values.get(key, def.default_value))


func validate() -> Array[String]:
	var errors: Array[String] = []
	for key in _values:
		var def := _catalog.get_def(key)
		if def == null:
			errors.append("unknown attribute '%s'" % key)
		elif _values[key] < def.min_value or _values[key] > def.max_value:
			errors.append("attribute '%s' out of range" % key)
	return errors


## Every catalog key with its current value.
func to_dict() -> Dictionary:
	var out := {}
	for key in _catalog.keys():
		out[key] = get_value(key)
	return out


static func from_dict(catalog: FcAttributeCatalog, data: Dictionary) -> FcAttributeSet:
	var s := FcAttributeSet.new(catalog)
	for key in data:
		var err := s.set_value(str(key), int(data[key]))
		if err == ERR_DOES_NOT_EXIST:
			s.load_warnings.append("ignored unknown attribute '%s'" % key)
		elif err != OK:
			s.load_warnings.append("rejected out-of-range value for '%s'" % key)
	return s
