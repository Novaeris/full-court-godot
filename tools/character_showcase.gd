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
var _wait := 0
var _pose_sheet := false
var _ball: MeshInstance3D

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
			"poses": _pose_sheet = kv[1] == "1"
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
		c.auto_advance = false
		_scene.add_child(c)
		c.position = centre + Vector3((float(i) - 2.0) * 3.6, 0.0, 0.0)
		c.rotation_degrees.y = 0.0
		c.set_state("idle", 0.0)
		c.advance(0.0)
		_models.append(c)
		i += 1
	_scene.set_process(false)
	if _pose_sheet:
		_setup_pose_sheet()
		return
	# shots: [file, camera position, target]
	var mid := centre + Vector3(0.0, 3.4, 0.0)
	_steps = [
		["front", mid + Vector3(0.0, 0.8, 19.0), mid],
		["side", mid + Vector3(-1.5, 0.8, 0.0) + Vector3(-1.0, 0.0, 0.0) * 0.0, mid],
		["threequarter", mid + Vector3(15.0, 3.0, 15.0), mid],
	]
	_steps[1][1] = mid + Vector3(22.0, 0.8, 0.0)
	var ball := FcBasketball.new()
	ball.position = centre + Vector3(0.0, 1.0, 5.0)
	ball.rotation_degrees = Vector3(25.0, 40.0, 10.0)
	_scene.add_child(ball)
	_steps.append(["ball_close", centre + Vector3(0.8, 1.6, 8.0), centre + Vector3(0.0, 1.0, 5.0), 30.0])
	_steps.append(["hoop", Vector3(18.0, 11.5, 12.0), Vector3(5.5, 10.5, 25.0), 42.0])
	_steps.append(["board_front", Vector3(13.0, 11.0, 25.0), Vector3(4.0, 11.0, 25.0), 50.0])
	_steps.append(["hoop_side", Vector3(12.0, 10.5, 41.0), Vector3(5.0, 10.0, 25.0), 36.0])
	_steps.append(["court_wide", Vector3(47.0, 34.0, 78.0 - 28.0), Vector3(47.0, 0.0, 22.0), 58.0])
	_steps.append(["court_key", Vector3(28.0, 14.0, 8.0), Vector3(12.0, 0.0, 25.0), 55.0])
	_steps.append(["detail_pg", centre + Vector3(-7.2, 5.6, 6.5), centre + Vector3(-7.2, 5.0, 0.0)])
	_steps.append(["detail_center", centre + Vector3(7.2, 6.4, 7.0), centre + Vector3(7.2, 5.8, 0.0)])


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 10:
		return false
	if _step >= _steps.size():
		quit()
		return true
	var s: Array = _steps[_step]
	if _wait == 0:
		if _pose_sheet:
			for c in _models:
				var on: bool = int(c.get_meta("sheet")) == _step
				c.visible = on
				(c.get_meta("label") as Label3D).visible = on
		_scene.camera.look_at_from_position(s[1], s[2], Vector3.UP)
		_scene.camera.fov = float(s[3]) if s.size() > 3 else 38.0
	_wait += 1
	if _wait >= 4:
		var img := root.get_texture().get_image()
		var path: String = "%s/%s.png" % [_out, s[0]]
		var err := img.save_png(ProjectSettings.globalize_path(path) if path.begins_with("user://") else path)
		print("saved ", path, " err=", err)
		_step += 1
		_wait = 0
	return false


## A contact sheet of every animation state, side view, one character each in rows, at a phase that shows the shape of the move.
func _setup_pose_sheet() -> void:
	for c in _models:
		c.queue_free()
	_models.clear()
	var states: Array = FcBroadcastPose.STATES
	var phases := {"shoot": 0.52, "three": 0.54, "layup": 0.55, "dunk": 0.5, "jump": 0.45, "contest": 0.35, "block": 0.4, "rebound": 0.4, "celebrate": 0.25, "crossover": 0.25, "hesitation": 0.3, "stop": 0.1, "land": 0.08, "turn": 0.5, "fall": 0.4, "steal": 0.3}
	var per_row := 6
	var i := 0
	var subject := {"key": "pose:sheet", "name": "pose", "jersey": 23, "position": "SF", "appearance": {"skin": "tone_3", "hair": "short", "facial_hair": "none"}, "physical": {"height_cm": 201, "weight_kg": 98}, "team": {"primary": "#2F6FED", "secondary": "#F4F7FF", "abbreviation": "HOU", "name": "Houston"}}
	_steps = []
	for state in states:
		var c := FcBroadcastCharacter.new().setup(subject, 0.0)
		c.auto_advance = false
		_scene.add_child(c)
		var sheet := i / per_row
		var col := i % per_row
		c.position = Vector3(47.0 + (float(col) - 2.5) * 5.4 + 0.0, 0.0, 25.0)
		c.rotation_degrees.y = 90.0
		c.set_meta("sheet", sheet)
		c.pose_at(state, float(phases.get(state, 0.25)))
		_models.append(c)
		var label := Label3D.new()
		label.text = state
		label.pixel_size = 0.012
		label.font_size = 64
		label.no_depth_test = true
		label.position = c.position + Vector3(0.0, 8.4, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.set_meta("sheet", sheet)
		c.set_meta("label", label)
		_scene.add_child(label)
		i += 1
	for sheet in (states.size() + per_row - 1) / per_row:
		_steps.append(["pose_sheet_%d" % sheet, Vector3(47.0, 5.0, 25.0 + 26.0), Vector3(47.0, 3.8, 25.0), 62.0])
