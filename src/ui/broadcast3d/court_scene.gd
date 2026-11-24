class_name FcCourtScene
extends Node3D
## The 3D arena of the broadcast view (decision D-070), built entirely in code, no assets: a court with the home team's colour on the paint and
## its abbreviation at centre, two hoops, stepped stands with an INSTANCED crowd (one MultiMesh of camera-facing cards: a few draw calls whatever
## the count, measured in B1b), courtside boards in the team colours, a scoreboard with the live score and clock, one shadow-casting light and
## a camera. Units are feet, the convention of FcCourtLayout: x along the length, z across the width (the court's y), y up. Presentation only:
## nothing here reads or changes a game; the viewer tells it what to show.
##
## Broadcast pass 2, M5 (D-071): the arena is dressed by an FcArenaIdentity (one scene, any team): the crowd takes its colours and sizes from
## FcCrowdPlan (home, away and neutral fans) and animates on the GPU (crowd.gdshader: idle sway, cheer, groan, wave), four rotating LED boards
## carry the identity's messages, benches hold seated players, four soft spotlights lift the court, and the floor is a little glossy.

const COURT_LENGTH := FcCourtLayout.COURT_LENGTH
const COURT_WIDTH := FcCourtLayout.COURT_WIDTH
const TIERS := 16
const SECTION_ROW_STEP := 4

var crowd_count: int = 6000
var shadows: bool = true
var camera: Camera3D

## The dressing of the arena (FcArenaIdentity); set by build().
var identity: Dictionary = {}

var _home_color := Color("2F6FED")
var _away_color := Color("F28A2E")
var _home_abbreviation := ""
var _crowd: MultiMeshInstance3D
var _crowd_homes: Array[Transform3D] = []
var _sections: Array = []   # [first instance, count] groups that stand up together
var _score_labels: Array[Label3D] = []
var _standing_section: int = -1
var _crowd_scales: Array[float] = []
var _crowd_material: ShaderMaterial   # null when the shader cannot be loaded: the crowd then uses a plain card material
var _cheer: float = 0.0
var _groan: float = 0.0
var _wave: float = -1.0
var _led_labels: Array[Label3D] = []
var _led_index: int = 0
var _led_clock: float = 0.0
var _bench_figures: int = 0
var _bench_nodes: Array[MultiMeshInstance3D] = []
var _light_count: int = 0
var _tier_materials: Dictionary = {}
var dressing: Dictionary = {}   # what FcArenaDressing added (counts), for tests
var _nets: Array = []     # the nets' materials, left hoop first
var _swish: Array[float] = []   # how hard each net is swinging (1 to 0)


## Builds the arena. `arena_identity` is an FcArenaIdentity.make result; when empty, a neutral one is made from the colours and the abbreviation.
func build(home_color: Color, away_color: Color, home_abbreviation: String, arena_identity: Dictionary = {}) -> void:
	identity = arena_identity if not arena_identity.is_empty() else FcArenaIdentity.make({"home": {"abbr": home_abbreviation, "name": "", "color": home_color}, "away": {"abbr": "", "name": "", "color": away_color}})
	_home_color = identity["home_color"]
	_away_color = identity["away_color"]
	_home_abbreviation = str(identity["home_abbr"])
	_add_environment()
	_add_light()
	_add_court()
	_add_hoops()
	_add_arena()
	_add_led_boards()
	_add_benches()
	_add_scoreboard()
	_add_crowd()
	dressing = FcArenaDressing.add_all(self, identity)
	camera = Camera3D.new()
	camera.fov = FcBroadcast3DRules.FOV
	camera.current = true
	add_child(camera)
	set_camera(FcBroadcast3DRules.camera_pose(Vector2(COURT_LENGTH / 2.0, COURT_WIDTH / 2.0), 1.0))


## Places the camera: `pose` is {"position", "target"} from FcBroadcast3DRules.camera_pose.
func set_camera(pose: Dictionary) -> void:
	camera.look_at_from_position(pose["position"], pose["target"], Vector3.UP)   # works before the scene is in the tree, unlike look_at


func set_scoreboard(text: String) -> void:
	for label in _score_labels:
		label.text = text


func section_count() -> int:
	return _sections.size()


func instance_count() -> int:
	return _crowd.multimesh.instance_count if _crowd != null else 0


