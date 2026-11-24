class_name FcProjectValidator
extends RefCounted
## Whole-project validation (AI toolkit phase 7): finds the breakages that unit tests do not look for. Run by `tools/validate_project.gd` (local and CI) and
## unit-tested on small fixture folders so that each check is proven to catch what it claims to catch. Every function returns a list of problems in plain
## words; an empty list is a pass. Nothing here changes a file.
##   scripts:    every .gd file loads (a syntax or type error makes load() fail)
##   resources:  every .tscn and .tres loads and every file it depends on exists
##   assets:     every image, model, audio and font file is imported (it has a .import file and the engine can load it)
##   json:       every .json file parses
##   players:    every GLB player model in assets/players passes FcPlayerModelValidator
##   clips:      every animation clip in a GLB under assets/animations only animates standard bones (FcAnimationClipValidator)

const ASSET_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "svg", "glb", "gltf", "ogg", "wav", "mp3", "ttf", "otf", "woff2"]
const SKIP_DIRS := [".git", ".godot", ".import", "builds", "export", "node_modules", "game_src", "creator_studio", "prototypes", "site"]


## Every file under `root` (a res:// or user:// folder) with one of `extensions`, skipping build output and the Creator Studio junctions.
static func files(root: String, extensions: Array) -> Array[String]:
	var out: Array[String] = []
	_walk(root, extensions, out)
	out.sort()
	return out


static func _walk(dir_path: String, extensions: Array, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null or FileAccess.file_exists(dir_path.path_join(".gdignore")):
		return   # a folder with a .gdignore file is hidden from Godot on purpose (for example the brand source images)
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir():
			if not SKIP_DIRS.has(name):
				_walk(dir_path.path_join(name), extensions, out)
		elif extensions.has(name.get_extension().to_lower()):
			out.append(dir_path.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()


static func check_scripts(root: String) -> Array[String]:
	var out: Array[String] = []
	for path in files(root, ["gd"]):
		if not compiles(path):
			out.append("%s does not compile (a syntax or type error)" % path)
	return out


## Whether a script compiles. A script with an error still loads as an object (and logs the error), but it cannot be instantiated; a file outside res://
## (a fixture) is compiled from its text so it works without being imported.
static func compiles(path: String) -> bool:
	var script: GDScript
	if not path.begins_with("res://"):
		script = GDScript.new()
		script.source_code = FileAccess.get_file_as_string(path)
		return script.reload() == OK
	script = load(path) as GDScript
	return script != null and script.can_instantiate()


static func check_resources(root: String) -> Array[String]:
	var out: Array[String] = []
	for path in files(root, ["tscn", "tres"]):
		var res := load(path)
		if res == null:
			out.append("%s cannot be loaded" % path)
			continue
		for dep in ResourceLoader.get_dependencies(path):
			var target := str(dep).get_slice("::", 2) if str(dep).contains("::") else str(dep)
			if target != "" and not ResourceLoader.exists(target) and not FileAccess.file_exists(target):
				out.append("%s depends on %s, which does not exist" % [path, target])
	return out


static func check_assets(root: String) -> Array[String]:
	var out: Array[String] = []
	for path in files(root, ASSET_EXTENSIONS):
		if not FileAccess.file_exists(path + ".import"):
			out.append("%s has no .import file (open the project once or run godot --import, then commit the .import file)" % path)
		elif not is_imported(path):
			out.append("%s is not imported (its .import file points at nothing: run godot --import)" % path)
	return out


## Whether the .import file of an asset leads to an imported copy that exists (the engine cache), or the asset is deliberately kept as it is.
static func is_imported(path: String) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path + ".import") != OK:
		return false
	if str(cfg.get_value("remap", "importer", "")) in ["keep", "skip"]:
		return true
	for key in cfg.get_section_keys("remap") if cfg.has_section("remap") else PackedStringArray():
		if str(key).begins_with("path") and FileAccess.file_exists(str(cfg.get_value("remap", key, ""))):
			return true
	return false


static func check_json(root: String) -> Array[String]:
	var out: Array[String] = []
	for path in files(root, ["json"]):
		var json := JSON.new()
		var err := json.parse(FileAccess.get_file_as_string(path))
		if err != OK:
			out.append("%s is not valid JSON (line %d: %s)" % [path, json.get_error_line(), json.get_error_message()])
	return out


static func check_player_models(root: String) -> Array[String]:
	var out: Array[String] = []
	for path in files(root, ["glb", "gltf"]):
		for problem in FcPlayerModelValidator.validate_path(path):
			out.append("%s: %s" % [path, problem])
	return out


static func check_animation_clips(root: String) -> Array[String]:
	var out: Array[String] = []
	for path in files(root, ["glb", "gltf"]):
		for problem in FcAnimationClipValidator.validate_path(path):
			out.append("%s: %s" % [path, problem])
	return out


## The generic checks over ONE folder (scripts, resources, JSON, assets): what the unit tests aim at a fixture folder. Returns the problems.
static func run_folder(root: String) -> Array[String]:
	var problems: Array[String] = []
	problems.append_array(check_scripts(root))
	problems.append_array(check_resources(root))
	problems.append_array(check_json(root))
	problems.append_array(check_assets(root))
	return problems


## The whole project. Returns {"problems": Array[String], "counts": {check: files looked at}}.
static func run_project() -> Dictionary:
	var problems: Array[String] = []
	var counts := {}
	for entry in [["scripts", ["res://src", "res://tools", "res://tests"], "gd"], ["resources", ["res://src", "res://scenes", "res://data", "res://assets"], "tscn"], ["json", ["res://data"], "json"]]:
		counts[entry[0]] = 0
		for root in entry[1]:
			counts[entry[0]] += files(root, ["gd"] if entry[0] == "scripts" else (["tscn", "tres"] if entry[0] == "resources" else ["json"])).size()
			match entry[0]:
				"scripts": problems.append_array(check_scripts(root))
				"resources": problems.append_array(check_resources(root))
				"json": problems.append_array(check_json(root))
	counts["assets"] = files("res://assets", ASSET_EXTENSIONS).size()
	problems.append_array(check_assets("res://assets"))
	counts["player_models"] = files("res://assets/players", ["glb", "gltf"]).size()
	problems.append_array(check_player_models("res://assets/players"))
	counts["animation_files"] = files("res://assets/animations", ["glb", "gltf"]).size()
	problems.append_array(check_animation_clips("res://assets/animations"))
	return {"problems": problems, "counts": counts}
