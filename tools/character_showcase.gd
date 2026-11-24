extends SceneTree
## Character showcase (3D overhaul): renders five distinct player archetypes in the REAL arena lighting and saves pictures from a front, a side
## and a three-quarter view (plus a broadcast-distance shot of a full ten). NOT headless: it opens a window.
##   godot_console --path . --script res://tools/character_showcase.gd -- out=docs/validation/3d_overhaul/m0 [size=1600x900] [model=legacy]
## It is a development tool: the cameras here may be closer than the 28 ft of D-070, because that limit is for the in-game broadcast camera.

var _out := "user://showcase"
var _size := Vector2i(1600, 900)
var _scene: FcCourtScene
var _steps: Array = []
var _frame := 0
var _step := 0
var _models: Array = []

## The five archetypes: position, height cm, weight kg, a key (which fixes face, hair and skin), and the options forced on top.
const ARCHETYPES := [
	{"name": "point_guard", "key": "showcase:pg", "pos": "PG", "h": 183, "w": 78, "appearance": {"skin": "tone_3", "hair": "fade", "facial_hair": "none"}},
	{"name": "shooting_guard", "key": "showcase:sg", "pos": "SG", "h": 193, "w": 87, "appearance": {"skin": "tone_5", "hair": "braids", "facial_hair": "stubble"}},
	{"name": "small_forward", "key": "showcase:sf", "pos": "SF", "h": 201, "w": 98, "appearance": {"skin": "tone_2", "hair": "short", "facial_hair": "goatee"}},
	{"name": "power_forward", "key": "showcase:pf", "pos": "PF", "h": 208, "w": 113, "appearance": {"skin": "tone_4", "hair": "bald", "facial_hair": "beard"}},
	{"name": "center", "key": "showcase:c", "pos": "C", "h": 216, "w": 125, "appearance": {"skin": "tone_6", "hair": "afro", "facial_hair": "none"}},
]


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"out": _out = kv[1]
			"size": _size = Vector2i(int(kv[1].get_slice("x", 0)), int(kv[1].get_slice("x", 1)))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = _size
	DisplayServer.window_set_size(_size)
	root.msaa_3d = Viewport.MSAA_4X
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var home := Color("2F6FED")
	var away := Color("F28A2E")
	_scene = FcCourtScene.new()
	root.add_child(_scene)
	_scene.build(home, away, "HOU", FcArenaIdentity.make({"home": {"abbr": "HOU", "name": "Houston Comets", "color": home}, "away": {"abbr": "DAL", "name": "Dallas", "color": away}}))
	var centre := Vector3(47.0, 0.0, 25.0)
	var i := 0
	for a in ARCHETYPES:
		var subject := {"key": a["key"], "name": a["name"], "jersey": 3 + i * 7, "position": a["pos"], "appearance": a["appearance"],
			"physical": {"height_cm": a["h"], "weight_kg": a["w"]},
			"team": {"primary": "#2F6FED", "secondary": "#F4F7FF", "abbreviation": "HOU", "name": "Houston"}}
		var c := FcBroadcastCharacter.new().setup(subject, 0.0)
		c.set_process(false)
		_scene.add_child(c)
		c.position = centre + Vector3((float(i) - 2.0) * 3.6, 0.0, 0.0)
		c.rotation_degrees.y = 0.0
		c.set_state("idle", 0.0)
		c.advance(0.0)
		_models.append(c)
		i += 1
	_scene.set_process(false)
	# shots: [file, camera position, target]
	var mid := centre + Vector3(0.0, 3.4, 0.0)
	_steps = [
		["front", mid + Vector3(0.0, 0.8, 19.0), mid],
		["side", mid + Vector3(-1.5, 0.8, 0.0) + Vector3(-1.0, 0.0, 0.0) * 0.0, mid],
		["threequarter", mid + Vector3(15.0, 3.0, 15.0), mid],
	]
	_steps[1][1] = mid + Vector3(22.0, 0.8, 0.0)
	_steps.append(["detail_pg", centre + Vector3(-7.2, 5.6, 6.5), centre + Vector3(-7.2, 5.0, 0.0)])
	_steps.append(["detail_center", centre + Vector3(7.2, 6.4, 7.0), centre + Vector3(7.2, 5.8, 0.0)])


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 10 or _frame % 6 != 0:
		return false
	if _step >= _steps.size():
		quit()
		return true
	var s: Array = _steps[_step]
	_scene.camera.look_at_from_position(s[1], s[2], Vector3.UP)
	_scene.camera.fov = 38.0
	if _frame % 12 == 0:
		var img := root.get_texture().get_image()
		var path: String = "%s/%s.png" % [_out, s[0]]
		var err := img.save_png(ProjectSettings.globalize_path(path) if path.begins_with("user://") else path)
		print("saved ", path, " err=", err)
		_step += 1
	return false
