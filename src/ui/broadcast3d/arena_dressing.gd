class_name FcArenaDressing
extends RefCounted
## The furniture and finish of the 3D arena (3D overhaul M4), added to the one FcCourtScene from an FcArenaIdentity, so a different home team gets a
## differently dressed arena and not a different scene: team-coloured seating sections with aisles, the back walls with championship banners and the
## team name, a lighting truss with lamps, an LED ribbon round the lower bowl, a scorer table with its staff, and courtside seats with spectators.
## Everything is a handful of meshes or one MultiMesh per kind (a seat, a person), so the crowd architecture is untouched and nothing is processed
## per spectator. Pure construction: no game data is read or changed.

const TIERS := 16
const TIER_DEPTH := 3.0
const TIER_HEIGHT := 1.1


## The colour of a seating tier box on `side` (0 near, 1 far, 2 left end, 3 right end) at tier `t`: the lower bowl in the home team colour (the
## visitors end in theirs), the upper bowl in a neutral dark, every other row a shade apart.
static func seat_color(identity: Dictionary, side: int, t: int) -> Color:
	var base: Color
	if t < 8:
		base = (identity["away_color"] as Color).darkened(0.62) if side == 3 else (identity["home_color"] as Color).darkened(0.6)
	else:
		base = FcScenePalette.color("seat_a")
	return base if t % 2 == 0 else base.darkened(0.14)


## Everything beyond the seats and the court, in one call. Returns a summary {seat_aisles, banners, lamps, staff, courtside} for tests.
static func add_all(scene: Node3D, identity: Dictionary) -> Dictionary:
	var out := {}
	out["seat_aisles"] = _aisles(scene)
	out["banners"] = _walls_and_banners(scene, identity)
	out["lamps"] = _truss(scene, identity)
	_ribbon(scene, identity)
	out["staff"] = _scorers_table(scene, identity)
	out["courtside"] = _courtside(scene, identity)
	return out


