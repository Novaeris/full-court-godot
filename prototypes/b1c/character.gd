class_name FcB1cCharacter
extends Node3D
## THROWAWAY prototype for milestone B1c (master plan 4.12): one basketball player built ENTIRELY IN CODE from the identity data the game
## already has (FcPlayerVisual.resolve: skin tone, hair style and colour, facial hair, build class, height and weight, team colours, jersey
## number), with no model or animation file. A stylised low-poly body from capsules, spheres and boxes on a joint hierarchy, animated by
## FcB1cPose (idle, run, dribble, shoot, layup, defend) with cross-fades. Units are feet (1 unit = 1 ft). The 2D portraits are NOT used:
## they cannot become 3D (no depth); only the categorical identity data and colours drive the look.

const DEFAULT_HEIGHT_CM := 198.0
const DEFAULT_WEIGHT_KG := 95.0
const BLEND_SECONDS := 0.2

var identity: Dictionary = {}
var uniform: Dictionary = {}
var height_feet: float = 6.5
var width_scale: float = 1.0
var jersey_number: int = 0
var state: String = "idle"

var _joints: Dictionary = {}     # name -> Node3D
var _meshes: Array[MeshInstance3D] = []
var _from_pose: Dictionary = FcB1cPose.pose_for("idle", 0.0)
var _blend: float = 1.0
var _time: float = 0.0
var _phase_offset: float = 0.0
var _hand: Node3D
var _back_number: Label3D
var _front_number: Label3D


## Builds the body for `subject` (the dictionary FcPlayerVisual.resolve takes) with an animation phase offset so a team does not move in unison.
func setup(subject: Dictionary, phase_offset: float = 0.0) -> FcB1cCharacter:
	var visual := FcPlayerVisual.resolve(subject)
	identity = visual["identity"]
	uniform = visual["uniform"]
	jersey_number = int(uniform["number"])
	var body: Dictionary = visual.get("body_in", {})
	var height_cm := float(body.get("height_cm", DEFAULT_HEIGHT_CM))
	var weight_kg := float(body.get("weight_kg", DEFAULT_WEIGHT_KG))
	height_feet = height_cm / 30.48
	# width follows the weight for the height (about 0.45 kg per cm is "average"), widened a little more by the build class (0 slim, 2 heavy)
	width_scale = clampf(weight_kg / (height_cm * 0.48), 0.78, 1.3) * (0.95 + 0.05 * float(identity["build"]))
	_phase_offset = phase_offset
	_build()
	return self


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


