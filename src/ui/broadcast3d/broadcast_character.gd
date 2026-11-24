class_name FcBroadcastCharacter
extends Node3D
## One basketball player in the 3D broadcast view, built ENTIRELY IN CODE from the identity data the game already has (FcPlayerVisual.resolve:
## skin tone, hair style and colour, facial hair, face proportions, build class, height, weight, position, team colours, jersey number), with no
## model or animation file. 3D overhaul M1: the body is a real Skeleton3D with one smooth skinned mesh (FcBodyBuilder) shaped by an FcBodyArchetype
## (height, mass, muscle, wingspan, shoulders, head, hands...), animated by FcBroadcastPose (pure maths) with cross-fades. Units are feet.
## The 2D portraits are NOT used (no depth): only the categorical identity data and colours drive the look, so Creator Studio and saves are unchanged.

const DEFAULT_HEIGHT_CM := 198.0
const DEFAULT_WEIGHT_KG := 95.0
const BLEND_SECONDS := 0.2

var identity: Dictionary = {}
var uniform: Dictionary = {}
var archetype: Dictionary = {}
var height_feet: float = 6.5
var width_scale: float = 1.0
var jersey_number: int = 0
var state: String = "idle"

var skeleton: Skeleton3D
var body_mesh: MeshInstance3D
var builder: FcBodyBuilder

var _bone: Dictionary = {}       # joint name -> bone index
var _from_pose: Dictionary = FcBroadcastPose.pose_for("idle", 0.0)
var _blend: float = 1.0
var _blend_seconds: float = BLEND_SECONDS
var _time: float = 0.0
var _phase_offset: float = 0.0
var _hand_bone: int = -1
var _pelvis_bone: int = -1
var _back_number: Label3D
var _front_number: Label3D


## Builds the body for `subject` (the dictionary FcPlayerVisual.resolve takes) with an animation phase offset so a team does not move in unison.
func setup(subject: Dictionary, phase_offset: float = 0.0) -> FcBroadcastCharacter:
	var visual := FcPlayerVisual.resolve(subject)
	identity = visual["identity"]
	uniform = visual["uniform"]
	jersey_number = int(uniform["number"])
	archetype = FcBodyArchetype.make(visual)
	height_feet = float(archetype["height_feet"])
	width_scale = float(archetype["width_scale"])
	_phase_offset = phase_offset
	_build()
	return self


func _build() -> void:
	builder = FcBodyBuilder.new()
	var built := builder.build(archetype, identity, uniform)
	skeleton = built["skeleton"]
	body_mesh = built["mesh_instance"]
	add_child(skeleton)
	_bone = built["bones"]
	_hand_bone = int(_bone["r_hand"])
	_pelvis_bone = int(_bone["pelvis"])
	_attach_numbers()
	_apply_pose(FcBroadcastPose.pose_for("idle", _phase_offset))


## The number, big on the back and small on the front, riding on the torso bone (3D text: legible at broadcast distance is the question).
func _attach_numbers() -> void:
	var h := height_feet
	var torso := BoneAttachment3D.new()
	torso.name = "TorsoMount"
	torso.bone_name = "torso"
	skeleton.add_child(torso)
	var pelvis_y: float = (builder.rest_origin("pelvis") as Vector3).y
	var secondary: Color = uniform["secondary"]
	var depth: float = float(archetype["chest_rz"]) * h
	_back_number = _label(str(jersey_number), secondary, Vector3(0.0, 0.705 * h - pelvis_y, -(depth + 0.012 * h)), 180.0, 0.2 * h)
	torso.add_child(_back_number)
	_front_number = _label(str(jersey_number), secondary, Vector3(0.0, 0.68 * h - pelvis_y, depth + 0.012 * h), 0.0, 0.1 * h)
	torso.add_child(_front_number)


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


# --- animation ----------------------------------------------------------------------------------------------------------------

## Switches to `new_state`, cross-fading from whatever pose the body is in now over BLEND_SECONDS (0 = at once).
func set_state(new_state: String, blend_seconds: float = BLEND_SECONDS) -> void:
	if new_state == state or not FcBroadcastPose.STATES.has(new_state):
		return
	_from_pose = _current_pose()
	state = new_state
	_blend = 0.0 if blend_seconds > 0.0 else 1.0
	_blend_seconds = maxf(blend_seconds, 0.0001)


func _phase() -> float:
	return fmod(_time / float(FcBroadcastPose.CYCLE[state]) + _phase_offset, 1.0)


func _current_pose() -> Dictionary:
	var target := FcBroadcastPose.pose_for(state, _phase())
	return FcBroadcastPose.blend(_from_pose, target, _blend) if _blend < 1.0 else target


## One step of time: moves the cross-fade and applies the pose to the bones.
func advance(delta: float) -> void:
	_time += delta
	if _blend < 1.0:
		_blend = minf(1.0, _blend + delta / _blend_seconds)
	_apply_pose(_current_pose())


func _apply_pose(pose: Dictionary) -> void:
	for name in FcBroadcastPose.JOINTS:
		var idx: int = _bone.get(name, -1)
		if idx < 0:
			continue
		skeleton.set_bone_pose_rotation(idx, Basis.from_euler(pose["joints"][name]).get_rotation_quaternion())
	var root: Vector3 = pose["root"]
	var rest: Vector3 = builder.rest_origin("pelvis")
	skeleton.set_bone_pose_position(_pelvis_bone, Vector3(root.x * height_feet, rest.y + root.y * height_feet, 0.0))


func _process(delta: float) -> void:
	advance(delta)


func current_pose() -> Dictionary:
	return _current_pose()


## Where the right hand is in the world (a ball can be held or bounced from there): the middle of the palm.
func hand_position() -> Vector3:
	if skeleton == null or not skeleton.is_inside_tree():
		return global_position
	var bone := skeleton.get_bone_global_pose(_hand_bone)
	var palm := bone * Vector3(0.0, -0.03 * height_feet, 0.0)
	return skeleton.global_transform * palm


## How many generated pieces the body has (lofts, ellipsoids, tubes): hair and facial hair add some.
func part_count() -> int:
	return builder.part_count() if builder != null else 0


func joint_names() -> Array:
	return _bone.keys()


## The number of triangles and vertices of the whole body (for the performance budget).
func triangle_count() -> int:
	return builder.triangle_total() if builder != null else 0
