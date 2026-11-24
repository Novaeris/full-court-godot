class_name FcHoopBuilder
extends RefCounted
## One basketball hoop (3D overhaul M3), with real proportions in feet: a padded stanchion with a support arm, a glass backboard 6 ft by 3.5 ft in a
## white frame with the 24 by 18 inch shooter's square, a 10 ft rim of 18 inch inside diameter on a bracket, and a diamond-mesh net that swings when
## a shot goes through (net.gdshader). Built facing +x (the court's inside) with the RIM CENTRE at the node's origin; the scene turns the far hoop
## by 180 degrees. Everything is a handful of meshes: a hoop is about ten draw calls.

const RIM_HEIGHT := 10.0
const RIM_RADIUS := 0.75           # centre of the tube: 18 inch inside diameter plus the tube
const RIM_TUBE := 0.03
const BOARD_WIDTH := 6.0
const BOARD_HEIGHT := 3.5
const BOARD_BEHIND_RIM := 1.25     # the rim centre is 15 inches in front of the board's face
const NET_DEPTH := 1.5
const NET_STRANDS := 12
const NET_LEVELS := 5


## Builds the hoop under `parent`, its rim centre at `position` (world), facing `facing` (+1 the court is towards +x, -1 towards -x).
## Returns {"root": Node3D, "net": ShaderMaterial, "rim": Vector3 (world centre of the rim)}.
static func build(parent: Node3D, position: Vector3, facing: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Hoop"
	root.position = position
	root.rotation_degrees.y = 0.0 if facing > 0 else 180.0
	parent.add_child(root)
	var steel := _material(FcScenePalette.color("stanchion"), 0.5, 0.4)
	var pad := _material(FcScenePalette.color("pad"), 0.9)
	var frame := _material(FcScenePalette.color("board_frame"), 0.5)
	# --- stanchion: a padded base behind the baseline, a pole, and an arm reaching the back of the board
	var board_x := -BOARD_BEHIND_RIM
	var base_x := board_x - 5.2
	_box(root, Vector3(1.6, 0.5, 2.6), Vector3(base_x, 0.25, 0.0), steel)
	_box(root, Vector3(0.9, 4.2, 2.2), Vector3(base_x, 2.6, 0.0), pad)        # the padding a player would hit
	_box(root, Vector3(0.45, 9.0, 0.6), Vector3(base_x, 7.5, 0.0), steel)    # the pole
	_box(root, Vector3(5.6, 0.45, 0.6), Vector3(board_x - 2.9, 12.0 - 0.9, 0.0), steel)   # the arm from the pole to the board
	# --- backboard: glass, frame, and the shooter's square
	var glass := StandardMaterial3D.new()
	glass.albedo_color = FcScenePalette.color("glass")
	glass.albedo_color.a = 0.3
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	glass.metallic_specular = 0.8
	var centre_y := RIM_HEIGHT + 0.75
	_box(root, Vector3(0.1, BOARD_HEIGHT, BOARD_WIDTH), Vector3(board_x - 0.05, centre_y, 0.0), glass)
	var t := 0.12
	_box(root, Vector3(0.14, t, BOARD_WIDTH), Vector3(board_x + 0.02, centre_y + BOARD_HEIGHT * 0.5 - t * 0.5, 0.0), frame)
	_box(root, Vector3(0.14, t, BOARD_WIDTH), Vector3(board_x + 0.02, centre_y - BOARD_HEIGHT * 0.5 + t * 0.5, 0.0), frame)
	_box(root, Vector3(0.14, BOARD_HEIGHT, t), Vector3(board_x + 0.02, centre_y, BOARD_WIDTH * 0.5 - t * 0.5), frame)
	_box(root, Vector3(0.14, BOARD_HEIGHT, t), Vector3(board_x + 0.02, centre_y, -BOARD_WIDTH * 0.5 + t * 0.5), frame)
	var square := _material(FcScenePalette.color("board_square"), 0.6)
	var sq_w := 2.0
	var sq_h := 1.5
	var sq_y := RIM_HEIGHT + sq_h * 0.5
	var st := 0.06
	_box(root, Vector3(0.04, st, sq_w), Vector3(board_x + 0.03, sq_y + sq_h * 0.5, 0.0), square)
	_box(root, Vector3(0.04, st, sq_w), Vector3(board_x + 0.03, sq_y - sq_h * 0.5, 0.0), square)
	_box(root, Vector3(0.04, sq_h, st), Vector3(board_x + 0.03, sq_y, sq_w * 0.5), square)
	_box(root, Vector3(0.04, sq_h, st), Vector3(board_x + 0.03, sq_y, -sq_w * 0.5), square)
	# --- rim and bracket
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = RIM_RADIUS - RIM_TUBE
	rim_mesh.outer_radius = RIM_RADIUS + RIM_TUBE
	rim_mesh.rings = 24
	rim_mesh.ring_segments = 8
	var rim := MeshInstance3D.new()
	rim.mesh = rim_mesh
	rim.material_override = _material(FcScenePalette.color("rim"), 0.35, 0.3)
	rim.position = Vector3.ZERO
	root.add_child(rim)
	_box(root, Vector3(BOARD_BEHIND_RIM - RIM_RADIUS + 0.1, 0.1, 0.4), Vector3(board_x + (BOARD_BEHIND_RIM - RIM_RADIUS + 0.1) * 0.5, -0.02, 0.0), _material(FcScenePalette.color("rim_bracket"), 0.4, 0.5))
	# --- net
	var net_material := ShaderMaterial.new()
	net_material.shader = load("res://src/ui/broadcast3d/net.gdshader") as Shader
	net_material.set_shader_parameter("depth", NET_DEPTH)
	net_material.set_shader_parameter("net_colour", FcScenePalette.color("net"))
	var net := MeshInstance3D.new()
	net.mesh = net_mesh()
	net.material_override = net_material
	net.position = Vector3(0.0, -0.02, 0.0)
	root.add_child(net)
	return {"root": root, "net": net_material, "rim": position}


## The net: levels of nodes on shrinking rings, each node joined to the two below it (a diamond pattern), as lines.
static func net_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	for level in NET_LEVELS:
		for i in NET_STRANDS:
			var here := _net_node(level, i)
			verts.append(here)
			verts.append(_net_node(level + 1, i))
			verts.append(here)
			verts.append(_net_node(level + 1, i + 1))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


static func _net_node(level: int, index: int) -> Vector3:
	var t := float(level) / float(NET_LEVELS)
	var radius := lerpf(RIM_RADIUS, 0.46, t)
	var angle := TAU * (float(index) + (0.5 if level % 2 == 1 else 0.0)) / float(NET_STRANDS)
	return Vector3(cos(angle) * radius, -NET_DEPTH * t, sin(angle) * radius)


## Sets how hard the net swings (1 right after a shot goes through, falling to 0).
static func swish(net_material: ShaderMaterial, amount: float) -> void:
	net_material.set_shader_parameter("swish", clampf(amount, 0.0, 1.0))


static func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


static func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node