## One crowd section stands up (taller) and the one before it sits down: the crowd's reaction, driven by the viewer at event times.
func stand_section(index: int) -> void:
	if _crowd == null or _sections.is_empty():
		return
	index = clampi(index, 0, _sections.size() - 1)
	var mm := _crowd.multimesh
	for s in [_standing_section, index]:
		if s < 0:
			continue
		var standing: bool = s == index
		var first: int = _sections[s][0]
		var count: int = _sections[s][1]
		for i in range(first, mini(first + count, mm.instance_count)):
			var home := _crowd_homes[i]
			var base_scale: float = _crowd_scales[i] if i < _crowd_scales.size() else 1.0
			var basis := Basis().scaled(Vector3(base_scale, base_scale * (1.35 if standing else 1.0), 1.0))
			mm.set_instance_transform(i, Transform3D(basis, home.origin + Vector3(0.0, 0.25 if standing else 0.0, 0.0)))
	_standing_section = index


func standing_section() -> int:
	return _standing_section


## The crowd reacts (M5): "cheer", "cheer_big" (a bigger jump and a stadium wave), "groan" (a slump) or "oh" (a short gasp). The shader does the
## motion; here only three numbers move, so a reaction costs almost nothing. advance_crowd (the scene calls it every frame) lets them fade.
func react_crowd(kind: String) -> void:
	match kind:
		"cheer":
			_cheer = maxf(_cheer, 0.6)
		"cheer_big":
			_cheer = 1.0
			_wave = 0.0
		"groan":
			_groan = 1.0
		"oh":
			_cheer = maxf(_cheer, 0.3)
			_groan = maxf(_groan, 0.35)


## Lets the reactions fade and the wave travel; also steps the LED messages. `delta` in seconds.
func advance_crowd(delta: float) -> void:
	for i in _swish.size():
		_swish[i] = maxf(0.0, _swish[i] - delta * 0.9)
		FcHoopBuilder.swish(_nets[i], _swish[i])
	_cheer = maxf(0.0, _cheer - delta * 0.7)
	_groan = maxf(0.0, _groan - delta * 0.8)
	if _wave >= 0.0:
		_wave += delta * 0.35
		if _wave > 1.25:
			_wave = -1.0
	if _crowd_material != null:
		_crowd_material.set_shader_parameter("cheer", _cheer)
		_crowd_material.set_shader_parameter("groan", _groan)
		_crowd_material.set_shader_parameter("wave_pos", _wave)
	advance_led(delta)


## {cheer, groan, wave} as the shader sees them (wave is -1 when there is none).
func crowd_state() -> Dictionary:
	return {"cheer": _cheer, "groan": _groan, "wave": _wave}


## Steps the LED boards: the message changes every identity["led_seconds"].
func advance_led(delta: float) -> void:
	if _led_labels.is_empty():
		return
	_led_clock += delta
	var every := float(identity.get("led_seconds", 4.0))
	if _led_clock >= every:
		_led_clock = fmod(_led_clock, every)
		_led_index = (_led_index + 1) % (identity["led_messages"] as Array).size()
		_apply_led_text()


func led_index() -> int:
	return _led_index


func led_text() -> String:
	return str((identity["led_messages"] as Array)[_led_index]) if not identity.is_empty() else ""


func led_label_count() -> int:
	return _led_labels.size()


## Whether the crowd uses the animated shader (false when it could not be loaded and plain cards are drawn).
func crowd_animated() -> bool:
	return _crowd_material != null


## Hides or shows the stand-in bench figures (the viewer seats the real players there and hides them).
func set_bench_figures_visible(shown: bool) -> void:
	for node in _bench_nodes:
		node.visible = shown


func bench_figure_count() -> int:
	return _bench_figures


func light_count() -> int:
	return _light_count


func _process(delta: float) -> void:
	advance_crowd(delta)


# --- building ------------------------------------------------------------------------------------------------------------------

func _material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


func _add_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0B1020")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8090B0")
	env.ambient_light_energy = 0.5
	env.glow_enabled = true   # the LED boards, lamps and ribbon bloom a little
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.0
	var holder := WorldEnvironment.new()
	holder.environment = env
	add_child(holder)


func _add_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62.0, 25.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = shadows
	sun.directional_shadow_max_distance = 160.0
	add_child(sun)
	_light_count = 1
	# four soft spotlights over the court (no shadows, so they are cheap in the compatibility renderer): the arena's key lighting
	var centre := Vector3(COURT_LENGTH / 2.0, 0.0, COURT_WIDTH / 2.0)
	var spots := int(identity.get("spot_count", 4))
	for k in spots:
		var position := Vector3(COURT_LENGTH * (0.25 if k % 2 == 0 else 0.75), 52.0, -10.0 if k < 2 else COURT_WIDTH + 10.0)
		var spot := SpotLight3D.new()
		spot.transform = Transform3D(Basis.looking_at(centre - position, Vector3.UP), position)
		spot.light_color = identity["light_tint"]
		spot.light_energy = float(identity.get("spot_energy", 0.55))
		spot.spot_range = 95.0
		spot.spot_angle = 38.0
		spot.shadow_enabled = false
		add_child(spot)
		_light_count += 1


