class_name FcBrand
extends RefCounted
## The Full Court (game) and Novaeris (studio) logos for the UI. Asset ids and files come from data/ui/brand.json. Rules:
##   - Full Court dominates the game (menu, loading, window); Novaeris appears at startup, in the credits and as a small mark in
##     footers. Never both large on one screen.
##   - A missing or unreadable file never fails: logo() falls back to a text wordmark, so tests, headless runs and a broken install
##     still show a name (docs/ASSET_SPEC.md, "Fallback").
##   - A logo is drawn from the smallest prepared size that is at least as wide as the space it needs, so it is never stretched up and
##     never squeezed down by a large factor (which would look jagged without mipmaps).

const MANIFEST := "res://data/ui/brand.json"
const FULL_COURT := "full_court_lockup"
const NOVAERIS := "novaeris_lockup"
const NOVAERIS_MARK := "novaeris_mark"
const NOVAERIS_WORDMARK := "novaeris_wordmark"

static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}


static func _assets() -> Dictionary:
	if _manifest.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		_manifest = parsed if parsed is Dictionary else {"assets": {}}
	return _manifest.get("assets", {})


## True when the manifest names `id` and its file loads.
static func has(id: String) -> bool:
	return texture(id) != null


## The texture of logo `id` for a space `min_width` pixels wide (0 = the master). Null when it is missing.
static func texture(id: String, min_width: int = 0) -> Texture2D:
	var asset: Dictionary = _assets().get(id, {})
	if asset.is_empty():
		return null
	var path := str(asset.get("file", ""))
	if min_width > 0:
		var best := 0
		for w in asset.get("sizes", {}):
			var width := int(w)
			if width >= min_width and (best == 0 or width < best):
				best = width
		if best > 0:
			path = str(asset["sizes"][str(best)])
	return _load("res://" + path)


static func _load(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_textures[path] = tex
	return tex


## A control showing logo `id` `width` pixels wide (height follows the picture). Without the file it is a text wordmark `fallback_text`.
## The control carries the brand name as its tooltip and name, so it is always identifiable (tests and screen readers).
static func logo(id: String, width: int, fallback_text: String) -> Control:
	var tex := texture(id, int(width * 1.0))
	if tex == null:
		var label := FcUiTables.label(fallback_text, FcUiTokens.TYPE_DISPLAY_XL, true)
		label.name = "Logo"
		label.tooltip_text = fallback_text
		return label
	var rect := TextureRect.new()
	rect.name = "Logo"
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(width, width * float(tex.get_height()) / float(tex.get_width()))
	rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.tooltip_text = fallback_text
	rect.set_meta("brand_id", id)
	rect.set_meta("brand_text", fallback_text)
	return rect
