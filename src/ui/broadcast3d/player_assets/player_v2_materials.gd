class_name FcPlayerV2Materials
extends RefCounted
## Materials of the V2 players (D-075), SHARED between players of the same colours: skin (player_skin.gdshader, the identity tone), eyes (an iris texture,
## glossy), brows and lashes (alpha-cut cards tinted by the hair colour). Textures live in assets/players/v2/textures (made from CC0 MakeHuman assets by
## tools/blender/v2/make_textures.py).

const TEX := "res://assets/players/v2/textures/"
const SKIN_SHADER := "res://src/ui/broadcast3d/player_skin.gdshader"

static var _cache: Dictionary = {}


static func _texture(file: String) -> Texture2D:
	var path := TEX + file
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func skin(tone: Color) -> Material:
	var key := "skin|" + tone.to_html(false)
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = load(SKIN_SHADER) as Shader
		m.set_shader_parameter("tone", tone)
		m.set_shader_parameter("detail", _texture("skin_detail.png"))
		m.set_shader_parameter("pores", _texture("skin_normal.png"))
		m.resource_name = "skin"
		_cache[key] = m
	return _cache[key]


static func eyes(iris: String) -> Material:
	var key := "eyes|" + iris
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = _texture("iris_%s.png" % iris)
		m.roughness = 0.12
		m.metallic_specular = 0.7
		m.disable_receive_shadows = true   # tiny, deep-set: the shadow map would bury them in black under the brow
		m.resource_name = "eyes"
		_cache[key] = m
	return _cache[key]


## Brows and lashes: alpha-scissored cards, no sorting problems, tinted by `color`.
static func card(kind: String, file: String, color: Color) -> Material:
	var key := "%s|%s|%s" % [kind, file, color.to_html(false)]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = _texture(file)
		m.albedo_color = color
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR   # the card colour is white; the hair colour tints it
		m.alpha_scissor_threshold = 0.5
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.disable_receive_shadows = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.85
		m.resource_name = kind
		_cache[key] = m
	return _cache[key]


static func hair(color: Color) -> Material:
	var key := "hair|" + color.to_html(false)
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://src/ui/broadcast3d/player_hair.gdshader") as Shader
		m.set_shader_parameter("hair_color", color)
		m.resource_name = "hair"
		_cache[key] = m
	return _cache[key]


static func clear_cache() -> void:
	_cache.clear()
