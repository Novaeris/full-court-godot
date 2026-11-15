class_name FcAttributeCatalog
extends RefCounted
## The loaded list of attribute definitions of one kind (basketball attributes,
## personality traits, or tendencies). Keeps definition order for display.
## Problems found while loading are collected in `load_errors` instead of
## crashing, so bad data files are reported clearly by tests.

var kind: String = ""
var load_errors: Array[String] = []

var _defs: Dictionary = {}
var _order: Array[String] = []


## Adds one definition. Returns OK, or an error if it is invalid or a duplicate.
func add_def(def: FcAttributeDef) -> Error:
	var problems := def.validate()
	if not problems.is_empty():
		load_errors.append_array(problems)
		return ERR_INVALID_DATA
	if _defs.has(def.key):
		load_errors.append("duplicate attribute key '%s'" % def.key)
		return ERR_ALREADY_EXISTS
	_defs[def.key] = def
	_order.append(def.key)
	return OK


func has_key(key: String) -> bool:
	return _defs.has(key)


## Returns the definition, or null if the key is unknown.
func get_def(key: String) -> FcAttributeDef:
	return _defs.get(key, null)


## All keys in file order.
func keys() -> Array[String]:
	return _order.duplicate()


func size() -> int:
	return _order.size()


func categories() -> Array[String]:
	var out: Array[String] = []
	for k in _order:
		var c: String = _defs[k].category
		if not out.has(c):
			out.append(c)
	return out


func keys_in_category(category: String) -> Array[String]:
	var out: Array[String] = []
	for k in _order:
		if _defs[k].category == category:
			out.append(k)
	return out


func is_valid() -> bool:
	return load_errors.is_empty() and not _order.is_empty()


static func from_dict(data: Dictionary) -> FcAttributeCatalog:
	var c := FcAttributeCatalog.new()
	c.kind = str(data.get("kind", ""))
	var entries = data.get("definitions", null)
	if not (entries is Array):
		c.load_errors.append("catalog has no 'definitions' list")
		return c
	for entry in entries:
		if entry is Dictionary:
			c.add_def(FcAttributeDef.from_dict(entry))
		else:
			c.load_errors.append("definition entry is not an object")
	return c


static func from_file(path: String) -> FcAttributeCatalog:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var c := FcAttributeCatalog.new()
		c.load_errors.append("cannot open %s" % path)
		return c
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		var c2 := FcAttributeCatalog.new()
		c2.load_errors.append("%s is not valid JSON object" % path)
		return c2
	return from_dict(parsed)
