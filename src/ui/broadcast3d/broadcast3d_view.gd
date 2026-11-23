class_name FcBroadcast3DView
extends SubViewportContainer
## The 3D broadcast view of a replay (master plan B4, decision D-070 reduced scope). It shows the same replay the 2D court shows, from a broadcast
## camera: the arena (FcCourtScene), ten code-built characters (FcBroadcastCharacter) walking to the positions the reconstruction
## (FcReconstructor, labelled "reconstructed", never tracked play) gives for the current event, the ball in the holder's hands or in flight, and
## the camera the director (FcCameraDirector) asks for through the SAME FcCameraRig the 2D view uses, so manual control, hybrid return and
## reset behave identically in both views.
##
## It is a view: it reads the replay model, timeline and reconstruction and changes nothing in a game. The replay position, score and clock
## belong to FcReplayScreen, never to this class, so switching views or falling back to 2D loses nothing. If building fails (or a test forces a
## failure) `setup` returns false and the screen keeps the 2D court.

signal camera_moved_by_hand

## Tests set this to prove the 2D fallback: the next setup() fails.
static var force_failure: bool = false

var rig: FcCameraRig = FcCameraRig.new()
var scene: FcCourtScene
var built: bool = false
var characters: Dictionary = {}   # player id -> FcBroadcastCharacter

var _viewport: SubViewport
var _model: FcReplayModel
var _timeline: FcBroadcastTimeline
var _by_event: Dictionary = {}    # event index -> keyframes of that event
var _targets: Dictionary = {}     # player id -> Vector2 (court feet) the character walks to
var _roles: Dictionary = {}       # player id -> "actor" | "ball" | "defender" | "other"
var _entry_type: int = 0
var _shot_kind: int = 0
var _attacks_right: bool = true
var _holder: int = 0
var _angle: Dictionary = {"angle": "main", "side": 1}   # the angle the camera is gliding to
var _angle_from: Dictionary = {"angle": "main", "side": 1}
var _angle_blend: float = 1.0
var _ball: MeshInstance3D
var _ball_goal: Vector3 = Vector3(47, 3, 25)
var _wave: int = 0
var _dragging: bool = false
var _teleport: bool = true


## Builds the view for a replay. `colors` are the home and away colours. Returns false when the 3D view cannot be built (the caller then keeps 2D).
func setup(replay_model: FcReplayModel, broadcast_timeline: FcBroadcastTimeline, colors: Array) -> bool:
	if force_failure or replay_model == null or replay_model.is_empty() or broadcast_timeline == null:
		return false
	_model = replay_model
	_timeline = broadcast_timeline
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_viewport)
	scene = FcCourtScene.new()
	_viewport.add_child(scene)
	var home: Color = colors[0] if colors.size() == 2 else Color("2F6FED")
	var away: Color = colors[1] if colors.size() == 2 else Color("F28A2E")
	scene.build(home, away, str(_model.box.abbreviations[0]))
	_build_characters([home, away])
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = 0.45
	ball_mesh.height = 0.9
	_ball = MeshInstance3D.new()
	_ball.mesh = ball_mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("F28A2E")
	_ball.material_override = m
	scene.add_child(_ball)
	var result := FcReconstructor.build(_timeline)
	for f in result["keyframes"]:
		if not _by_event.has(int(f["event"])):
			_by_event[int(f["event"])] = []
		(_by_event[int(f["event"])] as Array).append(f)
	built = true
	set_process(false)
	return true


