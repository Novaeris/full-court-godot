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
## The dribbled ball touched the floor (the replay screen decides whether it is heard).
signal ball_bounced

## Tests set this to prove the 2D fallback: the next setup() fails.
static var force_failure: bool = false
## A GLB player model (res:// path, validated by FcPlayerModelValidator) the players of the replay wear instead of the generated body; empty = generated (the
## default until a model is judged good enough to ship). A model that fails validation is ignored player by player and the generated body is used.
static var player_model: String = ""


## The model the replay players wear: player_model when set, otherwise the library players once the founder has promoted them (asset_library.json
## "promoted"), otherwise the generated body.
static func effective_model() -> String:
	if player_model != "":
		return player_model
	return FcPlayerAssetLibrary.library_model() if FcPlayerAssetLibrary.promoted() else ""

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
var _actor: int = 0
var _spot_id: int = 0                  # the player being introduced (0 none)
var _spot_ring: MeshInstance3D         # the glowing ring on the floor under the spotlit player
var _spot_light: SpotLight3D           # the light from above on the spotlit player
var _team_colors: Array = []
var _side_of: Dictionary = {}     # player id -> 0 home, 1 away
var _seated: Dictionary = {}      # player id -> true while sitting on the bench
var officials: Array[FcBroadcastCharacter] = []   # three referees
var coaches: Array[FcBroadcastCharacter] = []     # one head coach on each sideline
var _angle: Dictionary = {"angle": "main", "side": 1}   # the angle the camera is gliding to
var _angle_from: Dictionary = {"angle": "main", "side": 1}
var _angle_blend: float = 1.0
var _ball: FcBasketball
var _flight_start: Vector3 = Vector3.ZERO
var _flight_goal: Vector3 = Vector3(47, 3, 25)
var _flight_t: float = 1.0
var _flight_seconds: float = 0.5
var _rim_stage: int = 0     # 0 none yet, 1 dropped through or bounced off the rim for this event
var _drop_speed: float = 0.0
var _last_dribble_u: float = 0.5
var _ball_goal: Vector3 = Vector3(47, 3, 25)
var _wave: int = 0
var _dragging: bool = false
var _teleport: bool = true

const BENCH_SEATS := 8
const SCENERY_STEP := 0.05
var _scenery_clock: float = 0.0


## Builds the view for a replay. `colors` are the home and away colours. Returns false when the 3D view cannot be built (the caller then keeps 2D).
func setup(replay_model: FcReplayModel, broadcast_timeline: FcBroadcastTimeline, colors: Array, arena_identity: Dictionary = {}) -> bool:
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
	scene.build(home, away, str(_model.box.abbreviations[0]), arena_identity if not arena_identity.is_empty() else FcArenaIdentity.for_box(_model.box, home, away))   # the arena is dressed for the home team
	_team_colors = [home, away]
	_build_characters([home, away])
	scene.set_bench_figures_visible(false)
	_ball = FcBasketball.new()
	scene.add_child(_ball)
	var result := FcReconstructor.build(_timeline)
	for f in result["keyframes"]:
		if not _by_event.has(int(f["event"])):
			_by_event[int(f["event"])] = []
		(_by_event[int(f["event"])] as Array).append(f)
	built = true
	set_process(false)
	return true


## The three referees and the two head coaches: characters like the players (the same skeleton and mesh builder) in a referee shirt and black trousers or a
## suit, with no number. They are not in the game data and nothing here reads or writes it: they are scenery that follows the play.
func _build_staff(colors: Array) -> void:
	for k in 3:
		var subject := {"key": "official:%d" % k, "name": "official", "jersey": 0, "position": "SG", "attire": "referee",
			"physical": {"height_cm": 180 + k * 5, "weight_kg": 80 + k * 4},
			"team": {"primary": "#26272B", "secondary": "#F2F2F2", "abbreviation": "", "name": ""}}
		var c := FcBroadcastCharacter.new().setup(subject, float(k) * 0.3)
		c.auto_advance = false
		c.position = Vector3(30.0 + 17.0 * float(k), 0.0, 25.0)
		scene.add_child(c)
		officials.append(c)
	for side in 2:
		var subject := {"key": "coach:%d:%s" % [side, str(_model.box.abbreviations[side])], "name": "coach", "jersey": 0, "position": "SF", "attire": "suit",
			"physical": {"height_cm": 188, "weight_kg": 92},
			"team": {"primary": "#" + (colors[side] as Color).darkened(0.55).to_html(false), "secondary": "#F2F2F2", "abbreviation": "", "name": ""}}
		var c := FcBroadcastCharacter.new().setup(subject, float(side) * 0.5)
		c.auto_advance = false
		c.position = Vector3(FcCourtLayout.COURT_LENGTH * (0.29 if side == 0 else 0.71) + (3.2 if side == 0 else -3.2), 0.0, -1.6)
		c.set_state("coach", 0.0)
		scene.add_child(c)
		coaches.append(c)


