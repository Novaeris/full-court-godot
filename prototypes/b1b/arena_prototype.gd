class_name FcB1bArena
extends Node3D
## THROWAWAY prototype for milestone B1b (master plan 4.12a): can a 3D basketball broadcast run inside the hardware budget with the project's
## gl_compatibility renderer? One court, TEN PLACEHOLDER PLAYERS (capsules), one ball, one camera, a basic arena (stands, scoreboard, courtside
## boards), one shadow-casting light and an INSTANCED CROWD. No player models, no animation library, no production art. It is built entirely in
## code, scripted (no simulation, no reconstruction), not part of any shipped screen, and measured by tools/perf_benchmark.gd mode=3d.
## Units are feet (1 unit = 1 ft), the court convention of FcCourtLayout: x along the length, z across the width (the court's y), y up.

const COURT_LENGTH := 94.0
const COURT_WIDTH := 50.0

var crowd_count: int = 6000
var shadows: bool = true
var viewport_scoreboard: bool = true
var camera: Camera3D

var _players: Array[MeshInstance3D] = []
var _bases: Array[Vector3] = []
var _ball: MeshInstance3D
var _crowd: MultiMeshInstance3D
var _crowd_homes: Array[Transform3D] = []
var _sections: Array = []   # [first instance, count] groups that stand up together
var _board_viewport: SubViewport
var _board_label: Label
var _t: float = 0.0
var _next_wave: float = 2.0
var _wave: int = 0
var _board_clock: float = 0.0


## Builds the whole scene. Call once after adding to the tree.
func build() -> void:
	_add_environment()
	_add_light()
	_add_court()
	_add_hoops()
	_add_arena()
	_add_scoreboard()
	_add_players_and_ball()
	_add_crowd()
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.current = true
	add_child(camera)
	set_camera(Vector3(47, 40, 82), Vector3(47, 0, 22))


func set_camera(from: Vector3, look_at_point: Vector3) -> void:
	camera.position = from
	camera.look_at(look_at_point, Vector3.UP)


func _process(delta: float) -> void:
	_t += delta
	for i in _players.size():
		var base := _bases[i]
		var phase := _t * 0.9 + float(i)
		_players[i].position = base + Vector3(sin(phase) * 3.0, 0.0, cos(phase * 0.8) * 2.5)
	var a := _players[int(_t * 0.5) % 10].position
	var b := _players[(int(_t * 0.5) + 3) % 10].position
	var f := fmod(_t * 0.5, 1.0)
	_ball.position = a.lerp(b, f) + Vector3(0.0, 3.0 + 5.0 * sin(f * PI), 0.0)
	if _t >= _next_wave:
		_next_wave += 2.0
		_stand_section(_wave % _sections.size())
		_wave += 1
	if viewport_scoreboard and _board_label != null:
		_board_clock += delta
		if _board_clock >= 1.0:
			_board_clock = 0.0
			_board_label.text = "HOME %d   Q3 %d:%02d   AWAY %d" % [60 + int(_t) % 40, 11 - int(_t / 60.0) % 11, 59 - int(_t) % 60, 55 + int(_t) % 38]


# --- the scene ---------------------------------------------------------------------------------------------------------------

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


func _material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


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


## The court's markings drawn into a texture (1 px = 0.1 ft would be too big; 1 px = 0.5 ft is enough for a prototype).
func _court_image() -> Image:
	var w := int(COURT_LENGTH * 10.0)
	var h := int(COURT_WIDTH * 10.0)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color("B87A43"))
	for i in range(0, 10, 2):
		img.fill_rect(Rect2i(i * w / 10, 0, w / 10, h), Color("A5693A"))
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
		var x := COURT_LENGTH - 5.25 if right else 5.25
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
	var tiers := 16
	for side in 4:
		for t in tiers:
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
	for side in 2:   # courtside boards
		var board := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(COURT_LENGTH, 1.6, 0.3)
		board.mesh = mesh
		board.material_override = _material(Color("39A9FF") if side == 0 else Color("FF8A24"), 1.2)
		board.position = Vector3(COURT_LENGTH / 2.0, 0.8, -3.0 if side == 0 else COURT_WIDTH + 3.0)
		add_child(board)


