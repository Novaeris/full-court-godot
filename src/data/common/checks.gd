class_name FcChecks
extends RefCounted
## Small shared validation helpers. Validation functions across the data model
## return an Array[String] of human-readable problems (empty = valid).


## Lowercase identifier such as "three_point". Used for attribute keys.
static func is_snake_key(value: String) -> bool:
	var re := RegEx.new()
	re.compile("^[a-z][a-z0-9_]*$")
	return re.search(value) != null


## Color in "#RRGGBB" form.
static func is_hex_color(value: String) -> bool:
	var re := RegEx.new()
	re.compile("^#[0-9A-Fa-f]{6}$")
	return re.search(value) != null


## 2 to 4 uppercase letters, e.g. "HBR".
static func is_abbreviation(value: String) -> bool:
	var re := RegEx.new()
	re.compile("^[A-Z]{2,4}$")
	return re.search(value) != null


static func is_blank(value: String) -> bool:
	return value.strip_edges().is_empty()


## Rounds a float to a fixed number of decimals in a way that survives saving.
## Godot's JSON writes floats with ~14 significant digits, so an arbitrary
## double changes in its last bits after save + load. A value that came from
## text with few decimals does not. RULE: floats in saved data go through this.
static func quantize(value: float, decimals: int = 3) -> float:
	return String.num(value, decimals).to_float()


## Parses JSON text without printing engine errors. Returns null if invalid.
## (JSON.parse_string logs an ERROR for bad input, which is noise when we
## EXPECT to handle damaged files.)
static func parse_json(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data