func _build_characters(colors: Array) -> void:
	var numbers := FcJerseyNumbers.for_box(_model.box)
	var i := 0
	for p in _model.box.players:
		var side := 0 if p.team_id == _model.box.team_ids[0] else 1
		var primary: Color = colors[side]
		var body := FcBroadcast3DRules.body_for(p.player_id, p.position)
		var subject := {"key": "player:%d" % p.player_id, "name": p.name, "jersey": int(numbers.get(p.player_id, 0)), "position": FcPosition.abbreviation(p.position),
			"physical": {"height_cm": body[0], "weight_kg": body[1]},
			"team": {"primary": "#" + primary.to_html(false), "secondary": "#F4F7FF" if primary.get_luminance() < 0.5 else "#1B1B1B", "abbreviation": _model.box.abbreviations[side], "name": _model.box.team_names[side]}}
		var c := FcBroadcastCharacter.new().setup(subject, float(i) * 0.137)
		c.visible = false
		c.set_process(false)   # the view advances them, and only while it is showing
		scene.add_child(c)
		characters[p.player_id] = c
		i += 1


## Shows event `index`: who is on court, where they walk to, who holds the ball, the scoreboard. `animate` false jumps everyone there at once.
func show_event(index: int, animate: bool = true) -> void:
	if not built:
		return
	index = clampi(index, 0, _model.size() - 1)
	var frames: Array = _by_event.get(index, [])
	if frames.is_empty():
		frames = _by_event.get(_model.start_index(), [])
	if frames.is_empty():
		return
	var kf: Dictionary = frames[frames.size() - 1]
	var entry: Dictionary = _model.entries[index]
	var state := _model.state_at(index)
	_entry_type = int(entry["type"])
	_shot_kind = int(entry["x"]) if _entry_type in [FcGameEventLog.EV_SHOT_MADE, FcGameEventLog.EV_SHOT_MISSED, FcGameEventLog.EV_SHOT_BLOCKED] else 0
	_attacks_right = bool(state["attacks_right"])
	_holder = int(kf["holder"])
	var on_court: Dictionary = kf["players"]
	var offense: int = state["offense_side"]
	for pid in characters:
		var c: FcBroadcastCharacter = characters[pid]
		var here := on_court.has(pid)
		c.visible = here
		if not here:
			continue
		_targets[pid] = on_court[pid]
		var side := 0 if (state["on_court"][0] as Array).has(pid) else 1
		var role := "other"
		if int(entry["a"]) == pid:
			role = "actor"
		elif pid == _holder:
			role = "ball"
		elif side != offense:
			role = "defender"
		_roles[pid] = role
		if _teleport or not animate:
			var at: Vector2 = on_court[pid]
			c.position = Vector3(at.x, 0.0, at.y)
	_teleport = false
	var ball: Vector3 = kf["ball"]
	_ball_goal = Vector3(ball.x, ball.z, ball.y)
	if not animate:
		_ball.position = _ball_goal
	scene.set_scoreboard("%s %d   %s   %s %d" % [_model.box.abbreviations[0], int(state["home"]), _model.status_at(index), _model.box.abbreviations[1], int(state["away"])])
	set_process(is_visible_in_tree())


## The crowd reacts to the sounds of an event (the same cues the audio uses): a cheer stands the next section up.
func react(cues: Array) -> void:
	if not built:
		return
	for id in cues:
		if str(id).begins_with("crowd_cheer") and scene.section_count() > 0:
			scene.stand_section(_wave % scene.section_count())
			_wave += 1
			return


## The camera pose for the rig's camera, gliding between director angles so a change of angle is a move, not a jump (instant with reduced motion).
func _blended_pose(cam: Dictionary, delta: float) -> Dictionary:
	var want := rig.pose_angle()
	if str(want["angle"]) != str(_angle["angle"]) or (str(want["angle"]) == "baseline" and int(want["side"]) != int(_angle["side"])):
		_angle_from = _angle
		_angle = want
		_angle_blend = 0.0
	_angle_blend = 1.0 if FcMotion.reduced else minf(1.0, _angle_blend + delta / FcBroadcast3DRules.ANGLE_BLEND_SECONDS)
	var to_pose := FcBroadcast3DRules.camera_pose(cam["focus"], float(cam["zoom"]), str(_angle["angle"]), int(_angle["side"]))
	if _angle_blend >= 1.0:
		return to_pose
	var from_pose := FcBroadcast3DRules.camera_pose(cam["focus"], float(cam["zoom"]), str(_angle_from["angle"]), int(_angle_from["side"]))
	var w := smoothstep(0.0, 1.0, _angle_blend)
	return {"position": (from_pose["position"] as Vector3).lerp(to_pose["position"], w), "target": (from_pose["target"] as Vector3).lerp(to_pose["target"], w)}


