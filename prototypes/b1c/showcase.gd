class_name FcB1cShowcase
extends Node3D
## THROWAWAY prototype for milestone B1c: the B1b arena with the capsules replaced by TEN CODE-BUILT CHARACTERS (FcB1cCharacter), five a side, of
## different heights, weights, builds, skin tones, hair and facial hair, wearing 1 and 2 digit numbers, each in a different animation state, so
## the question "do these read as basketball players at broadcast distance, and do ten of them fit the budget" can be answered by looking at
## screenshots and by measuring. Scripted, no simulation. Wired into no shipped screen.

const SUBJECTS := [
	{"name": "Guard One", "height": 178, "weight": 74, "position": "PG", "jersey": 1, "state": "dribble", "skin": "tone_2", "hair": "short", "facial_hair": "none"},
	{"name": "Guard Two", "height": 191, "weight": 86, "position": "SG", "jersey": 7, "state": "run", "skin": "tone_5", "hair": "braids", "facial_hair": "goatee"},
	{"name": "Wing One", "height": 201, "weight": 97, "position": "SF", "jersey": 23, "state": "shoot", "skin": "tone_4", "hair": "afro", "facial_hair": "none"},
	{"name": "Big One", "height": 211, "weight": 112, "position": "PF", "jersey": 34, "state": "layup", "skin": "tone_6", "hair": "bald", "facial_hair": "beard"},
	{"name": "Big Two", "height": 221, "weight": 128, "position": "C", "jersey": 99, "state": "defend", "skin": "tone_3", "hair": "fade", "facial_hair": "stubble"},
	{"name": "Away Guard", "height": 183, "weight": 79, "position": "PG", "jersey": 0, "state": "run", "skin": "tone_1", "hair": "curly", "facial_hair": "none"},
	{"name": "Away Guard Two", "height": 194, "weight": 90, "position": "SG", "jersey": 12, "state": "defend", "skin": "tone_4", "hair": "locs", "facial_hair": "stubble"},
	{"name": "Away Wing", "height": 203, "weight": 100, "position": "SF", "jersey": 45, "state": "idle", "skin": "tone_2", "hair": "long", "facial_hair": "none"},
	{"name": "Away Big", "height": 208, "weight": 109, "position": "PF", "jersey": 8, "state": "shoot", "skin": "tone_5", "hair": "short", "facial_hair": "beard"},
	{"name": "Away Center", "height": 216, "weight": 120, "position": "C", "jersey": 10, "state": "dribble", "skin": "tone_6", "hair": "afro", "facial_hair": "goatee"}]

var arena: FcB1bArena
var characters: Array[FcB1cCharacter] = []
var camera: Camera3D
var _t: float = 0.0
var _runs: Array = []   # {character, home, direction}
var _ball: MeshInstance3D


func build(crowd: int = 6000, shadows: bool = true, board: bool = true) -> void:
	arena = FcB1bArena.new()
	arena.crowd_count = crowd
	arena.shadows = shadows
	arena.viewport_scoreboard = board
	arena.placeholder_players = false
	add_child(arena)
	arena.build()
	camera = arena.camera
	var shape := FcCourtLayout.formation(true)
	var spots: Array[Vector2] = []
	spots.append_array(shape["offense"])
	spots.append_array(shape["defense"])
	for i in SUBJECTS.size():
		var def: Dictionary = SUBJECTS[i]
		var home := i < 5
		var subject := {"key": "b1c:%d" % i, "name": def["name"], "jersey": def["jersey"], "position": def["position"],
			"appearance": {"skin": def["skin"], "hair": def["hair"], "facial_hair": def["facial_hair"]},
			"physical": {"height_cm": def["height"], "weight_kg": def["weight"]},
			"team": {"primary": "#2F6FED" if home else "#F28A2E", "secondary": "#F4F7FF" if home else "#1B1B1B", "abbreviation": "HOM" if home else "AWY", "name": "Home" if home else "Away"}}
		var c := FcB1cCharacter.new().setup(subject, float(i) * 0.137)
		c.set_state(str(def["state"]), 0.0)
		c.position = Vector3(spots[i].x, 0.0, spots[i].y)
		c.rotation_degrees = Vector3(0.0, 0.0 if i % 2 == 0 else 180.0, 0.0)   # half face the sideline camera, half show it their backs
		add_child(c)
		characters.append(c)
		if str(def["state"]) == "run":
			_runs.append({"c": c, "home": c.position, "dir": 1.0})
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = 0.45
	ball_mesh.height = 0.9
	_ball = MeshInstance3D.new()
	_ball.mesh = ball_mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("F28A2E")
	_ball.material_override = m
	add_child(_ball)


func set_camera(from: Vector3, look_at_point: Vector3) -> void:
	arena.set_camera(from, look_at_point)


## Camera presets for the visual review: "broadcast" (elevated sideline), "medium" (courtside), "close" (head and shoulders of the shooter).
func view(name: String) -> void:
	match name:
		"medium":
			arena.set_camera(Vector3(32, 8, 62), Vector3(38, 4, 36))
		"close":
			var c := characters[2]
			arena.set_camera(c.global_position + Vector3(2.2, c.height_feet * 0.78, 5.0), c.global_position + Vector3(0.0, c.height_feet * 0.72, 0.0))
		"back":
			var c2 := characters[1]
			arena.set_camera(c2.global_position + Vector3(0.0, c2.height_feet * 0.8, -9.0), c2.global_position + Vector3(0.0, c2.height_feet * 0.55, 0.0))
		_:
			arena.set_camera(Vector3(47, 40, 82), Vector3(47, 0, 22))


func instance_count() -> int:
	return arena.instance_count()


func _process(delta: float) -> void:
	_t += delta
	for r in _runs:
		var c: FcB1cCharacter = r["c"]
		var speed := FcB1cPose.ground_speed("run", c.height_feet)
		c.position.x += float(r["dir"]) * speed * delta
		var home: Vector3 = r["home"]
		if absf(c.position.x - home.x) > 12.0:
			r["dir"] = -float(r["dir"])
		c.rotation_degrees.y = 90.0 if float(r["dir"]) > 0.0 else -90.0
	var dribbler := characters[0]
	var hand := dribbler.hand_position()
	_ball.position = Vector3(hand.x, 0.5 + absf(sin(_t * 5.0)) * (hand.y - 0.5), hand.z)
