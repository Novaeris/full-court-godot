class_name FcUiFonts
extends RefCounted
## The two typefaces: Inter for body text (variable weight, tabular figures for statistics) and Barlow Condensed for
## headings and big numbers (broadcast style). Both are open-licence fonts bundled in assets/fonts (assets/README.md).
## A missing or unreadable font file never fails: the functions return null and Godot's default font is used instead.

const BODY_FILE := "res://assets/fonts/Inter-Variable.ttf"
const DISPLAY_FILES := {500: "res://assets/fonts/BarlowCondensed-Medium.ttf", 600: "res://assets/fonts/BarlowCondensed-SemiBold.ttf", 700: "res://assets/fonts/BarlowCondensed-Bold.ttf"}

static var _cache: Dictionary = {}


## Inter at a weight (400 regular, 500 medium, 600 semibold, 700 bold); `tabular` gives equal-width digits for tables.
static func body(weight: int = 400, tabular: bool = false) -> Font:
	var key := "body:%d:%s" % [weight, tabular]
	if _cache.has(key):
		return _cache[key]
	var base := _load(BODY_FILE)
	var font: Font = null
	if base != null:
		var ts := TextServerManager.get_primary_interface()
		var fv := FontVariation.new()
		fv.base_font = base
		fv.variation_opentype = {ts.name_to_tag("wght"): weight}
		if tabular:
			fv.opentype_features = {ts.name_to_tag("tnum"): 1}
		font = fv
	_cache[key] = font
	return font


## Barlow Condensed at the nearest of Medium (500), SemiBold (600) and Bold (700).
static func display(weight: int = 600) -> Font:
	var key := "display:%d" % weight
	if _cache.has(key):
		return _cache[key]
	var chosen := 500 if weight < 550 else (600 if weight < 650 else 700)
	var font := _load(DISPLAY_FILES[chosen])
	_cache[key] = font
	return font


static func _load(path: String) -> Font:
	if not ResourceLoader.exists(path):
		return null
	var res = load(path)
	return res as Font