func _build_characters(colors: Array) -> void:
	var numbers := FcJerseyNumbers.for_box(_model.box)
	var i := 0
	for p in _model.box.players:
		var side := 0 if p.team_id == _model.box.team_ids[0] else 1
		var primary: Color = colors[side]
		var body := FcBroadcast3DRules.body_for(p.player_id, p.position)
		var subject := {"key": "player:%d" % p.player_id, "name": p.name, "jersey": int(numbers.get(p.player_id, 0)), "position": FcPosition.abbreviation(p.position),
			"physical": {"height_cm": body[0], "weight_kg": body[1]}, "model": effective_model(),
			"team": {"primary": "#" + primary.to_html(false), "secondary": "#F4F7FF" if primary.get_luminance() < 0.5 else "#1B1B1B", "abbreviation": _model.box.abbreviations[side], "name": _model.box.team_names[side]}}
		var c := FcBroadcastCharacter.new().setup(subject, float(i) * 0.137)
		c.visible = false
		c.auto_advance = false   # the view advances them, and only while it is showing
		scene.add_child(c)
		characters[p.player_id] = c
		_side_of[p.player_id] = side
		i += 1
	_build_staff(colors)


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
	_actor = int(entry["a"])
	var on_court: Dictionary = kf["players"]
	var offense: int = state["offense_side"]
	var bench_slot := [0, 0]
	for pid in characters:
		var c: FcBroadcastCharacter = characters[pid]
		var here := on_court.has(pid)
		if not here:
			# off the court a player sits on his team bench (the first eight; a longer bench is out of the picture)
			var team: int = _side_of[pid]
			var slot: int = bench_slot[team]
			bench_slot[team] = slot + 1
			c.visible = slot < BENCH_SEATS
			_seated[pid] = true
			_targets.erase(pid)
			c.position = _bench_position(team, slot)
			c.rotation_degrees.y = 0.0
			continue
		c.visible = true
		_seated.erase(pid)
		_targets[pid] = on_court[pid]
		var side := 0 if (state["on_court"][0] as Array).has(pid) else 1
		var role := "other"
		if int(entry["a"]) == pid:
			role = "actor"
		elif int(entry["b"]) == pid and _entry_type in [FcGameEventLog.EV_SHOT_BLOCKED, FcGameEventLog.EV_TURNOVER, FcGameEventLog.EV_SHOT_MADE]:
			role = "partner"
		elif pid == _holder:
			role = "ball"
		elif side != offense:
			role = "defender"
		_roles[pid] = role
		if _teleport or not animate:
			var at: Vector2 = on_court[pid]
			c.position = Vector3(at.x, 0.0, at.y)
	_teleport = false
	_mark_contester(int(entry["a"]), on_court)
	var ball: Vector3 = kf["ball"]
	_ball_goal = Vector3(ball.x, ball.z, ball.y)
	if not animate:
		_ball.position = _ball_goal
		_flight_goal = _ball_goal
		_flight_start = _ball_goal
		_flight_t = 1.0
		_rim_stage = 0
	scene.set_scoreboard("%s %d   %s   %s %d" % [_model.box.abbreviations[0], int(state["home"]), _model.status_at(index), _model.box.abbreviations[1], int(state["away"])])
	set_process(is_visible_in_tree())


