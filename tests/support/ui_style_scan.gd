class_name FcUiStyleScan
extends RefCounted
## Counts style literals in the UI code so the redesign cannot quietly go backwards. Per file under src/ui it counts:
##   color        literal colour constructors (Color(...)): colours belong in FcUiTokens
##   font         direct font-size overrides (add_theme_font_size_override): sizes belong in the theme and type scale
##   sized_label  FcUiTables.label(text, <number>...) calls with a literal size
## The theme, the tokens and everything under src/ui/kit, shell, cards and team (crests and team colours are art) are exempt (they are where such values live). test_ui_style_lint.gd
## compares the counts with tests/support/ui_style_baseline.json: a count may fall (migrating a screen) but never rise.

const ROOT := "res://src/ui"
const EXEMPT_FILES := ["res://src/ui/ui_theme.gd", "res://src/ui/ui_tokens.gd"]
const EXEMPT_DIRS := ["res://src/ui/kit/", "res://src/ui/shell/", "res://src/ui/cards/", "res://src/ui/team/"]


## {"res://src/ui/app.gd": {"color": 0, "font": 0, "sized_label": 41}, ...} for every non-exempt file with at least one hit.
static func scan() -> Dictionary:
	var out := {}
	for path in _files(ROOT):
		if path in EXEMPT_FILES or EXEMPT_DIRS.any(func(d: String) -> bool: return path.begins_with(d)):
			continue
		var counts := count_text(FileAccess.get_file_as_string(path))
		if counts["color"] + counts["font"] + counts["sized_label"] > 0:
			out[path] = counts
	return out


## The three counts for a piece of source text (also used by the scanner's own test).
static func count_text(source: String) -> Dictionary:
	var color_re := RegEx.new()
	color_re.compile("\\bColor\\(")
	var sized_re := RegEx.new()
	sized_re.compile("FcUiTables\\.label\\(.*,\\s*\\d+(\\s*,\\s*(true|false))?\\)")
	var colors := 0
	var fonts := 0
	var sized := 0
	for line in source.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#") or code.begins_with("##"):
			continue
		colors += color_re.search_all(code).size()
		if code.contains("add_theme_font_size_override"):
			fonts += 1
		if sized_re.search(code) != null:
			sized += 1
	return {"color": colors, "font": fonts, "sized_label": sized}


static func _files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_files(dir_path.path_join(sub)))
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	out.sort()
	return out
