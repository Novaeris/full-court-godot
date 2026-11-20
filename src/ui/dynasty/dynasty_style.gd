class_name FcDynastyStyle
extends RefCounted
## Colours and small helpers shared by the Dynasty screens. Rarity is the one place that gets strong colour: it must be
## readable at a glance on every card. Everything else follows FcUiTheme.

const RARITY_COLORS := {
	"common": Color(0.62, 0.66, 0.72),
	"uncommon": Color(0.36, 0.78, 0.50),
	"rare": Color(0.32, 0.60, 0.96),
	"epic": Color(0.70, 0.45, 0.96),
	"legendary": Color(0.98, 0.78, 0.28),
}
const FRAME_COLORS := {"none": Color(0, 0, 0, 0), "bronze": Color(0.80, 0.50, 0.28), "silver": Color(0.80, 0.84, 0.90),
	"gold": Color(0.98, 0.80, 0.32), "platinum": Color(0.62, 0.92, 0.94), "diamond": Color(0.58, 0.80, 1.0)}

static var _textures: Dictionary = {}


static func rarity_color(rarity: String) -> Color:
	return RARITY_COLORS.get(rarity, RARITY_COLORS["common"])


static func rarity_label(rarity: String) -> String:
	return rarity.capitalize()


## Card artwork as a texture, or null when there is none or it cannot be read (callers draw the fallback).
static func art_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if _textures.has(path):
		return _textures[path]
	var tex: Texture2D = null
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	_textures[path] = tex
	return tex


static func box(fill: Color, border: Color, width: int = 2, radius: int = 8, pad: int = 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s


static func initials(name: String) -> String:
	var out := ""
	for part in name.split(" ", false):
		if part.length() > 0 and out.length() < 2:
			out += part.substr(0, 1).to_upper()
	return out if out != "" else "?"


static func currency_text(balances: Dictionary) -> String:
	return "Credits %s    Tokens %s    Shards %s" % [_n(int(balances.get("credits", 0))), _n(int(balances.get("tokens", 0))), _n(int(balances.get("shards", 0)))]


static func _n(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if value < 0 else "") + s + out