## On a shot, the defender nearest the shooter contests it (a hand up); everyone else keeps the plain defensive stance.
func _mark_contester(shooter: int, on_court: Dictionary) -> void:
	if not (_entry_type in [FcGameEventLog.EV_SHOT_MADE, FcGameEventLog.EV_SHOT_MISSED, FcGameEventLog.EV_SHOT_BLOCKED]) or not on_court.has(shooter):
		return
	var best := -1
	var best_distance := 1.0e9
	for pid in _roles:
		if _roles[pid] != "defender" or not on_court.has(pid):
			continue
		var d := (on_court[pid] as Vector2).distance_to(on_court[shooter])
		if d < best_distance:
			best_distance = d
			best = pid
	if best != -1 and best_distance < 9.0:
		_roles[best] = "contester"


## Where a bench player sits: team 0 on the left bench and team 1 on the right, in a row behind the far sideline.
func _bench_position(team: int, slot: int) -> Vector3:
	var cx := FcCourtLayout.COURT_LENGTH * (0.29 if team == 0 else 0.71)
	return Vector3(cx + (float(slot) - float(BENCH_SEATS - 1) / 2.0) * 1.35, 0.0, -7.1)


## The crowd reacts to the sounds of an event (the same cues the audio uses): cheers stand the next section up and make the crowd jump (a big one
## starts a stadium wave), a groan slumps it, an "oh" is a short gasp.
func react(cues: Array) -> void:
	if not built:
		return
	for id in cues:
		var cue := str(id)
		if cue.begins_with("crowd_cheer"):
			scene.react_crowd("cheer_big" if cue == "crowd_cheer_big" else "cheer")
			if scene.section_count() > 0:
				scene.stand_section(_wave % scene.section_count())
				_wave += 1
			return
		elif cue == "crowd_groan":
			scene.react_crowd("groan")
			return
		elif cue == "crowd_oh":
			scene.react_crowd("oh")
			return


## The camera pose for the rig's camera, gliding between director angles so a change of angle is a move, not a jump (instant with reduced motion).
func _blended_pose(cam: Dictionary, delta: float) -> Dictionary:
	var want := rig.pose_angle()
	if str(want["angle"]) != str(_angle["angle"]) or (str(want["angle"]) == "baseline" and int(want["side"]) != int(_angle["side"])):
		_angle_from = _angle
		_angle = want
		_angle_blend = 0.0
	_angle_blend = 1.0 if FcMotion.reduced else minf(1.0, _angle_blend + delta / FcBroadcast3DRules.ANGLE_BLEND_SECONDS)
	var to_pose := _pose_for(_angle, cam)
	if _angle_blend >= 1.0:
		return to_pose
	var from_pose := _pose_for(_angle_from, cam)
	var w := smoothstep(0.0, 1.0, _angle_blend)
	return {"position": (from_pose["position"] as Vector3).lerp(to_pose["position"], w), "target": (from_pose["target"] as Vector3).lerp(to_pose["target"], w)}


## The camera pose for one angle. A "closeup" frames the player nearest the shot's focus from the front (his face and number), the other angles use the
## fixed broadcast offsets. Never nearer than the 28 ft minimum of D-070 either way.
func _pose_for(angle: Dictionary, cam: Dictionary) -> Dictionary:
	if str(angle["angle"]) == "closeup":
		var subject := _nearest_character(cam["focus"], 7.0)
		if subject != null:
			return FcBroadcast3DRules.camera_pose_front(Vector2(subject.position.x, subject.position.z), float(cam["zoom"]), subject.rotation_degrees.y)
	return FcBroadcast3DRules.camera_pose(cam["focus"], float(cam["zoom"]), str(angle["angle"]), int(angle["side"]))


## The visible player standing nearest `point` (court feet) within `within` feet, or null.
func _nearest_character(point: Vector2, within: float) -> FcBroadcastCharacter:
	var best: FcBroadcastCharacter = null
	var best_distance := within
	for pid in characters:
		var c: FcBroadcastCharacter = characters[pid]
		if not c.visible or _seated.has(pid):
			continue
		var d := Vector2(c.position.x, c.position.z).distance_to(point)
		if d < best_distance:
			best_distance = d
			best = c
	return best