func _process(delta: float) -> void:
	if not built or not is_visible_in_tree():
		return
	rig.reduced = FcMotion.reduced
	rig.advance(delta)
	var cam := rig.camera()
	scene.set_camera(_blended_pose(cam, delta))
	var hoop := FcCourtLayout.basket(_attacks_right)
	for pid in _targets:
		var c: FcBroadcastCharacter = characters[pid]
		if not c.visible:
			continue
		var target: Vector2 = _targets[pid]
		var here := Vector2(c.position.x, c.position.z)
		var distance := here.distance_to(target)
		var moving := distance > 0.6
		var state := FcBroadcast3DRules.state_for(_entry_type, _shot_kind, str(_roles.get(pid, "other")), moving)
		c.set_state(state)
		c.advance(delta)
		if moving:
			var step := minf(distance, FcBroadcast3DRules.travel_speed(state, c.height_feet) * delta)
			var next := here.move_toward(target, step)
			c.position = Vector3(next.x, 0.0, next.y)
			c.rotation_degrees.y = FcBroadcast3DRules.facing_yaw(here, target)
		else:
			c.rotation_degrees.y = FcBroadcast3DRules.facing_yaw(here, hoop)
	_move_ball(delta)


func _move_ball(delta: float) -> void:
	if _holder != 0 and characters.has(_holder) and (characters[_holder] as FcBroadcastCharacter).visible:
		var hand := (characters[_holder] as FcBroadcastCharacter).hand_position()
		_ball.position = hand
		return
	_ball.position = _ball.position.move_toward(_ball_goal, FcReconstructor.BALL_SPEED_LIMIT * delta)


# --- the camera by hand ------------------------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not built or rig.mode == FcCameraRig.Mode.AUTO:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			rig.manual_move(Vector2.ZERO, 1.15)
			camera_moved_by_hand.emit()
			accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			rig.manual_move(Vector2.ZERO, 1.0 / 1.15)
			camera_moved_by_hand.emit()
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		var before := floor_point(motion.position - motion.relative)
		var after := floor_point(motion.position)
		rig.manual_move(before - after, 1.0)   # drag the floor under the pointer, as in the 2D view
		camera_moved_by_hand.emit()
		accept_event()


## The court point (feet) under a pixel of this view (the ray from the camera meets the floor).
func floor_point(pixel: Vector2) -> Vector2:
	var camera := scene.camera
	var origin := camera.project_ray_origin(pixel)
	var direction := camera.project_ray_normal(pixel)
	if absf(direction.y) < 0.0001:
		return Vector2(FcCourtLayout.COURT_LENGTH / 2.0, FcCourtLayout.COURT_WIDTH / 2.0)
	var t := -origin.y / direction.y
	var hit := origin + direction * t
	return Vector2(clampf(hit.x, 0.0, FcCourtLayout.COURT_LENGTH), clampf(hit.z, 0.0, FcCourtLayout.COURT_WIDTH))


# --- for tests and the screen -------------------------------------------------------------------------------------------------

func on_court_ids() -> Array:
	var out: Array = []
	for pid in characters:
		if (characters[pid] as FcBroadcastCharacter).visible:
			out.append(pid)
	out.sort()
	return out


func ball_position() -> Vector3:
	return _ball.position if _ball != null else Vector3.ZERO


func camera_pose() -> Dictionary:
	return {"position": scene.camera.position, "target": scene.camera.position + (-scene.camera.global_transform.basis.z)} if built else {}


func character_state(player_id: int) -> String:
	return (characters[player_id] as FcBroadcastCharacter).state if characters.has(player_id) else ""
