class_name FcPlayerAssetLibrary
extends RefCounted
## The player asset registry (Production Phase M1, docs/development/PLAYER_ASSET_LIBRARY.md). It does NOT decide how a player looks: FcPlayerVisual.resolve()
## does, and stays the only identity source. The library turns that identity (and the body archetype) into the NAMES of the pieces that draw it: which body
## file (lean, athletic, heavy), which head (face id x jaw), nose, lips, brow and eyes, which hair style, facial hair and accessory. It then loads the part
## files once (cached), checks every name exists, and attaches the chosen meshes to a skeleton. Anything missing is reported and skipped, never fatal: the
## character falls back to what it has (and, when no body loads, to the generated body).
## Everything here is deterministic and presentation-only; nothing is saved.

const DATA_PATH := "res://data/player_pipeline/asset_library.json"

static var _data: Dictionary = {}
static var _scenes: Dictionary = {}      # path -> PackedScene (or null when missing)
static var _materials: Dictionary = {}   # "kind|colour" -> StandardMaterial3D (shared between players)
static var _validated: Dictionary = {}   # path -> problems from FcPlayerModelValidator (a model is checked once, not once per player)


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {}
	return _data


## The model value that asks the library to choose the body file from the player (instead of one explicit GLB path).
static func library_model() -> String:
	return str(data().get("library_model", "library"))


## True once the founder has approved the library players as the default look (D-074 promotion rule). Off until then: the generated body is the default,
## and 3D-rendered portraits are off. One data flag switches both, so the promotion is a reviewed one-line change.
static func promoted() -> bool:
	return bool(data().get("promoted", false))


## "lean", "athletic" or "heavy" for the body archetype bulk (0 slight, 1 heavy).
static func body_for(bulk: float) -> String:
	var t: Dictionary = data().get("body_bulk_thresholds", {})
	if bulk < float(t.get("lean", 0.3)):
		return "lean"
	if bulk < float(t.get("athletic", 0.56)):
		return "athletic"
	return "heavy"


static func body_path(body: String) -> String:
	return str((data().get("bodies", {}) as Dictionary).get(body, ""))


## The names of every piece for a player: {body, body_path, head, nose, nostrils, lips, brow, eyes, hair, facial, headband, width_scale}. Pure.
static func spec(identity: Dictionary, archetype: Dictionary) -> Dictionary:
	var lib := data()
	var props: Dictionary = identity.get("proportions", {})
	var faces := int(lib.get("face_count", 6))
	var face_index := clampi(int(str(identity.get("face", "face_1")).trim_prefix("face_")) - 1, 0, faces - 1)
	var jaw := clampi(int(props.get("jaw", 0)), 0, int(lib.get("jaw_count", 3)) - 1)
	var nose := clampi(int(props.get("nose", 0)), 0, 2)
	var mouth := clampi(int(props.get("mouth", 1)), 0, 2)
	var brow := clampi(int(props.get("brow", 1)), 0, 2)
	var eyes := clampi((int(props.get("eye_size", 100)) - 90) / 10, 0, 2)
	var hair_style := str(identity.get("hair", "short"))
	var facial_style := str(identity.get("facial_hair", "none"))
	var w: Dictionary = lib.get("face_width_percent", {})
	var wt := clampf((float(props.get("face_w", 86)) - float(w.get("min", 80))) / maxf(float(w.get("max", 92)) - float(w.get("min", 80)), 1.0), 0.0, 1.0)
	var body := body_for(float(archetype.get("bulk", 0.4)))
	return {
		"body": body, "body_path": body_path(body),
		"head": "skin_head_%d%d" % [face_index, jaw], "nose": "nose_%d" % nose, "nostrils": "nostrils_%d" % nose, "lips": "lips_%d" % mouth,
		"brow": "brow_%d" % brow, "eyes": "eyes_%d" % eyes,
		"hair": str((lib.get("hair", {}) as Dictionary).get(hair_style, "")),
		"facial": str((lib.get("facial_hair", {}) as Dictionary).get(facial_style, "")).replace("{jaw}", str(jaw)),
		"headband": str((lib.get("accessories", {}) as Dictionary).get("headband", "")) if int(props.get("accessory", 0)) == 1 else "",
		"width_scale": lerpf(float(w.get("scale_min", 0.94)), float(w.get("scale_max", 1.06)), wt),
	}