## A player is being introduced (the replay screen calls this with his id, and with 0 when the introductions end): he turns to the camera, waves, and a
## light and a ring on the floor pick him out.
func show_introduction(player_id: int) -> void:
	_spot_id = player_id


## The ring and the light follow the introduced player, or the scorer during a celebration, and are hidden otherwise.
func _update_spot(celebrating: bool) -> void:
	var id := _spot_id if _spot_id != 0 else (_actor if celebrating else 0)
	if _spot_ring == null:
		var disc := CylinderMesh.new()
		disc.top_radius = 1.7
		disc.bottom_radius = 1.7
		disc.height = 0.04
		disc.radial_segments = 40
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = FcScenePalette.color("rim")
		m.albedo_color.a = 0.55
		_spot_ring = MeshInstance3D.new()
		_spot_ring.mesh = disc
		_spot_ring.material_override = m
		_spot_ring.visible = false
		_spot_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scene.add_child(_spot_ring)
		_spot_light = SpotLight3D.new()
		_spot_light.spot_range = 40.0
		_spot_light.spot_angle = 14.0
		_spot_light.light_energy = 3.0
		_spot_light.shadow_enabled = false
		_spot_light.visible = false
		scene.add_child(_spot_light)
	var c: FcBroadcastCharacter = characters.get(id)
	var on := c != null and c.visible and not _seated.has(id)
	_spot_ring.visible = on
	_spot_light.visible = on
	if on:
		_spot_ring.position = Vector3(c.position.x, 0.03, c.position.z)
		var color := _team_colors[int(_side_of.get(id, 0))] as Color
		var ring_colour := color
		ring_colour.a = 0.55
		(_spot_ring.material_override as StandardMaterial3D).albedo_color = ring_colour
		_spot_light.light_color = color.lerp(FcScenePalette.color("line"), 0.6)
		_spot_light.transform = Transform3D(Basis.looking_at(Vector3(0.0, -1.0, 0.0) + Vector3(0.001, 0.0, 0.001), Vector3.FORWARD), Vector3(c.position.x, 22.0, c.position.z))


## Whether the director's current shot is a celebration of a made basket (the scorer's team reacts and a light picks out the scorer).
func is_celebrating() -> bool:
	return built and _entry_type == FcGameEventLog.EV_SHOT_MADE and str(rig.last_shot().get("reason", "")) == "celebration"


func _process(delta: float) -> void:
	if not built or not is_visible_in_tree():
		return
	rig.reduced = FcMotion.reduced
	rig.advance(delta)
	var cam := rig.camera()
	scene.set_camera(_blended_pose(cam, delta))
	_advance_scenery(delta)
	var hoop := FcCourtLayout.basket(_attacks_right)
	var celebrating := is_celebrating()
	_update_spot(celebrating)
	for pid in _targets:
		var c: FcBroadcastCharacter = characters[pid]
		if not c.visible:
			continue
		var target: Vector2 = _targets[pid]
		var here := Vector2(c.position.x, c.position.z)
		var distance := here.distance_to(target)
		var moving := distance > 0.6
		var role := str(_roles.get(pid, "other"))
		if celebrating and role in ["other", "ball", "partner"] and _side_of.get(pid, -1) == _side_of.get(_actor, -2):
			role = "celebrant"   # the scorer's teammates celebrate the basket
		if _spot_id != 0:
			if pid == _spot_id:
				c.set_state("intro")
				c.playback = 1.0
				c.advance(delta)
				c.rotation_degrees.y = lerp_angle(deg_to_rad(c.rotation_degrees.y), 0.0, minf(1.0, delta * 8.0)) * 180.0 / PI   # towards the broadcast camera
			else:
				c.set_state("idle")
				c.advance(delta)
			continue
		var action := FcBroadcast3DRules.action_for(_entry_type, _shot_kind, role, pid)
		var speed := FcBroadcast3DRules.travel_speed_for(distance)
		var state := action
		if state == "":
			state = FcBroadcast3DRules.motion_for(role, speed) if moving else FcBroadcast3DRules.state_for(_entry_type, _shot_kind, role, false)
		c.set_state(state)
		c.playback = FcBroadcast3DRules.playback_for(state, speed, c.height_feet) if moving and action == "" else 1.0
		c.advance(delta)
		if moving:
			var step := minf(distance, speed * delta)
			var next := here.move_toward(target, step)
			c.position = Vector3(next.x, 0.0, next.y)
			# defenders keep facing the play while they slide; everyone else faces where they are going
			var look := FcBroadcast3DRules.facing_yaw(here, hoop) if role in ["defender", "contester"] else FcBroadcast3DRules.facing_yaw(here, target)
			c.rotation_degrees.y = lerp_angle(deg_to_rad(c.rotation_degrees.y), deg_to_rad(look), minf(1.0, delta * 10.0)) * 180.0 / PI
		else:
			c.rotation_degrees.y = lerp_angle(deg_to_rad(c.rotation_degrees.y), deg_to_rad(FcBroadcast3DRules.facing_yaw(here, hoop)), minf(1.0, delta * 10.0)) * 180.0 / PI
	_move_ball(delta)