static func _material(color: Color, rough: float = 0.8, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


static func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # dressing never shades the court (the sun casts the players' shadows only)
	parent.add_child(node)
	return node


## Steps (aisles) running up through the seating, as ONE MultiMesh of dark slabs: four aisles on each of the four sides.
static func _aisles(scene: Node3D) -> int:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var slab := BoxMesh.new()
	slab.size = Vector3(0.9, TIER_HEIGHT + 0.04, TIER_DEPTH + 0.02)
	mm.mesh = slab
	var transforms: Array[Transform3D] = []
	for side in 4:
		for t in TIERS:
			var span := (94.0 + 40.0 + t * 6.0) if side < 2 else (50.0 + 40.0 + t * 6.0)
			for k in 4:
				var along := (float(k) + 1.0) / 5.0 * span - span / 2.0
				var y := TIER_HEIGHT * (t + 0.5)
				var pos: Vector3
				var basis := Basis()
				match side:
					0: pos = Vector3(47.0 + along, y, -12.0 - t * TIER_DEPTH)
					1: pos = Vector3(47.0 + along, y, 50.0 + 12.0 + t * TIER_DEPTH)
					2:
						pos = Vector3(-16.0 - t * TIER_DEPTH, y, 25.0 + along)
						basis = Basis(Vector3.UP, PI / 2.0)
					_:
						pos = Vector3(94.0 + 16.0 + t * TIER_DEPTH, y, 25.0 + along)
						basis = Basis(Vector3.UP, PI / 2.0)
				transforms.append(Transform3D(basis, pos))
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.material_override = _material(FcScenePalette.color("concrete"), 0.95)
	scene.add_child(node)
	return transforms.size()


## Back walls behind the highest row, and championship banners hanging on the far one in the home colours, each with the team name.
static func _walls_and_banners(scene: Node3D, identity: Dictionary) -> int:
	var wall_material := _material(FcScenePalette.color("concrete"), 0.95)
	var top := TIER_HEIGHT * TIERS + 6.0
	_box(scene, Vector3(260.0, 60.0, 1.0), Vector3(47.0, 30.0, -12.0 - TIERS * TIER_DEPTH - 2.0), wall_material)
	_box(scene, Vector3(260.0, 60.0, 1.0), Vector3(47.0, 30.0, 62.0 + TIERS * TIER_DEPTH + 2.0), wall_material)
	_box(scene, Vector3(1.0, 60.0, 200.0), Vector3(-16.0 - TIERS * TIER_DEPTH - 2.0, 30.0, 25.0), wall_material)
	_box(scene, Vector3(1.0, 60.0, 200.0), Vector3(110.0 + TIERS * TIER_DEPTH + 2.0, 30.0, 25.0), wall_material)
	var hash_value := FcPlayerVisual.fnv1a(str(identity["key"]))
	var count := 3 + int(hash_value % 4)
	var banner_color: Color = identity["home_color"]
	var nickname := str(identity.get("home_nickname", ""))
	var far_z := -12.0 - TIERS * TIER_DEPTH - 1.4
	var made := 0
	for i in count:
		var x := 47.0 + (float(i) - float(count - 1) / 2.0) * 22.0
		var tone := banner_color.darkened(0.15 + 0.08 * float(i % 2))
		_box(scene, Vector3(7.0, 14.0, 0.15), Vector3(x, top + 13.0, far_z), _material(tone, 0.7))
		_box(scene, Vector3(7.4, 0.6, 0.2), Vector3(x, top + 20.2, far_z), _material(identity["accent"] as Color, 0.6))
		var label := Label3D.new()
		label.text = nickname if nickname != "" else str(identity["home_abbr"])
		label.font_size = 40
		label.pixel_size = 0.03
		label.modulate = Color.WHITE
		label.shaded = false
		label.double_sided = false
		label.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		label.position = Vector3(x, top + 15.0, far_z + 0.12)
		scene.add_child(label)
		made += 1
	return made


## A lighting truss: a rectangle frame high above the court with a row of lamps along both long sides that glow.
static func _truss(scene: Node3D, identity: Dictionary) -> int:
	var y := 58.0
	var steel := _material(FcScenePalette.color("stanchion"), 0.6)
	var x0 := -6.0
	var x1 := 100.0
	var z0 := -14.0
	var z1 := 64.0
	_box(scene, Vector3(x1 - x0, 0.8, 0.8), Vector3((x0 + x1) / 2.0, y, z0), steel)
	_box(scene, Vector3(x1 - x0, 0.8, 0.8), Vector3((x0 + x1) / 2.0, y, z1), steel)
	_box(scene, Vector3(0.8, 0.8, z1 - z0), Vector3(x0, y, (z0 + z1) / 2.0), steel)
	_box(scene, Vector3(0.8, 0.8, z1 - z0), Vector3(x1, y, (z0 + z1) / 2.0), steel)
	var lamp := _material(identity["light_tint"] as Color, 0.3, 2.2)
	var lamps := 0
	for k in 8:
		var x := lerpf(x0 + 6.0, x1 - 6.0, float(k) / 7.0)
		for z in [z0, z1]:
			_box(scene, Vector3(2.4, 0.6, 1.2), Vector3(x, y - 0.7, z), lamp)
			lamps += 1
	return lamps


## The LED ribbon round the front of the lower bowl: four boxes in front of the face of tier 8 carrying the scrolling chevrons.
static func _ribbon(scene: Node3D, identity: Dictionary) -> void:
	var shader := load("res://src/ui/broadcast3d/led_ribbon.gdshader") as Shader
	if shader == null:
		return
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("colour_a", identity["home_color"])
	material.set_shader_parameter("colour_b", identity["accent"])
	material.set_shader_parameter("colour_c", identity["away_color"])
	var y := TIER_HEIGHT * 7.0 + 0.55
	_box(scene, Vector3(94.0 + 40.0 + 7.0 * 6.0, 1.0, 0.25), Vector3(47.0, y, -12.0 - 7.0 * TIER_DEPTH + 1.5), material)
	_box(scene, Vector3(94.0 + 40.0 + 7.0 * 6.0, 1.0, 0.25), Vector3(47.0, y, 62.0 + 7.0 * TIER_DEPTH - 1.5), material)
	_box(scene, Vector3(0.25, 1.0, 50.0 + 40.0 + 7.0 * 6.0), Vector3(-16.0 - 7.0 * TIER_DEPTH + 1.5, y, 25.0), material)
	_box(scene, Vector3(0.25, 1.0, 50.0 + 40.0 + 7.0 * 6.0), Vector3(110.0 + 7.0 * TIER_DEPTH - 1.5, y, 25.0), material)


## Two MultiMeshes (bodies and heads) of seated people at `spots` (world positions of the floor under each seat), in colours from `colors`, skin from `skins`.
static func _seated_people(scene: Node3D, spots: Array, colors: Array, skins: Array, seed_value: int, facing_yaw: float) -> int:
	if spots.is_empty():
		return 0
	var bodies := MultiMesh.new()
	var heads := MultiMesh.new()
	for mm in [bodies, heads]:
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.instance_count = spots.size()
	var body := BoxMesh.new()
	body.size = Vector3(0.9, 1.4, 0.6)
	var head := SphereMesh.new()
	head.radius = 0.3
	head.height = 0.6
	bodies.mesh = body
	heads.mesh = head
	var rng := FcRng.new(seed_value)
	for i in spots.size():
		var p: Vector3 = spots[i]
		var basis := Basis(Vector3.UP, facing_yaw)
		bodies.set_instance_transform(i, Transform3D(basis, p + Vector3(0.0, 1.5, 0.0)))
		bodies.set_instance_color(i, colors[rng.range_int(0, colors.size() - 1)])
		heads.set_instance_transform(i, Transform3D(basis, p + Vector3(0.0, 2.55, 0.0)))
		heads.set_instance_color(i, skins[rng.range_int(0, skins.size() - 1)])
	for mm in [bodies, heads]:
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		node.material_override = material
		scene.add_child(node)
	return spots.size()


## The scorer table on the far sideline between the benches, its front lit in the home colours, with its staff seated behind it.
static func _scorers_table(scene: Node3D, identity: Dictionary) -> int:
	var z := -6.2
	_box(scene, Vector3(18.0, 2.6, 2.4), Vector3(47.0, 1.3, z), _material(FcScenePalette.color("table"), 0.7))
	_box(scene, Vector3(18.2, 0.15, 2.6), Vector3(47.0, 2.65, z), _material(FcScenePalette.color("table_top"), 0.5))
	_box(scene, Vector3(17.0, 1.4, 0.1), Vector3(47.0, 1.5, z + 1.25), _material(identity["home_color"] as Color, 0.4, 1.0))
	for i in 5:   # laptops and screens on the table
		_box(scene, Vector3(0.9, 0.7, 0.08), Vector3(47.0 + (float(i) - 2.0) * 3.2, 3.1, z - 0.2), _material(FcScenePalette.color("pad"), 0.4, 0.2))
	var spots: Array = []
	for i in 5:
		spots.append(Vector3(47.0 + (float(i) - 2.0) * 3.2, 0.9, z - 2.2))
	var palette: Array = [FcScenePalette.color("official_shirt"), identity["accent"], FcScenePalette.color("coach_suit")]
	return _seated_people(scene, spots, palette, identity["bench_skins"], 8181, PI)


## Rows of courtside seats with spectators behind both baskets and along the near sideline, in smart clothes and team colours.
static func _courtside(scene: Node3D, identity: Dictionary) -> int:
	var spots: Array = []
	var chair_transforms: Array[Transform3D] = []
	for end in 2:
		var x := -9.0 if end == 0 else 103.0
		for row in 2:
			for k in 11:
				var z := 25.0 + (float(k) - 5.0) * 2.7
				var p := Vector3(x + (-float(row) * 3.0 if end == 0 else float(row) * 3.0), 0.0, z)
				spots.append(p)
				chair_transforms.append(Transform3D(Basis(), p + Vector3(0.0, 0.9, 0.0)))
	for k in 14:
		var x := 47.0 + (float(k) - 6.5) * 3.3
		var p := Vector3(x, 0.0, 58.0)
		spots.append(p)
		chair_transforms.append(Transform3D(Basis(), p + Vector3(0.0, 0.9, 0.0)))
	var chairs := MultiMesh.new()
	chairs.transform_format = MultiMesh.TRANSFORM_3D
	var seat := BoxMesh.new()
	seat.size = Vector3(1.0, 0.5, 1.0)
	chairs.mesh = seat
	chairs.instance_count = chair_transforms.size()
	for i in chair_transforms.size():
		chairs.set_instance_transform(i, chair_transforms[i])
	var chair_node := MultiMeshInstance3D.new()
	chair_node.multimesh = chairs
	chair_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chair_node.material_override = _material(FcScenePalette.color("pad"), 0.8)
	scene.add_child(chair_node)
	var palette: Array = [identity["home_color"], FcScenePalette.color("coach_suit"), FcScenePalette.color("official_shirt"), identity["away_color"], FcScenePalette.color("seat_a")]
	var count := _seated_people(scene, spots.slice(0, 22), palette, identity["bench_skins"], 3131, -PI / 2.0)
	count += _seated_people(scene, spots.slice(22, 44), palette, identity["bench_skins"], 3132, PI / 2.0)
	count += _seated_people(scene, spots.slice(44), palette, identity["bench_skins"], 3133, PI)
	return count
