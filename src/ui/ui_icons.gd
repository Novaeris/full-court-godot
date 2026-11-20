class_name FcUiIcons
extends RefCounted
## The Lucide icon set (ISC licence, assets/icons/lucide, see assets/README.md). Icons are white glyphs, so any control can tint
## them with a theme colour. An unknown or missing icon returns null and the control simply shows no icon.

const FOLDER := "res://assets/icons/lucide/"

static var _cache: Dictionary = {}


## The icon's texture, or null when there is no such icon.
static func texture(icon_name: String) -> Texture2D:
	if icon_name == "":
		return null
	if _cache.has(icon_name):
		return _cache[icon_name]
	var path := FOLDER + icon_name + ".svg"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_cache[icon_name] = tex
	return tex


## True when the icon exists in the bundle.
static func has_icon(icon_name: String) -> bool:
	return texture(icon_name) != null


## A tinted icon as a TextureRect (square, `size_px` wide); an empty one when the icon does not exist.
static func rect(icon_name: String, tint: Color = FcUiTokens.TEXT_MUTED, size_px: int = 20) -> TextureRect:
	var r := TextureRect.new()
	r.texture = texture(icon_name)
	r.modulate = tint
	r.custom_minimum_size = Vector2(size_px, size_px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