## Bench players sit, coaches stand with their arms folded, and the referees follow the ball: lead at the baseline of the attacked basket on the far side
## of the lane, trail behind the play on the sideline, centre on the opposite sideline.
func _advance_scenery(delta: float) -> void:
	# the bench and the coaches barely move, so they are updated 20 times a second (with the time they missed) and the hidden ones not at all: this is
	# where the cost of the 3D view grew most with the number of people (about 0.15 ms per animated character per frame on the development machine)
	_scenery_clock += delta
	if _scenery_clock >= SCENERY_STEP:
		for pid in _seated:
			var c: FcBroadcastCharacter = characters[pid]
			if not c.visible:
				continue
			c.set_state("sit")
			c.playback = 1.0
			c.advance(_scenery_clock)
		for c in coaches:
			c.advance(_scenery_clock)
		_scenery_clock = 0.0
	var dir := 1.0 if _attacks_right else -1.0
	var ball := Vector2(_ball.position.x, _ball.position.z)
	var end_x := FcCourtLayout.COURT_LENGTH if _attacks_right else 0.0
	var lead_side := 1.0 if ball.y < 25.0 else -1.0
	var targets := [Vector2(end_x - dir * 2.5, 25.0 + lead_side * 11.0),
		Vector2(clampf(ball.x - dir * 12.0, 5.0, 89.0), -1.5 if ball.y < 25.0 else 51.5),
		Vector2(clampf(ball.x + dir * 6.0, 5.0, 89.0), 51.5 if ball.y < 25.0 else -1.5)]
	for k in officials.size():
		var c := officials[k]
		var here := Vector2(c.position.x, c.position.z)
		var distance := here.distance_to(targets[k])
		var speed := minf(FcBroadcast3DRules.travel_speed_for(distance) * 0.6, 11.0)
		var moving := distance > 1.0
		var state := FcBroadcast3DRules.motion_for("other", speed) if moving else "idle"
		c.set_state(state)
		c.playback = FcBroadcast3DRules.playback_for(state, speed, c.height_feet) if moving else 1.0
		c.advance(delta)
		if moving:
			var next := here.move_toward(targets[k], minf(distance, speed * delta))
			c.position = Vector3(next.x, 0.0, next.y)
		c.rotation_degrees.y = lerp_angle(deg_to_rad(c.rotation_degrees.y), deg_to_rad(FcBroadcast3DRules.facing_yaw(here, ball)), minf(1.0, delta * 6.0)) * 180.0 / PI


