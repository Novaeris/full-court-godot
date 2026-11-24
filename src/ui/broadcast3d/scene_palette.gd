class_name FcScenePalette
extends RefCounted
## The fixed colours of the 3D arena (wood, rim, glass, furniture, officials), read once from data/ui/scene_palette.json so no colour is scattered
## through the scene code. A missing name returns magenta, which is easy to spot in a picture.

static var _colours: Dictionary = {}


static func color(name: String) -> Color:
	if _colours.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/scene_palette.json"))
		_colours = parsed if parsed is Dictionary else {"missing": "FFFFFF"}
	return Color.html(str(_colours[name])) if _colours.has(name) else Color.MAGENTA


## Every colour name in the file (for the test that proves each one parses).
static func names() -> Array:
	color("missing")
	return _colours.keys()
