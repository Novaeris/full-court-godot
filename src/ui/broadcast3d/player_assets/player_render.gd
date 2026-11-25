class_name FcPlayerRender
extends Node
## Portraits RENDERED FROM THE 3D PLAYER (Production Phase M1, docs/development/PLAYER_ASSET_LIBRARY.md). The same library model that plays in the broadcast
## is photographed once in a small off-screen viewport (orthographic camera, head and shoulders, fixed lighting, transparent background) and the picture is
## kept as a texture, so a profile portrait, a card, a Dynasty scouting card, a Career profile and Creator Studio all show the person the broadcast shows.
## Rules:
##   - DETERMINISTIC: the picture depends only on the player look (identity, face proportions, build, height and weight, team colours, number), never on a
##     random number. The cache key holds all of that plus MODEL_VERSION, so a new look (a trade, a new haircut) or a new model is a new picture, and an
##     unchanged player is never rendered twice.
##   - DEFERRED: texture_for() returns what is cached or null at once and queues the render; renders run one at a time, a few frames each, and `rendered`
##     is emitted so a screen redraws. No menu waits for a render.
##   - FALLBACK: when it returns null (no renderer, the model is missing, the picture is still being made) the caller draws the existing 2D figure, which
##     stays available and unchanged. Off by default (`enabled`); screens opt in.
##   - BOUNDED: at most `max_textures` pictures are kept (oldest forgotten first).
## One instance lives in the scene tree under the root (made on first use).

signal rendered(key: String)

const MODEL_VERSION := 2
const SIZE := 256

static var enabled: bool = FcPlayerAssetLibrary.promoted()
static var max_textures: int = 192
## The model portraits are made from: the V2 players (D-075).
static var model: String = "v2"
static var _shared: FcPlayerRender = null
static var _cache: Dictionary = {}      # key -> ImageTexture
static var _order: Array[String] = []

var _queue: Array = []                  # [key, subject]
var _busy: bool = false


## True when a picture can be rendered (a rendering device exists).
static func available() -> bool:
	return DisplayServer.get_name() != "headless"


## The subject (what FcBroadcastCharacter.setup takes) for a resolved visual (FcPlayerVisual.resolve), so a portrait is built from the same identity.
static func subject_from_visual(visual: Dictionary) -> Dictionary:
	var identity: Dictionary = visual["identity"]
	var uniform: Dictionary = visual["uniform"]
	var out := {
		"key": str(visual["key"]), "name": "", "jersey": int(uniform.get("number", 0)), "model": model,
		"appearance": {"skin": identity["skin"], "hair": identity["hair"], "face": identity["face"], "facial_hair": identity["facial_hair"]},
		"team": {"primary": "#" + (uniform["primary"] as Color).to_html(false), "secondary": "#" + (uniform["secondary"] as Color).to_html(false),
			"abbreviation": str(uniform.get("abbreviation", "")), "name": str(uniform.get("abbreviation", ""))},
	}
	if visual.has("body_in"):
		out["physical"] = visual["body_in"]
		out["position"] = str((visual["body_in"] as Dictionary).get("position", ""))
	if visual.has("age"):
		out["age"] = visual["age"]
	return out


## Everything that changes the picture.
static func key_for(visual: Dictionary, mode: String = "bust") -> String:
	var identity: Dictionary = visual["identity"]
	var uniform: Dictionary = visual["uniform"]
	return "%d|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [MODEL_VERSION, mode, visual["key"], identity["skin"], identity["hair"], identity["face"], identity["facial_hair"],
		str(identity["build"]), JSON.stringify(identity["proportions"]), (uniform["primary"] as Color).to_html(false), (uniform["secondary"] as Color).to_html(false),
		JSON.stringify(visual.get("body_in", {}))]


## The cached picture, or null (then it is queued, when enabled and possible). Never blocks.
static func texture_for(visual: Dictionary, mode: String = "bust") -> Texture2D:
	if not enabled or not available() or visual.is_empty():
		return null
	var key := key_for(visual, mode)
	if _cache.has(key):
		return _cache[key]
	var host := shared()
	if host != null:
		host.request(key, subject_from_visual(visual), mode)
	return null


static func cached(visual: Dictionary, mode: String = "bust") -> bool:
	return _cache.has(key_for(visual, mode))


## The instance in the scene tree (made on first use); null when there is no tree yet.
static func shared() -> FcPlayerRender:
	if _shared == null or not is_instance_valid(_shared):
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null or tree.root == null:
			return null
		_shared = FcPlayerRender.new()
		_shared.name = "PlayerRender"
		tree.root.add_child.call_deferred(_shared)
	return _shared


func request(key: String, subject: Dictionary, mode: String = "bust") -> void:
	for item in _queue:
		if item[0] == key:
			return
	_queue.append([key, subject, mode])
	_pump.call_deferred()


func _pump() -> void:
	if _busy or _queue.is_empty() or not is_inside_tree():
		return
	_busy = true
	var item: Array = _queue.pop_front()
	await _render(str(item[0]), item[1], str(item[2]))
	_busy = false
	if not _queue.is_empty():
		_pump.call_deferred()


func _render(key: String, subject: Dictionary, mode: String = "bust") -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE * 3 / 2) if mode == "full" else Vector2i(SIZE, SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var character := FcBroadcastCharacter.new().setup(subject, 0.0)
	character.auto_advance = false
	var sky := Environment.new()
	sky.background_mode = Environment.BG_CLEAR_COLOR
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.ambient_light_color = Color.html("#B7C2D6")
	sky.ambient_light_energy = 0.9
	var world := WorldEnvironment.new()
	world.environment = sky
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32.0, 28.0, 0.0)
	sun.light_energy = 1.05
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10.0, -140.0, 0.0)
	fill.light_energy = 0.35
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var h := character.height_feet
	camera.size = h * 1.06 if mode == "full" else h * 0.27
	camera.position = Vector3(0.0, h * (0.5 if mode == "full" else 0.885), h * 3.0)
	viewport.add_child(world)
	viewport.add_child(sun)
	viewport.add_child(fill)
	viewport.add_child(character)
	viewport.add_child(camera)
	camera.current = true
	character.pose_at("idle", 0.0)
	add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := viewport.get_texture().get_image()
	if img != null and not img.is_empty() and character.imported:
		img.generate_mipmaps()
		_store(key, ImageTexture.create_from_image(img))
		rendered.emit(key)
	viewport.queue_free()


static func _store(key: String, tex: ImageTexture) -> void:
	if not _cache.has(key):
		_order.append(key)
	_cache[key] = tex
	while _order.size() > max_textures:
		_cache.erase(_order.pop_front())


static func clear_cache() -> void:
	_cache.clear()
	_order.clear()