func _move_ball(delta: float) -> void:
	# a player in a two-handed action (a shot, a rebound, a dunk) has the ball in both hands for the part of the loop the pose says so
	if _actor != 0 and characters.has(_actor) and (characters[_actor] as FcBroadcastCharacter).visible:
		var held := (characters[_actor] as FcBroadcastCharacter).ball_anchor()
		if bool(held["active"]):
			_ball.position = held["position"]
			_ball.spin = Vector3.ZERO
			_flight_start = _ball.position
			_flight_t = 1.0
			_flight_goal = _ball.position
			_ball.advance(delta)
			return
	if _holder != 0 and characters.has(_holder) and (characters[_holder] as FcBroadcastCharacter).visible:
		var holder := characters[_holder] as FcBroadcastCharacter
		var hand := holder.hand_position()
		if holder.state in ["dribble", "dribble_run", "drive", "crossover", "hesitation"]:
			# bounced: hand to floor and back, twice per loop, in time with the dribbling arm
			var u := FcBallMotion.dribble_u(holder.cycle_phase())
			if _last_dribble_u > 0.75 and u < 0.25:   # the bounce parabola started again: the ball has just hit the floor
				ball_bounced.emit()
			_last_dribble_u = u
			_ball.position = Vector3(hand.x, FcBallMotion.dribble_height(u, hand.y), hand.z)
			_ball.spin = FcBallMotion.spin_axis_rate("dribble", Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, holder.rotation.y))
		else:
			_ball.position = hand + Vector3(0.0, 0.1, 0.0)
			_ball.spin = Vector3.ZERO
		_flight_start = _ball.position
		_flight_goal = _ball.position
		_flight_t = 1.0
		_ball.advance(delta)
		return
	_fly(delta)
	_ball.advance(delta)


## The ball in the air: a new goal starts an arc from where the ball is; arriving at a basket on a made shot drops it through the net (and swings the
## net), on a miss it bounces off the rim. The speed never exceeds the reconstruction's own limit.
func _fly(delta: float) -> void:
	if _ball_goal.distance_to(_flight_goal) > 0.5:
		_flight_start = _ball.position
		_flight_goal = _ball_goal
		_flight_t = 0.0
		_rim_stage = 0
		_flight_seconds = maxf(FcBallMotion.flight_seconds(_flight_start, _flight_goal, FcReconstructor.BALL_SPEED_LIMIT * 0.8), 0.25)
	var shot := _entry_type in [FcGameEventLog.EV_SHOT_MADE, FcGameEventLog.EV_SHOT_MISSED, FcGameEventLog.EV_SHOT_BLOCKED, FcGameEventLog.EV_FREE_THROW]
	if _flight_t < 1.0:
		_flight_t = minf(1.0, _flight_t + delta / _flight_seconds)
		_ball.position = FcBallMotion.flight_position(_flight_start, _flight_goal, _flight_t, shot)
		var direction := _flight_goal - _flight_start
		_ball.spin = FcBallMotion.spin_axis_rate("shot" if shot else "pass", direction)
		return
	var rim := scene.rim_position(_attacks_right)
	var near_rim := Vector2(_ball.position.x - rim.x, _ball.position.z - rim.z).length() < 2.2 and absf(_ball.position.y - rim.y) < 3.5
	if shot and near_rim and _rim_stage == 0:
		_rim_stage = 1
		if _entry_type == FcGameEventLog.EV_SHOT_MADE or (_entry_type == FcGameEventLog.EV_FREE_THROW and false):
			_ball.position = Vector3(rim.x, rim.y + 0.25, rim.z)
			_drop_speed = 6.0
			scene.swish(_attacks_right)
			_rim_stage = 2
		else:   # a miss rattles off the rim and out into the court
			var inward := -1.0 if _attacks_right else 1.0
			_flight_start = _ball.position
			_flight_goal = Vector3(rim.x + inward * 3.0, 1.0, rim.z + (FcCourtLayout.unit(_actor, 5) - 0.5) * 5.0)
			_flight_t = 0.0
			_flight_seconds = 0.75
			return
	if _rim_stage == 2:   # through the net: falling under gravity, stopping on the floor
		_drop_speed += FcBallMotion.GRAVITY * delta
		_ball.position.y = maxf(FcBallMotion.RADIUS, _ball.position.y - _drop_speed * delta)
		_ball.spin = Vector3.ZERO
		return
	_ball.spin = Vector3.ZERO


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
		if (characters[pid] as FcBroadcastCharacter).visible and not _seated.has(pid):
			out.append(pid)
	out.sort()
	return out


func ball_position() -> Vector3:
	return _ball.position if _ball != null else Vector3.ZERO


func camera_pose() -> Dictionary:
	return {"position": scene.camera.position, "target": scene.camera.position + (-scene.camera.global_transform.basis.z)} if built else {}


func character_state(player_id: int) -> String:
	return (characters[player_id] as FcBroadcastCharacter).state if characters.has(player_id) else ""
