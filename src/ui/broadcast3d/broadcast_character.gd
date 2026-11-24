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
## The radius of the ball in feet (a size 7 ball is 9.4 inches across).
const BALL_RADIUS := 0.39

var identity: Dictionary = {}
var uniform: Dictionary = {}
var archetype: Dictionary = {}
var height_feet: float = 6.5
var width_scale: float = 1.0
var jersey_number: int = 0
var state: String = "idle"
## Animation clock speed: 1 is the authored speed; a stride is slowed or sped so the feet match the ground speed.
var playback: float = 1.0

var skeleton: Skeleton3D
var body_mesh: MeshInstance3D
var builder: FcBodyBuilder

var _bone: Dictionary = {}       # joint name -> bone index
var _from_pose: Dictionary = FcBroadcastPose.pose_for("idle", 0.0)
var _blend: float = 1.0
var _blend_seconds: float = BLEND_SECONDS
var _grip: float = 0.0
var _anchor_model: Vector3 = Vector3.ZERO
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


## One step of time: moves the cross-fade and applies the pose to the bones. `playback` scales the animation clock so a stride can be matched
## to the speed the body really travels (feet do not slide).
func advance(delta: float) -> void:
	_time += delta * playback
	if _blend < 1.0:
		_blend = minf(1.0, _blend + delta / _blend_seconds)
	_apply_pose(_current_pose())


## Shows `new_state` at `phase` at once, with no blend (for pictures and tests).
func pose_at(new_state: String, phase: float) -> void:
	state = new_state
	_blend = 1.0
	_time = (phase - _phase_offset) * float(FcBroadcastPose.CYCLE[new_state])
	_apply_pose(FcBroadcastPose.pose_for(new_state, phase))


func _apply_pose(pose: Dictionary) -> void:
	for name in FcBroadcastPose.JOINTS:
		var idx: int = _bone.get(name, -1)
		if idx < 0:
			continue
		skeleton.set_bone_pose_rotation(idx, Basis.from_euler(pose["joints"][name]).get_rotation_quaternion())
	var root: Vector3 = pose["root"]
	var rest: Vector3 = builder.rest_origin("pelvis")
	var pelvis_y := rest.y + root.y * height_feet
	skeleton.set_bone_pose_position(_pelvis_bone, Vector3(root.x * height_feet, pelvis_y, 0.0))
	# ground contact: unless airborne, the lower foot's sole rests on the floor whatever the pose does to the legs (no floating, no sinking)
	var air := float(pose["air"])
	if air < 0.999:
		var globals := _forward_kinematics()
		var lowest := minf((globals[int(_bone["l_foot"])] as Transform3D).origin.y, (globals[int(_bone["r_foot"])] as Transform3D).origin.y)
		var ankle: float = (builder.rest_origin("l_foot") as Vector3).y
		pelvis_y += (ankle - lowest) * (1.0 - air)
		skeleton.set_bone_pose_position(_pelvis_bone, Vector3(root.x * height_feet, pelvis_y, 0.0))
	_grip = 0.0
	var grip := float(pose["grip"])
	if grip > 0.01:
		_apply_grip(pose, grip, pelvis_y - rest.y)


## Both arms reach for the ball anchor of the pose (two-bone IK per arm) and blend from the canned arm pose by `grip`.
func _apply_grip(pose: Dictionary, grip: float, shift: float) -> void:
	var anchor: Vector3 = (pose["ball"] as Vector3) * height_feet + Vector3(0.0, shift, 0.0)
	_grip = grip
	_anchor_model = anchor
	var torso_idx: int = _bone["torso"]
	var to_local := (_forward_kinematics()[torso_idx] as Transform3D).affine_inverse()
	for side in ["l", "r"]:
		var sign := 1.0 if side == "l" else -1.0
		var sh: int = _bone[side + "_shoulder"]
		var el: int = _bone[side + "_elbow"]
		var hd: int = _bone[side + "_hand"]
		var upper: float = skeleton.get_bone_rest(el).origin.length()
		var lower: float = skeleton.get_bone_rest(hd).origin.length()
		var start: Vector3 = skeleton.get_bone_rest(sh).origin
		var wrist := to_local * (anchor + Vector3(sign * BALL_RADIUS * 1.05, -0.12, -0.02))
		var solved := FcLimbIK.solve(start, upper, lower, wrist, Vector3(sign * 0.5, -0.7, -0.35))
		var posed_sh := Basis.from_euler(pose["joints"][side + "_shoulder"]).get_rotation_quaternion()
		var posed_el := Basis.from_euler(pose["joints"][side + "_elbow"]).get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(sh, posed_sh.slerp((solved["basis"] as Basis).get_rotation_quaternion(), grip))
		skeleton.set_bone_pose_rotation(el, posed_el.slerp(Quaternion(Vector3.RIGHT, -float(solved["bend"])), grip))


## The model-space transform of every bone from the current local poses. Skeleton3D only refreshes its own global poses on its own schedule, so
## ground contact and IK, which need the answer NOW, compute it here (16 bones, trivial).
func _forward_kinematics() -> Array:
	var out: Array = []
	for i in skeleton.get_bone_count():
		var local := skeleton.get_bone_pose(i)
		var parent := skeleton.get_bone_parent(i)
		out.append(local if parent < 0 else (out[parent] as Transform3D) * local)
	return out


## The ball anchor of the current pose in the world, and how strongly both hands hold it: {"active": bool, "position": Vector3, "grip": float}.
func ball_anchor() -> Dictionary:
	if _grip <= 0.05 or skeleton == null or not skeleton.is_inside_tree():
		return {"active": false, "position": Vector3.ZERO, "grip": 0.0}
	return {"active": true, "position": skeleton.global_transform * _anchor_model, "grip": _grip}


## Godot switches `_process` on again when a node enters the tree whatever set_process(false) said before, so "someone else advances me" is a flag:
## the broadcast view steps its characters itself (once, with the speed it chooses) and turns this off.
var auto_advance: bool = true


func _process(delta: float) -> void:
	if auto_advance:
		advance(delta)


func current_pose() -> Dictionary:
	return _current_pose()


## Where the right hand is in the world (a ball can be held or bounced from there): the middle of the palm.
func hand_position() -> Vector3:
	if skeleton == null or not skeleton.is_inside_tree():
		return global_position
	var bone: Transform3D = _forward_kinematics()[_hand_bone]
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
