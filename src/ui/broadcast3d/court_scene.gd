class_name FcCourtScene
extends Node3D
## The 3D arena of the broadcast view (decision D-070), built entirely in code, no assets: a court with the home team's colour on the paint and
## its abbreviation at centre, two hoops, stepped stands with an INSTANCED crowd (one MultiMesh of camera-facing cards: a few draw calls whatever
## the count, measured in B1b), courtside boards in the team colours, a scoreboard with the live score and clock, one shadow-casting light and
## a camera. Units are feet, the convention of FcCourtLayout: x along the length, z across the width (the court's y), y up. Presentation only:
## nothing here reads or changes a game; the viewer tells it what to show.

const COURT_LENGTH := FcCourtLayout.COURT_LENGTH
const COURT_WIDTH := FcCourtLayout.COURT_WIDTH
const TIERS := 16
const SECTION_ROW_STEP := 4

var crowd_count: int = 6000
var shadows: bool = true
var camera: Camera3D

var _home_color := Color("2F6FED")
var _away_color := Color("F28A2E")
var _home_abbreviation := ""
var _crowd: MultiMeshInstance3D
var _crowd_homes: Array[Transform3D] = []
var _sections: Array = []   # [first instance, count] groups that stand up together
var _score_labels: Array[Label3D] = []
var _standing_section: int = -1


func build(home_color: Color, away_color: Color, home_abbreviation: String) -> void:
	_home_color = home_color
	_away_color = away_color
	_home_abbreviation = home_abbreviation
	_add_environment()
	_add_light()
	_add_court()
	_add_hoops()
	_add_arena()
	_add_scoreboard()
	_add_crowd()
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
			var basis := Basis().scaled(Vector3(1.0, 1.35 if standing else 1.0, 1.0))
			mm.set_instance_transform(i, Transform3D(basis, home.origin + Vector3(0.0, 0.25 if standing else 0.0, 0.0)))
	_standing_section = index


func standing_section() -> int:
	return _standing_section


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
	env.ambient_light_energy = 0.6
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


func _add_court() -> void:
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(COURT_LENGTH, COURT_WIDTH)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(_court_image())
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


## The court's markings drawn into a texture, the paints tinted with the home team's colour (10 pixels per foot).
func _court_image() -> Image:
	var w := int(COURT_LENGTH * 10.0)
	var h := int(COURT_WIDTH * 10.0)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color("B87A43"))
	for i in range(0, 10, 2):
		img.fill_rect(Rect2i(i * w / 10, 0, w / 10, h), Color("A5693A"))
	var paint := _home_color.lerp(Color("B87A43"), 0.35)
	img.fill_rect(Rect2i(0, h / 2 - 80, 190, 160), paint)
	img.fill_rect(Rect2i(w - 190, h / 2 - 80, 190, 160), paint)
	var line := Color("F4EBDD")
	img.fill_rect(Rect2i(0, 0, w, 6), line)
	img.fill_rect(Rect2i(0, h - 6, w, 6), line)
	img.fill_rect(Rect2i(0, 0, 6, h), line)
	img.fill_rect(Rect2i(w - 6, 0, 6, h), line)
	img.fill_rect(Rect2i(w / 2 - 3, 0, 6, h), line)
	for k in 360:
		var a := TAU * k / 360.0
		img.fill_rect(Rect2i(int(w / 2.0 + cos(a) * 60.0), int(h / 2.0 + sin(a) * 60.0), 6, 6), line)
	for right in [false, true]:
		var base_x := w if right else 0
		var dir := -1 if right else 1
		var paint_x := base_x if not right else base_x - 190
		img.fill_rect(Rect2i(paint_x, h / 2 - 80, 190, 6), line)
		img.fill_rect(Rect2i(paint_x, h / 2 + 74, 190, 6), line)
		img.fill_rect(Rect2i(base_x + dir * 190 - (6 if right else 0), h / 2 - 80, 6, 160), line)
		var hoop_x := (w - 52) if right else 52
		for k in 180:
			var a := (PI if right else 0.0) - 1.15 + 2.3 * k / 180.0
			img.fill_rect(Rect2i(int(hoop_x + cos(a) * 237.0), int(h / 2.0 + sin(a) * 237.0), 5, 5), line)
	return img


func _add_hoops() -> void:
	for right in [false, true]:
		var x := COURT_LENGTH - FcCourtLayout.BASKET_FROM_BASELINE if right else FcCourtLayout.BASKET_FROM_BASELINE
		var pole := MeshInstance3D.new()
		var pole_mesh := BoxMesh.new()
		pole_mesh.size = Vector3(0.6, 10.0, 0.6)
		pole.mesh = pole_mesh
		pole.material_override = _material(Color("C9D2E3"))
		pole.position = Vector3(x + (4.0 if right else -4.0), 5.0, COURT_WIDTH / 2.0)
		add_child(pole)
		var board := MeshInstance3D.new()
		var board_mesh := BoxMesh.new()
		board_mesh.size = Vector3(0.2, 3.5, 6.0)
		board.mesh = board_mesh
		board.material_override = _material(Color("F2F5FA"))
		board.position = Vector3(x + (1.2 if right else -1.2), 11.0, COURT_WIDTH / 2.0)
		add_child(board)
		var rim := MeshInstance3D.new()
		var rim_mesh := TorusMesh.new()
		rim_mesh.inner_radius = 0.7
		rim_mesh.outer_radius = 0.78
		rim.mesh = rim_mesh
		rim.material_override = _material(Color("F28A2E"))
		rim.position = Vector3(x, 10.0, COURT_WIDTH / 2.0)
		add_child(rim)


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
			tier.material_override = _material(Color("27324A") if t % 2 == 0 else Color("202A40"))
			add_child(tier)
	for side in 2:   # the courtside boards, in the team colours
		var board := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(COURT_LENGTH, 1.6, 0.3)
		board.mesh = mesh
		board.material_override = _material(_home_color if side == 0 else _away_color, 1.2)
		board.position = Vector3(COURT_LENGTH / 2.0, 0.8, -3.0 if side == 0 else COURT_WIDTH + 3.0)
		add_child(board)


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


## One MultiMesh of camera-facing cards (B1b measured about 0.04 ms for 6,000), a colour each; one section at a time stands at event times.
func _add_crowd() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.9, 1.5)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	var homes: Array[Transform3D] = []
	var palette := [Color("C94B4B"), Color("E8B04B"), Color("4B8BC9"), Color("F0F0F0"), Color("5BB07A"), Color("8B5BC9"), Color("2B2B2B"), _home_color, _away_color]
	var rng := FcRng.new(9001)
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
			if homes.size() > section_start and t % SECTION_ROW_STEP == 0:
				_sections.append([section_start, homes.size() - section_start])
	mm.instance_count = homes.size()
	for i in homes.size():
		mm.set_instance_transform(i, homes[i])
		mm.set_instance_color(i, palette[rng.range_int(0, palette.size() - 1)])
	_crowd_homes = homes
	_crowd = MultiMeshInstance3D.new()
	_crowd.multimesh = mm
	_crowd.material_override = material
	add_child(_crowd)