func _part(parent: Node3D, mesh: Mesh, color: Color, offset: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _mat(color)
	node.position = offset
	parent.add_child(node)
	_meshes.append(node)
	return node


func _joint(parent: Node3D, name: String, at: Vector3) -> Node3D:
	var joint := Node3D.new()
	joint.name = name
	joint.position = at
	parent.add_child(joint)
	_joints[name] = joint
	return joint


func _capsule(radius: float, length: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = maxf(length, radius * 2.0)
	m.radial_segments = 10
	m.rings = 3
	return m


func _build() -> void:
	var h := height_feet
	var w := width_scale
	var skin: Color = identity["skin_color"]
	var primary: Color = uniform["primary"]
	var secondary: Color = uniform["secondary"]
	var hip_y := 0.53 * h
	var shoulder_y := 0.82 * h
	var pelvis := _joint(self, "pelvis", Vector3(0.0, hip_y, 0.0))
	var torso := _joint(pelvis, "torso", Vector3.ZERO)
	_part(pelvis, BoxMesh.new(), primary, Vector3.ZERO).scale = Vector3(0.24 * h * w, 0.11 * h, 0.14 * h * w)        # shorts
	_part(pelvis, BoxMesh.new(), secondary, Vector3(0.0, 0.052 * h, 0.0)).scale = Vector3(0.245 * h * w, 0.012 * h, 0.145 * h * w)   # waistband trim
	var chest := _part(torso, _capsule(0.1 * h * w, 0.3 * h), primary, Vector3(0.0, (shoulder_y - hip_y) * 0.5, 0.0))
	chest.scale = Vector3(1.0, 1.0, 0.7)
	var head_joint := _joint(torso, "head", Vector3(0.0, shoulder_y - hip_y + 0.03 * h, 0.0))
	var head_radius := 0.065 * h
	var head_scale: Dictionary = identity.get("proportions", {})
	var head := _part(head_joint, SphereMesh.new(), skin, Vector3(0.0, head_radius, 0.0))
	(head.mesh as SphereMesh).radius = head_radius
	(head.mesh as SphereMesh).height = head_radius * 2.0
	head.scale = Vector3(float(head_scale.get("face_w", 84)) / 84.0, 1.08, 0.95)
	_hair(head_joint, head_radius)
	_facial_hair(head_joint, head_radius)
	# arms: skin upper arm (a sleeveless jersey) and forearm, a small hand
	for side in [-1, 1]:
		var shoulder_name := "l_shoulder" if side < 0 else "r_shoulder"
		var elbow_name := "l_elbow" if side < 0 else "r_elbow"
		var shoulder := _joint(torso, shoulder_name, Vector3(side * 0.13 * h * w, shoulder_y - hip_y - 0.02 * h, 0.0))
		_part(shoulder, _capsule(0.035 * h * w, 0.17 * h), skin, Vector3(0.0, -0.085 * h, 0.0))
		var elbow := _joint(shoulder, elbow_name, Vector3(0.0, -0.17 * h, 0.0))
		_part(elbow, _capsule(0.03 * h * w, 0.16 * h), skin, Vector3(0.0, -0.08 * h, 0.0))
		var hand := _joint(elbow, "%s_hand" % ("l" if side < 0 else "r"), Vector3(0.0, -0.17 * h, 0.0))
		_part(hand, SphereMesh.new(), skin, Vector3.ZERO).scale = Vector3(0.05 * h, 0.05 * h, 0.05 * h)
		if side > 0:
			_hand = hand
	# legs: thigh and shin, shoe
	for side in [-1, 1]:
		var hip := _joint(pelvis, "l_hip" if side < 0 else "r_hip", Vector3(side * 0.055 * h * w, -0.04 * h, 0.0))
		_part(hip, _capsule(0.045 * h * w, 0.25 * h), primary, Vector3(0.0, -0.125 * h, 0.0))
		var knee := _joint(hip, "l_knee" if side < 0 else "r_knee", Vector3(0.0, -0.25 * h, 0.0))
		_part(knee, _capsule(0.036 * h * w, 0.24 * h), skin, Vector3(0.0, -0.12 * h, 0.0))
		_part(knee, BoxMesh.new(), secondary, Vector3(0.0, -0.245 * h, 0.03 * h)).scale = Vector3(0.07 * h, 0.035 * h, 0.14 * h)   # shoe
	# the number, big on the back and small on the front (3D text: legible at broadcast distance is the question)
	_back_number = _label(str(jersey_number), secondary, Vector3(0.0, (shoulder_y - hip_y) * 0.55, -0.075 * h), 180.0, 0.2 * h)
	torso.add_child(_back_number)
	_front_number = _label(str(jersey_number), secondary, Vector3(0.0, (shoulder_y - hip_y) * 0.6, 0.075 * h), 0.0, 0.1 * h)
	torso.add_child(_front_number)
	_apply_pose(FcB1cPose.pose_for("idle", _phase_offset))


func _label(text: String, color: Color, at: Vector3, yaw_degrees: float, size_feet: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 1)
	l.outline_size = 6
	l.font_size = 64
	l.pixel_size = size_feet / 64.0
	l.position = at
	l.rotation_degrees = Vector3(0.0, yaw_degrees, 0.0)
	l.double_sided = false
	l.shaded = false
	return l


func _hair(head_joint: Node3D, r: float) -> void:
	var color: Color = identity["hair_color"]
	var style := str(identity["hair"])
	var top := Vector3(0.0, r * 1.45, 0.0)
	match style:
		"bald":
			pass
		"short", "fade":
			_part(head_joint, SphereMesh.new(), color, top + Vector3(0.0, -r * 0.2, 0.0)).scale = Vector3(r * 2.05, r * (0.9 if style == "short" else 0.6), r * 2.05)
		"afro":
			_part(head_joint, SphereMesh.new(), color, top + Vector3(0.0, 0.0, 0.0)).scale = Vector3(r * 2.9, r * 2.5, r * 2.9)
		"braids", "locs", "long":
			_part(head_joint, SphereMesh.new(), color, top + Vector3(0.0, -r * 0.2, 0.0)).scale = Vector3(r * 2.1, r * 0.9, r * 2.1)
			var strands := 6 if style != "long" else 1
			for k in strands:
				var angle := TAU * k / strands
				var drop := _part(head_joint, _capsule(r * 0.12, r * (2.2 if style == "locs" else 1.5)), color, Vector3(cos(angle) * r * 0.85, r * 0.55, sin(angle) * r * 0.85 - (r * 0.2 if style == "long" else 0.0)))
				if style == "long":
					drop.scale = Vector3(r * 6.0, 1.4, 1.0)
					drop.position = Vector3(0.0, r * 0.3, -r * 0.8)
		"curly":
			for k in 7:
				var angle := TAU * k / 7.0
				_part(head_joint, SphereMesh.new(), color, Vector3(cos(angle) * r * 0.7, r * 1.55, sin(angle) * r * 0.7)).scale = Vector3(r * 0.9, r * 0.9, r * 0.9)
			_part(head_joint, SphereMesh.new(), color, top).scale = Vector3(r * 1.4, r * 0.9, r * 1.4)


func _facial_hair(head_joint: Node3D, r: float) -> void:
	var color: Color = (identity["hair_color"] as Color).darkened(0.1)
	match str(identity["facial_hair"]):
		"stubble":
			_part(head_joint, SphereMesh.new(), (identity["skin_color"] as Color).darkened(0.25), Vector3(0.0, r * 0.55, r * 0.08)).scale = Vector3(r * 1.9, r * 0.9, r * 1.85)
		"goatee":
			_part(head_joint, SphereMesh.new(), color, Vector3(0.0, r * 0.3, r * 0.85)).scale = Vector3(r * 0.5, r * 0.5, r * 0.4)
		"beard":
			_part(head_joint, SphereMesh.new(), color, Vector3(0.0, r * 0.55, r * 0.1)).scale = Vector3(r * 2.0, r * 1.1, r * 1.95)


# --- animation ----------------------------------------------------------------------------------------------------------------

## Switches to `new_state`, cross-fading from whatever pose the body is in now over BLEND_SECONDS (0 = at once).
func set_state(new_state: String, blend_seconds: float = BLEND_SECONDS) -> void:
	if new_state == state or not FcB1cPose.STATES.has(new_state):
		return
	_from_pose = _current_pose()
	state = new_state
	_blend = 0.0 if blend_seconds > 0.0 else 1.0
	_blend_seconds = maxf(blend_seconds, 0.0001)


var _blend_seconds: float = BLEND_SECONDS


func _phase() -> float:
	return fmod(_time / float(FcB1cPose.CYCLE[state]) + _phase_offset, 1.0)


func _current_pose() -> Dictionary:
	var target := FcB1cPose.pose_for(state, _phase())
	return FcB1cPose.blend(_from_pose, target, _blend) if _blend < 1.0 else target


## One step of time: moves the cross-fade and applies the pose to the joints.
func advance(delta: float) -> void:
	_time += delta
	if _blend < 1.0:
		_blend = minf(1.0, _blend + delta / _blend_seconds)
	_apply_pose(_current_pose())


func _apply_pose(pose: Dictionary) -> void:
	for name in FcB1cPose.JOINTS:
		(_joints[name] as Node3D).rotation = pose["joints"][name]
	var root: Vector3 = pose["root"]
	(_joints["pelvis"] as Node3D).position = Vector3(root.x * height_feet, 0.53 * height_feet + root.y * height_feet, 0.0)


func _process(delta: float) -> void:
	advance(delta)


func current_pose() -> Dictionary:
	return _current_pose()


## Where the right hand is in the world (a ball can be held or bounced from there).
func hand_position() -> Vector3:
	return _hand.global_position if _hand != null and _hand.is_inside_tree() else global_position


func part_count() -> int:
	return _meshes.size()


func joint_names() -> Array:
	return _joints.keys()