func _add_court() -> void:
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(COURT_LENGTH + 6.0, COURT_WIDTH + 6.0)   # the playing surface plus a 3 ft border out to the boards
	var m := ShaderMaterial.new()
	m.shader = load("res://src/ui/broadcast3d/court_floor.gdshader") as Shader
	var paint := _home_color.lerp(FcScenePalette.color("floor_light"), 0.3)
	m.set_shader_parameter("wood_light", FcScenePalette.color("floor_light"))
	m.set_shader_parameter("wood_dark", FcScenePalette.color("floor_dark"))
	m.set_shader_parameter("seam_colour", FcScenePalette.color("floor_seam"))
	m.set_shader_parameter("line_colour", FcScenePalette.color("line"))
	m.set_shader_parameter("paint_colour", paint)
	m.set_shader_parameter("circle_colour", paint)
	m.set_shader_parameter("border_colour", _home_color.darkened(0.25))
	m.set_shader_parameter("gloss", float(identity.get("floor_roughness", 0.4)) * 0.75)   # a varnished floor: a little gloss under the spotlights
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.material_override = m
	floor_node.position = Vector3(COURT_LENGTH / 2.0, 0.0, COURT_WIDTH / 2.0)
	add_child(floor_node)
	var apron := PlaneMesh.new()
	apron.size = Vector2(COURT_LENGTH + 80.0, COURT_WIDTH + 80.0)
	var apron_node := MeshInstance3D.new()
	apron_node.mesh = apron
	apron_node.material_override = _material(Color("1A2438"))
	apron_node.position = Vector3(COURT_LENGTH / 2.0, -0.05, COURT_WIDTH / 2.0)
	add_child(apron_node)
	if _home_abbreviation != "":   # the home team's mark at centre court, lying on the floor
		var mark := Label3D.new()
		mark.text = _home_abbreviation
		mark.font_size = 96
		mark.pixel_size = 0.07
		mark.modulate = Color(1, 1, 1, 0.85)
		mark.shaded = false
		mark.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		mark.position = Vector3(COURT_LENGTH / 2.0, 0.03, COURT_WIDTH / 2.0)
		add_child(mark)
	var nickname := str(identity.get("home_nickname", ""))
	if nickname != "":   # the team's name under the centre mark, and along both end lines behind the baskets
		var name_mark := Label3D.new()
		name_mark.text = nickname
		name_mark.font_size = 48
		name_mark.pixel_size = 0.06
		name_mark.modulate = Color.WHITE
		name_mark.modulate.a = 0.7
		name_mark.shaded = false
		name_mark.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		name_mark.position = Vector3(COURT_LENGTH / 2.0, 0.03, COURT_WIDTH / 2.0 + 9.0)
		add_child(name_mark)
		for right in [false, true]:
			var end_mark := Label3D.new()
			end_mark.text = nickname
			end_mark.font_size = 64
			end_mark.pixel_size = 0.07
			end_mark.modulate = identity["accent"]
			end_mark.shaded = false
			end_mark.rotation_degrees = Vector3(-90.0, -90.0 if right else 90.0, 0.0)
			end_mark.position = Vector3(COURT_LENGTH + 7.0 if right else -7.0, 0.03, COURT_WIDTH / 2.0)
			add_child(end_mark)


func _add_hoops() -> void:
	for right in [false, true]:
		var x := COURT_LENGTH - FcCourtLayout.BASKET_FROM_BASELINE if right else FcCourtLayout.BASKET_FROM_BASELINE
		var built := FcHoopBuilder.build(self, Vector3(x, FcHoopBuilder.RIM_HEIGHT, COURT_WIDTH / 2.0), -1 if right else 1)
		_nets.append(built["net"])
		_swish.append(0.0)


## The net of the left (false) or right (true) hoop swings: a shot went through.
func swish(right: bool) -> void:
	var i := 1 if right else 0
	if i < _swish.size():
		_swish[i] = 1.0


## The centre of a hoop's rim in the world (feet).
func rim_position(right: bool) -> Vector3:
	var x := COURT_LENGTH - FcCourtLayout.BASKET_FROM_BASELINE if right else FcCourtLayout.BASKET_FROM_BASELINE
	return Vector3(x, FcHoopBuilder.RIM_HEIGHT, COURT_WIDTH / 2.0)