func _add_scoreboard() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if viewport_scoreboard:
		_board_viewport = SubViewport.new()
		_board_viewport.size = Vector2i(512, 128)
		_board_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		var back := ColorRect.new()
		back.color = Color("0B1020")
		back.size = Vector2(512, 128)
		_board_viewport.add_child(back)
		_board_label = Label.new()
		_board_label.text = "HOME 60   Q3 11:59   AWAY 55"
		_board_label.add_theme_font_size_override("font_size", 40)
		_board_label.position = Vector2(20, 36)
		_board_viewport.add_child(_board_label)
		add_child(_board_viewport)
		m.albedo_texture = _board_viewport.get_texture()
	else:
		var img := Image.create(512, 128, false, Image.FORMAT_RGB8)
		img.fill(Color("0B1020"))
		img.fill_rect(Rect2i(20, 40, 472, 48), Color("FFB547"))
		m.albedo_texture = ImageTexture.create_from_image(img)
	for facing in [0.0, 180.0]:
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(26.0, 6.5)
		quad.mesh = mesh
		quad.material_override = m
		quad.position = Vector3(COURT_LENGTH / 2.0, 36.0, COURT_WIDTH / 2.0 + (0.2 if facing == 0.0 else -0.2))
		quad.rotation_degrees = Vector3(0.0, facing, 0.0)
		add_child(quad)


func _add_players_and_ball() -> void:
	var shape := FcCourtLayout.formation(true)
	var spots: Array[Vector2] = []
	spots.append_array(shape["offense"])
	spots.append_array(shape["defense"])
	for i in 10:
		var mesh := CapsuleMesh.new()
		mesh.radius = 1.0
		mesh.height = 6.2 + float(i % 3) * 0.3
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = _material(Color("39A9FF") if i < 5 else Color("FF8A24"))
		var base := Vector3(spots[i].x, mesh.height / 2.0, spots[i].y)
		node.position = base
		add_child(node)
		_players.append(node)
		_bases.append(base)
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = 0.45
	ball_mesh.height = 0.9
	_ball = MeshInstance3D.new()
	_ball.mesh = ball_mesh
	_ball.material_override = _material(Color("F28A2E"))
	add_child(_ball)


## The crowd: ONE MultiMesh of camera-facing cards (a few draw calls whatever the count), each with its own colour; seated and standing are
## two heights, and one section at a time stands up at event times (the plan's reaction model), not every person every frame.
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
	var palette := [Color("C94B4B"), Color("E8B04B"), Color("4B8BC9"), Color("F0F0F0"), Color("5BB07A"), Color("8B5BC9"), Color("2B2B2B")]
	var rng := FcRng.new(9001)
	for side in 4:
		for t in 16:
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
			if homes.size() > section_start and t % 4 == 0:
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
	if _sections.is_empty():
		_sections.append([0, 1])


## One section stands up (taller), the previous one sits down again.
func _stand_section(index: int) -> void:
	var mm := _crowd.multimesh
	for s in _sections.size():
		var standing := s == index
		var first: int = _sections[s][0]
		var count: int = _sections[s][1]
		for i in range(first, mini(first + count, mm.instance_count)):
			var home := _crowd_homes[i]
			var basis := Basis().scaled(Vector3(1.0, 1.35 if standing else 1.0, 1.0))
			mm.set_instance_transform(i, Transform3D(basis, home.origin + Vector3(0.0, 0.25 if standing else 0.0, 0.0)))


func instance_count() -> int:
	return _crowd.multimesh.instance_count if _crowd != null else 0
