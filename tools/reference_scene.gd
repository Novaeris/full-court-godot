extends SceneTree
## The standardized player comparison scene (V2.1): ONE reference player, identical studio lighting, identical cameras and identical poses for every
## model version, so pictures can be compared side by side. NOT headless (it renders).
##   godot_console --path . --script res://tools/reference_scene.gd -- out=docs/validation/player_v21/v2_0 model=v2 [key=reference:1]
##   model: "" (the generated procedural body), "library" (M1), "v2" (the V2 players)
## Views: front, side, back (full body), face, upper body, hands, shoes, neutral pose (three-quarter), action pose (jump shot, three-quarter).

const VIEWS := ["front", "side", "back", "face", "upper", "hands", "shoes", "neutral", "action", "deform_arm", "deform_leg"]
const SIZE := Vector2i(900, 1200)

var _out := "user://reference"
var _model := "v2"
var _key := "reference:1"
var _character: FcBroadcastCharacter
var _camera: Camera3D
var _view := -1
var _wait := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() == 2:
			match kv[0]:
				"out": _out = kv[1]
				"model": _model = kv[1]
				"key": _key = kv[1]
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = SIZE
	DisplayServer.window_set_size(SIZE)
	root.msaa_3d = Viewport.MSAA_4X
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out) if _out.begins_with("user://") else _out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.html("#5A6270")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.html("#AEB7C6")
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world := WorldEnvironment.new()
	world.environment = env
	root.add_child(world)
	for spec in [[Vector3(-35.0, 30.0, 0.0), 0.85, true], [Vector3(-15.0, -55.0, 0.0), 0.32, false], [Vector3(-25.0, 165.0, 0.0), 0.55, false]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = spec[0]
		light.light_energy = spec[1]
		light.shadow_enabled = spec[2]
		root.add_child(light)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	floor.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color.html("#3E444F")
	floor_mat.roughness = 0.9
	floor.material_override = floor_mat
	root.add_child(floor)
	var subject := {"key": _key, "name": "Marcus Reyes", "jersey": 23, "position": "SF", "model": _model,
		"physical": {"height_cm": 201, "weight_kg": 100}, "kit": "home",
		"appearance": {"skin": "tone_4", "hair": "fade", "facial_hair": "goatee", "face": "face_3"},
		"team": {"primary": "#1D428A", "secondary": "#FFC72C", "abbreviation": "HOU", "name": "Houston"}}
	FcJerseyGraphics.clear_cache()
	_character = FcBroadcastCharacter.new().setup(subject, 0.0)
	_character.auto_advance = false
	root.add_child(_character)
	FcPlayerLod.bake_characters([_character])
	_camera = Camera3D.new()
	_camera.fov = 28.0
	root.add_child(_camera)
	_camera.current = true
	_next()


func _frame(view: String) -> void:
	var h := _character.height_feet
	_character.rotation_degrees.y = 0.0
	match view:
		"action":
			_character.pose_at("shoot", 0.48)
		"deform_arm":
			_character.pose_at("contest", 0.1)
		"deform_leg":
			_character.pose_at("defend", 0.25)
		_:
			_character.pose_at("idle", 0.0)
	var target := Vector3(0.0, h * 0.5, 0.0)
	var from := Vector3(0.0, h * 0.5, h * 3.6)
	match view:
		"side": from = Vector3(h * 3.6, h * 0.5, 0.0)
		"back": from = Vector3(0.0, h * 0.5, -h * 3.6)
		"face":
			target = Vector3(0.0, h * 0.925, 0.0)
			from = Vector3(h * 0.18, h * 0.93, h * 0.75)
		"upper":
			target = Vector3(0.0, h * 0.78, 0.0)
			from = Vector3(h * 0.35, h * 0.8, h * 1.45)
		"hands":
			target = Vector3(h * 0.12, h * 0.47, 0.0)
			from = Vector3(h * 0.55, h * 0.5, h * 0.75)
		"shoes":
			target = Vector3(0.0, h * 0.05, 0.0)
			from = Vector3(h * 0.45, h * 0.16, h * 0.8)
		"deform_arm":
			target = Vector3(0.0, h * 0.85, 0.0)
			from = Vector3(h * 0.75, h * 0.9, h * 1.05)
		"deform_leg":
			target = Vector3(0.0, h * 0.3, 0.0)
			from = Vector3(h * 0.95, h * 0.35, h * 0.85)
		"neutral", "action":
			target = Vector3(0.0, h * (0.55 if view == "action" else 0.5), 0.0)
			from = Vector3(h * 2.4, h * 0.6, h * 2.9)
	_camera.look_at_from_position(from, target, Vector3.UP)


func _next() -> void:
	_view += 1
	if _view >= VIEWS.size():
		quit()
		return
	_frame(VIEWS[_view])
	_wait = 0


func _process(_delta: float) -> bool:
	if _view < 0 or _view >= VIEWS.size():
		return false
	_wait += 1
	if _wait == 6:
		var img := root.get_texture().get_image()
		var path := "%s/%s.png" % [_out, VIEWS[_view]]
		img.save_png(path)
		print("saved ", path)
		_next()
	return false