## One material per seating colour (a tier colour comes from FcArenaDressing: team colours in the lower bowl), shared by all tiers that use it.
func _tier_material(side: int, t: int) -> StandardMaterial3D:
	var c := FcArenaDressing.seat_color(identity, side, t)
	var key := c.to_html(false)
	if not _tier_materials.has(key):
		_tier_materials[key] = _material(c)
	return _tier_materials[key]


func _add_arena() -> void:
	for side in 4:
		for t in TIERS:
			var tier := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			var depth := 3.0
			var height := 1.1
			if side < 2:
				mesh.size = Vector3(COURT_LENGTH + 40.0 + t * 6.0, height, depth)
				tier.position = Vector3(COURT_LENGTH / 2.0, height * (t + 0.5), (-12.0 - t * depth) if side == 0 else (COURT_WIDTH + 12.0 + t * depth))
			else:
				mesh.size = Vector3(depth, height, COURT_WIDTH + 40.0 + t * 6.0)
				tier.position = Vector3((-16.0 - t * depth) if side == 2 else (COURT_LENGTH + 16.0 + t * depth), height * (t + 0.5), COURT_WIDTH / 2.0)
			tier.mesh = mesh
			tier.material_override = _tier_material(side, t)
			add_child(tier)


## Four LED boards around the court in the team colours (sidelines and end lines), each carrying the identity's rotating messages as text facing the
## court. Labels only face one way (double_sided off), so a board seen from behind is plain, not mirrored.
func _add_led_boards() -> void:
	var specs := [
		{"pos": Vector3(COURT_LENGTH / 2.0, 0.8, -3.0), "size": Vector3(COURT_LENGTH, 1.6, 0.3), "yaw": 0.0, "face": Vector3(0, 0, 1), "along": Vector3(1, 0, 0), "n": 5, "color": _home_color},
		{"pos": Vector3(COURT_LENGTH / 2.0, 0.8, COURT_WIDTH + 3.0), "size": Vector3(COURT_LENGTH, 1.6, 0.3), "yaw": 180.0, "face": Vector3(0, 0, -1), "along": Vector3(1, 0, 0), "n": 5, "color": _away_color},
		{"pos": Vector3(-3.0, 0.8, COURT_WIDTH / 2.0), "size": Vector3(0.3, 1.6, COURT_WIDTH), "yaw": 90.0, "face": Vector3(1, 0, 0), "along": Vector3(0, 0, 1), "n": 3, "color": _home_color},
		{"pos": Vector3(COURT_LENGTH + 3.0, 0.8, COURT_WIDTH / 2.0), "size": Vector3(0.3, 1.6, COURT_WIDTH), "yaw": -90.0, "face": Vector3(-1, 0, 0), "along": Vector3(0, 0, 1), "n": 3, "color": _away_color}]
	for spec in specs:
		var board := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = spec["size"]
		board.mesh = mesh
		board.material_override = _material(spec["color"], 0.9)
		board.position = spec["pos"]
		add_child(board)
		var length := (spec["size"] as Vector3).dot(spec["along"])
		for k in int(spec["n"]):
			var label := Label3D.new()
			label.font_size = 48
			label.pixel_size = 0.026
			label.modulate = Color.WHITE
			label.shaded = false
			label.double_sided = false
			label.rotation_degrees = Vector3(0.0, float(spec["yaw"]), 0.0)
			var offset: float = (float(k) + 0.5) / float(spec["n"]) - 0.5
			label.position = (spec["pos"] as Vector3) + (spec["along"] as Vector3) * (offset * length) + (spec["face"] as Vector3) * 0.2
			add_child(label)
			_led_labels.append(label)
	_apply_led_text()


func _apply_led_text() -> void:
	var text := led_text()
	for label in _led_labels:
		label.text = text