## The part file that holds a mesh name ("head" or "hair"), by its prefix.
static func part_file_for(mesh_name: String) -> String:
	var kind := "hair" if (mesh_name.begins_with("hair_") or mesh_name.begins_with("facial_") or mesh_name.begins_with("acc_")) else "head"
	return str((data().get("parts", {}) as Dictionary).get(kind, ""))


## The PackedScene at `path`, cached; null when the file is missing or not imported.
static func scene(path: String) -> PackedScene:
	if path == "":
		return null
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene if ResourceLoader.exists(path) else null
	return _scenes[path]


## Copies the meshes named in `spec` from the part files onto `skeleton`. Returns the problems found (missing files or meshes); the pieces that exist are attached.
static func attach_parts(skeleton: Skeleton3D, spec_in: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var wanted: Array[String] = []
	for key in ["head", "nose", "nostrils", "lips", "brow", "eyes", "hair", "facial", "headband"]:
		if str(spec_in.get(key, "")) != "":
			wanted.append(str(spec_in[key]))
	var by_file := {}
	for mesh_name in wanted:
		var file := part_file_for(mesh_name)
		if not by_file.has(file):
			by_file[file] = []
		(by_file[file] as Array).append(mesh_name)
	for file in by_file:
		var packed := scene(file)
		if packed == null:
			problems.append("part file %s is missing or not imported" % file)
			continue
		var instance := packed.instantiate()
		for mesh_name in by_file[file]:
			var source := instance.find_child(str(mesh_name), true, false) as MeshInstance3D
			if source == null:
				problems.append("part %s is not in %s" % [mesh_name, file])
				continue
			var copy := source.duplicate() as MeshInstance3D
			skeleton.add_child(copy)
			copy.skeleton = NodePath("..")
		instance.free()
	return problems


## Checks the whole registry without a player: every file exists and every name a spec can produce is in its part file. Used by the tests and the validator.
static func registry_problems() -> Array[String]:
	var out: Array[String] = []
	var lib := data()
	if lib.is_empty():
		out.append("the asset library file is missing or not valid JSON")
		return out
	for body in lib.get("bodies", {}):
		var path := str(lib["bodies"][body])
		if not ResourceLoader.exists(path):
			out.append("body %s: %s is missing" % [body, path])
	var names := {}
	for f in int(lib.get("face_count", 6)):
		for j in int(lib.get("jaw_count", 3)):
			names["skin_head_%d%d" % [f, j]] = true
	for k in 3:
		for prefix in ["nose_", "nostrils_", "lips_", "brow_", "eyes_"]:
			names["%s%d" % [prefix, k]] = true
	for style in (lib.get("hair", {}) as Dictionary).values():
		if str(style) != "":
			names[str(style)] = true
	for style in (lib.get("facial_hair", {}) as Dictionary).values():
		if str(style) != "":
			for j in int(lib.get("jaw_count", 3)):
				names[str(style).replace("{jaw}", str(j))] = true
	for style in (lib.get("accessories", {}) as Dictionary).values():
		names[str(style)] = true
	var instances := {}
	for mesh_name in names:
		var file := part_file_for(str(mesh_name))
		if not instances.has(file):
			var packed := scene(file)
			instances[file] = packed.instantiate() if packed != null else null
		if instances[file] == null:
			out.append("part file %s is missing" % file)
		elif (instances[file] as Node).find_child(str(mesh_name), true, false) == null:
			out.append("part %s is not in %s" % [mesh_name, file])
	for file in instances:
		if instances[file] != null:
			(instances[file] as Node).free()
	return out


## A material shared by every player that wears the same colour of the same kind (one StandardMaterial3D, not one per mesh per player).
static func shared_material(kind: String, color: Color, roughness: float) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [kind, color.to_html(false), roughness]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		m.resource_name = kind
		if kind in ["jersey", "shorts", "socks", "trim"]:
			m.cull_mode = BaseMaterial3D.CULL_DISABLED   # open cloth: its inside shows the cloth, not the body
		_materials[key] = m
	return _materials[key]


## The validator problems of a model file, computed once per file per run.
static func validated(path: String) -> Array[String]:
	if not _validated.has(path):
		_validated[path] = FcPlayerModelValidator.validate_path(path)
	return _validated[path]


## Drops cached scenes and materials (tests and the asset reload).
static func clear_cache() -> void:
	_scenes.clear()
	_materials.clear()
	_validated.clear()
	_data = {}