## A bench for each team behind the far sideline, with a row of seated figures in the team colours: two MultiMeshes (bodies and heads), so the
## whole bench area is a handful of draw calls.
func _add_benches() -> void:
	var seats := maxi(1, int(identity.get("bench_seats", 6)))
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.9, 1.5, 0.7)
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.32
	head_mesh.height = 0.64
	var bodies := MultiMesh.new()
	var heads := MultiMesh.new()
	for mm in [bodies, heads]:
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
	bodies.mesh = body_mesh
	heads.mesh = head_mesh
	bodies.instance_count = seats * 2
	heads.instance_count = seats * 2
	var skins: Array = identity["bench_skins"]
	var rng := FcRng.new(4242)
	for team in 2:
		var cx := COURT_LENGTH * (0.29 if team == 0 else 0.71)
		var width := float(seats) * 1.2 + 1.0
		for part in [[Vector3(width, 0.4, 1.8), Vector3(cx, 1.6, -7.5)], [Vector3(width, 1.6, 0.25), Vector3(cx, 2.6, -8.6)]]:
			var piece := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = part[0]
			piece.mesh = box
			piece.material_override = _material(identity["bench_furniture"])
			piece.position = part[1]
			add_child(piece)
		for k in seats:
			var x := cx + (float(k) - float(seats - 1) / 2.0) * 1.2
			var index := team * seats + k
			bodies.set_instance_transform(index, Transform3D(Basis(), Vector3(x, 2.55, -7.4)))
			bodies.set_instance_color(index, _home_color if team == 0 else _away_color)
			heads.set_instance_transform(index, Transform3D(Basis(), Vector3(x, 3.6, -7.4)))
			heads.set_instance_color(index, skins[rng.range_int(0, skins.size() - 1)])
	for mm in [bodies, heads]:
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		node.material_override = material
		add_child(node)
		_bench_nodes.append(node)
	_bench_figures = seats * 2


func _add_scoreboard() -> void:
	var housing := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(26.0, 6.5, 0.6)
	housing.mesh = mesh
	housing.material_override = _material(Color("0B1020"))
	housing.position = Vector3(COURT_LENGTH / 2.0, 36.0, COURT_WIDTH / 2.0)
	add_child(housing)
	for facing in [0.0, 180.0]:
		var label := Label3D.new()
		label.font_size = 64
		label.pixel_size = 0.036
		label.modulate = Color("FFB547")
		label.shaded = false
		label.text = "-"
		label.rotation_degrees = Vector3(0.0, facing, 0.0)
		label.position = Vector3(COURT_LENGTH / 2.0, 36.0, COURT_WIDTH / 2.0 + (0.35 if facing == 0.0 else -0.35))
		add_child(label)
		_score_labels.append(label)


## One MultiMesh of camera-facing cards (B1b measured about 0.04 ms for 6,000). Colours and sizes come from FcCrowdPlan (home, away and neutral fans);
## the motion is in crowd.gdshader. One section at a time still stands at event times (stand_section).
func _add_crowd() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.9, 1.5)
	var shader := load("res://src/ui/broadcast3d/crowd.gdshader") as Shader
	var material: Material
	if shader != null:
		_crowd_material = ShaderMaterial.new()
		_crowd_material.shader = shader
		material = _crowd_material
	else:   # the shader could not be loaded: plain camera-facing cards, no animation
		var plain := StandardMaterial3D.new()
		plain.vertex_color_use_as_albedo = true
		plain.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		plain.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material = plain
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	var homes: Array[Transform3D] = []
	var sides: Array = []
	var alongs: Array = []
	for side in 4:
		for t in TIERS:
			var row_y := 1.1 * (t + 1.0) + 0.75
			var span := (COURT_LENGTH + 40.0 + t * 6.0) if side < 2 else (COURT_WIDTH + 40.0 + t * 6.0)
			var count := int(span / 1.3)
			var start := -span / 2.0
			var section_start := homes.size()
			for k in count:
				if homes.size() >= crowd_count:
					break
				var along := start + k * 1.3
				var pos: Vector3
				match side:
					0: pos = Vector3(COURT_LENGTH / 2.0 + along, row_y, -12.0 - t * 3.0 + 0.5)
					1: pos = Vector3(COURT_LENGTH / 2.0 + along, row_y, COURT_WIDTH + 12.0 + t * 3.0 - 0.5)
					2: pos = Vector3(-16.0 - t * 3.0 + 0.5, row_y, COURT_WIDTH / 2.0 + along)
					_: pos = Vector3(COURT_LENGTH + 16.0 + t * 3.0 - 0.5, row_y, COURT_WIDTH / 2.0 + along)
				homes.append(Transform3D(Basis(), pos))
				sides.append(side)
				alongs.append((along + span / 2.0) / span)
			if homes.size() > section_start and t % SECTION_ROW_STEP == 0:
				_sections.append([section_start, homes.size() - section_start])
	var plan := FcCrowdPlan.plan(identity, sides, alongs)
	mm.instance_count = homes.size()
	_crowd_scales = []
	for i in homes.size():
		var fan_scale: float = plan["scales"][i]
		_crowd_scales.append(fan_scale)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(fan_scale, fan_scale, 1.0)), homes[i].origin))
		mm.set_instance_color(i, plan["colors"][i])
	_crowd_homes = homes
	_crowd = MultiMeshInstance3D.new()
	_crowd.multimesh = mm
	_crowd.material_override = material
	add_child(_crowd)
