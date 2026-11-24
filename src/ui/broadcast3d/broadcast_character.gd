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

## A GLB player model to wear instead of the generated body (res:// path of a file in assets/players, set from subject["model"]); empty = generated.
var model_path: String = ""
## True when the body is an imported model (Blender, GLB) driven through the retarget layer below.
var imported: bool = false
var model_problems: Array[String] = []   # why a requested model was refused (the generated body is then used)
## With model = FcPlayerAssetLibrary.library_model(): the names of the pieces chosen for this player, and any part that could not be attached.
var asset_spec: Dictionary = {}
var _surname: String = ""
var part_problems: Array[String] = []
var _finger_bones: Dictionary = {}   # extension bone name -> index (empty for a model without fingers)
var _finger_q: Dictionary = {}       # bone name -> the rotation it holds now (fingers ease toward their pose)
var _finger_rate: float = 1.0

var _bone: Dictionary = {}       # joint name -> bone index
var _hs: float = 6.5             # the body height in SKELETON units (feet for the generated body, metres for an imported one)
var _k: float = 1.0              # skeleton units per foot, for the few lengths the code states in feet (the ball radius, the number sizes)
var _rest_rot: Dictionary = {}   # bone index -> its local rest rotation (Quaternion) in an imported rig
var _parent_rest: Dictionary = {}   # bone index -> the GLOBAL rest rotation of its parent in an imported rig
var _rest_global: Dictionary = {}   # bone name -> global rest origin (skeleton units), imported rigs
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
	uniform["attire"] = str(subject.get("attire", "playing"))   # "playing", "referee" or "suit" (a coach): see FcBodyBuilder
	jersey_number = int(uniform["number"])
	_surname = FcJerseyGraphics.surname_of(str(subject.get("name", "")))
	archetype = FcBodyArchetype.make(visual)
	if str(uniform["attire"]) != "playing":
		archetype["shoe"] = 1   # an official or a coach wears dark shoes
	height_feet = float(archetype["height_feet"])
	width_scale = float(archetype["width_scale"])
	_phase_offset = phase_offset
	model_path = str(subject.get("model", ""))
	_build()
	return self


func _build() -> void:
	if model_path != "":
		if _build_imported():
			return
	_hs = height_feet
	_k = 1.0
	builder = FcBodyBuilder.new()
	var built := builder.build(archetype, identity, uniform)
	skeleton = built["skeleton"]
	body_mesh = built["mesh_instance"]
	add_child(skeleton)
	_bone = built["bones"]
	_hand_bone = int(_bone["r_hand"])
	_pelvis_bone = int(_bone["pelvis"])
	if str(uniform["attire"]) == "playing":
		_attach_numbers()   # only players wear a number
	_apply_pose(FcBroadcastPose.pose_for("idle", _phase_offset))


## Wears the GLB at `model_path` instead of the generated body. The model must pass FcPlayerModelValidator; if it does not (or cannot be loaded) the
## reasons are kept in `model_problems`, nothing is changed and the generated body is built, so a bad model can never break a game.
## The rig is driven by the SAME FcBroadcastPose maths through a retarget layer: the pose rotations assume a rest pose with every bone axis aligned to the
## world, and an imported bone has its own rest rotation R (Blender bones point along their own axis), so the local rotation given to a bone is
## (G^-1 * q * G) * R where q is the pose rotation and G the global rest rotation of its parent: the world-aligned rotation, conjugated into the parent
## frame and applied on top of the rest of the bone. For a rig whose rest rotations are all identity this is exactly the generated body behaviour.
func _build_imported() -> bool:
	var path := model_path
	var library_mode := model_path == FcPlayerAssetLibrary.library_model()
	if library_mode:
		asset_spec = FcPlayerAssetLibrary.spec(identity, archetype)
		path = str(asset_spec["body_path"])
	model_problems = FcPlayerAssetLibrary.validated(path)
	if not model_problems.is_empty():
		return false
	var root := (load(path) as PackedScene).instantiate() as Node3D
	var found := root.find_children("*", "Skeleton3D", true, false)
	skeleton = found[0] as Skeleton3D
	var armature := root.find_child("Armature", true, false)
	var extras: Dictionary = armature.get_meta("extras", {}) if armature != null and armature.has_meta("extras") else {}
	var model_height := float(extras.get("fc_height_m", FcPlayerModelValidator.standard()["height_m"]))
	var bulk := float(archetype["bulk"])
	var across := 0.9 + 0.28 * bulk   # a heavier player is a little wider; the standard model is at bulk 0.36, so about 1.0 there
	_hs = model_height
	var scale := height_feet / model_height
	_k = 1.0 / scale
	root.scale = Vector3(scale * across, scale, scale * across)
	add_child(root)
	imported = true
	for name in FcBroadcastPose.JOINTS:
		_bone[name] = skeleton.find_bone(name)
	_hand_bone = int(_bone["r_hand"])
	_pelvis_bone = int(_bone["pelvis"])
	var global_rot: Array = []
	var global_pos: Array = []
	for i in skeleton.get_bone_count():
		var local := skeleton.get_bone_rest(i)
		var parent := skeleton.get_bone_parent(i)
		var local_rot := local.basis.get_rotation_quaternion()
		global_rot.append(local_rot if parent < 0 else (global_rot[parent] as Quaternion) * local_rot)
		global_pos.append(local.origin if parent < 0 else (global_pos[parent] as Vector3) + (global_rot[parent] as Quaternion) * local.origin)
		_rest_rot[i] = local_rot
		_parent_rest[i] = (global_rot[parent] as Quaternion) if parent >= 0 else Quaternion.IDENTITY
		_rest_global[skeleton.get_bone_name(i)] = global_pos[i]
		if skeleton.get_bone_name(i).begins_with("x_"):
			_finger_bones[skeleton.get_bone_name(i)] = i
	if library_mode:
		part_problems = FcPlayerAssetLibrary.attach_parts(skeleton, asset_spec)
		_scale_head(float(asset_spec["width_scale"]))
	_dress_imported(library_mode)
	if str(uniform["attire"]) == "playing" and not (library_mode and FcJerseyGraphics.available()):
		_attach_numbers()   # a library jersey carries its number as a texture; Label3D numbers are the fallback (no renderer, or a plain model)
	_apply_pose(FcBroadcastPose.pose_for("idle", _phase_offset))
	return true


## Dresses the imported model from the identity: recolours every surface by its name (skin and face parts, hair, facial hair, brow, lips, jersey, shorts,
## socks, shoes, trim, headband) with materials SHARED between players of the same colours, shows the hair of the style (or the default hair of a plain
## model), and hides the model default eyes and hair when the library attached its own. The eyes and nostrils keep their own material (vertex colours).
func _dress_imported(library_mode: bool = false) -> void:
	var tints: Dictionary = FcPlayerAssetLibrary.data().get("tints", {})
	var skin: Color = identity["skin_color"]
	var hair: Color = identity["hair_color"]
	var primary: Color = uniform["primary"]
	var secondary: Color = uniform["secondary"]
	var shoe: Color
	match int(archetype["shoe"]):
		0: shoe = Color.WHITE
		1: shoe = Color.BLACK.lightened(0.1)
		2: shoe = secondary
		_: shoe = primary.lightened(0.25)
	var shorts := primary
	var socks := Color.WHITE
	if str(uniform["attire"]) != "playing":
		shorts = primary.darkened(0.3)
		socks = shorts
	var colors := {
		"skin": [skin, 0.55], "jersey": [primary, 0.8], "shorts": [shorts, 0.8], "socks": [socks, 0.85], "shoes": [shoe, 0.5], "sole": [Color.WHITE, 0.6],
		"trim": [secondary, 0.7], "accessory": [secondary, 0.8], "hair": [hair, 0.8],
		"lips": [skin.lerp(Color.html(str(tints.get("lips", "#8E3B3B"))), float(tints.get("lips_mix", 0.42))), 0.5],
		"stubble": [hair.lerp(skin, float(tints.get("stubble_mix", 0.62))), 0.9],
		"brow": [hair.darkened(float(tints.get("brow_darken", 0.12))) if str(identity["hair"]) != "bald" else skin.darkened(0.55), 0.8],
	}
	var style := str(identity["hair"])
	var default_hair := "" if style == "bald" else ("hair_afro" if style == "afro" else "hair_short")
	for node in skeleton.get_children():
		if not (node is MeshInstance3D):
			continue
		var mesh := node as MeshInstance3D
		var mesh_name := str(mesh.name)
		if library_mode:
			if mesh_name == "features" or mesh_name == "hair_short":
				mesh.visible = false   # the library attached its own eyes and hair
				continue
		elif mesh_name.begins_with("hair_"):
			mesh.visible = mesh_name == default_hair
		var kind := ""
		if mesh_name == "skin" or mesh_name.begins_with("skin_head_") or mesh_name.begins_with("nose_"):
			kind = "skin"
		elif mesh_name == "facial_stubble" or mesh_name.begins_with("facial_stubble_"):
			kind = "stubble"
		elif mesh_name.begins_with("hair_") or mesh_name.begins_with("facial_"):
			kind = "hair"
		elif mesh_name.begins_with("brow_"):
			kind = "brow"
		elif mesh_name.begins_with("lips_"):
			kind = "lips"
		elif mesh_name.begins_with("acc_"):
			kind = "accessory"
		elif colors.has(mesh_name):
			kind = mesh_name
		elif mesh_name == "features" or mesh_name.begins_with("eyes_") or mesh_name.begins_with("nostrils_"):
			var own := mesh.mesh.surface_get_material(0) as BaseMaterial3D if mesh.mesh != null else null
			if own != null:
				own.vertex_color_use_as_albedo = true   # the eyes are painted with vertex colours (sclera, iris, pupil)
		if library_mode and FcJerseyGraphics.available() and (kind == "jersey" or kind == "shorts"):
			if kind == "jersey":
				var number := jersey_number if str(uniform["attire"]) == "playing" else 0
				mesh.material_override = FcJerseyGraphics.jersey_material(self, primary, number, _surname, str(uniform["abbreviation"]), secondary, primary.darkened(0.55))
			else:
				mesh.material_override = FcJerseyGraphics.cloth_material(shorts)
		elif kind != "":
			var spec_colour: Array = colors[kind]
			mesh.material_override = FcPlayerAssetLibrary.shared_material(kind, spec_colour[0], float(spec_colour[1]))
		if body_mesh == null and mesh_name == "skin":
			body_mesh = mesh


## Widens or narrows the head by the face width of the identity: the head bone is scaled across the body, in the bone own axes.
func _scale_head(width: float) -> void:
	var idx: int = _bone["head"]
	var global_rest: Quaternion = (_parent_rest[idx] as Quaternion) * (_rest_rot[idx] as Quaternion)
	var across := global_rest.inverse() * Vector3.RIGHT
	skeleton.set_bone_pose_scale(idx, Vector3(lerpf(1.0, width, absf(across.x)), lerpf(1.0, width, absf(across.y)), lerpf(1.0, width, absf(across.z))))


## The global rest position of a bone in skeleton units (feet for the generated body, metres for an imported one).
func _rest_pos(name: String) -> Vector3:
	return _rest_global[name] if imported else builder.rest_origin(name)


## The local rotation to give a bone for the pose rotation `q` (the retarget layer; the generated body needs none).
func _local_rotation(index: int, q: Quaternion) -> Quaternion:
	if not imported:
		return q
	return FcRigRetarget.local_rotation(_parent_rest[index], _rest_rot[index], q)


## The number, big on the back and small on the front, riding on the torso bone (3D text: legible at broadcast distance is the question).
func _attach_numbers() -> void:
	var h := height_feet
	var torso := BoneAttachment3D.new()
	torso.name = "TorsoMount"
	torso.bone_name = "torso"
	skeleton.add_child(torso)
	var pelvis_y: float = (_rest_pos("pelvis") as Vector3).y
	var secondary: Color = uniform["secondary"]
	var hs := h * _k   # the same positions and sizes, in skeleton units
	var depth: float = float(archetype["chest_rz"]) * hs
	_back_number = _label(str(jersey_number), secondary, Vector3(0.0, 0.705 * hs - pelvis_y, -(depth + 0.012 * hs)), 180.0, 0.2 * hs)
	torso.add_child(_back_number)
	_front_number = _label(str(jersey_number), secondary, Vector3(0.0, 0.68 * hs - pelvis_y, depth + 0.012 * hs), 0.0, 0.1 * hs)
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
	_finger_rate = clampf(delta * 14.0, 0.0, 1.0)
	if _blend < 1.0:
		_blend = minf(1.0, _blend + delta / _blend_seconds)
	_apply_pose(_current_pose())


## Shows `new_state` at `phase` at once, with no blend (for pictures and tests).
func pose_at(new_state: String, phase: float) -> void:
	state = new_state
	_blend = 1.0
	_finger_rate = 1.0
	_time = (phase - _phase_offset) * float(FcBroadcastPose.CYCLE[new_state])
	_apply_pose(FcBroadcastPose.pose_for(new_state, phase))


func _apply_pose(pose: Dictionary) -> void:
	for name in FcBroadcastPose.JOINTS:
		var idx: int = _bone.get(name, -1)
		if idx < 0:
			continue
		skeleton.set_bone_pose_rotation(idx, _local_rotation(idx, Basis.from_euler(pose["joints"][name]).get_rotation_quaternion()))
	var root: Vector3 = pose["root"]
	var rest: Vector3 = _rest_pos("pelvis")
	var pelvis_y := rest.y + root.y * _hs
	skeleton.set_bone_pose_position(_pelvis_bone, Vector3(root.x * _hs, pelvis_y, 0.0))
	# ground contact: unless airborne, the lower foot's sole rests on the floor whatever the pose does to the legs (no floating, no sinking)
	var air := float(pose["air"])
	if air < 0.999:
		var globals := _forward_kinematics()
		var lowest := minf((globals[int(_bone["l_foot"])] as Transform3D).origin.y, (globals[int(_bone["r_foot"])] as Transform3D).origin.y)
		var ankle: float = (_rest_pos("l_foot") as Vector3).y
		pelvis_y += (ankle - lowest) * (1.0 - air)
		skeleton.set_bone_pose_position(_pelvis_bone, Vector3(root.x * _hs, pelvis_y, 0.0))
	_grip = 0.0
	var grip := float(pose["grip"])
	if grip > 0.01:
		_apply_grip(pose, grip, pelvis_y - rest.y)
	if not _finger_bones.is_empty():
		_apply_fingers(grip)


## The fingers hold the hand pose of the state, closing on the ball as the grip rises (FcHandPoses); they ease toward it so a change of state does not pop.
func _apply_fingers(grip: float) -> void:
	for side in ["l", "r"]:
		var targets := FcHandPoses.finger_rotations(state, side, grip)
		for bone_name in targets:
			var idx: int = _finger_bones.get(bone_name, -1)
			if idx < 0:
				continue
			var q := _local_rotation(idx, targets[bone_name])
			var now: Quaternion = _finger_q.get(bone_name, q)
			now = now.slerp(q, _finger_rate)
			_finger_q[bone_name] = now
			skeleton.set_bone_pose_rotation(idx, now)


## Both arms reach for the ball anchor of the pose (two-bone IK per arm) and blend from the canned arm pose by `grip`.
func _apply_grip(pose: Dictionary, grip: float, shift: float) -> void:
	var anchor: Vector3 = (pose["ball"] as Vector3) * _hs + Vector3(0.0, shift, 0.0)
	_grip = grip
	_anchor_model = anchor
	var torso_idx: int = _bone["torso"]
	var torso_global: Transform3D = _forward_kinematics()[torso_idx]
	# the torso frame the pose maths use: its orientation without the rest rotation of an imported bone (the identity for the generated body)
	var rest_torso := (_parent_rest[torso_idx] as Quaternion) * (_rest_rot[torso_idx] as Quaternion) if imported else Quaternion.IDENTITY
	var ours := Transform3D(Basis(torso_global.basis.get_rotation_quaternion() * rest_torso.inverse()), torso_global.origin)
	var to_local := ours.affine_inverse()
	for side in ["l", "r"]:
		var sign := 1.0 if side == "l" else -1.0
		var sh: int = _bone[side + "_shoulder"]
		var el: int = _bone[side + "_elbow"]
		var shoulder_at: Vector3 = _rest_pos(side + "_shoulder")
		var upper: float = shoulder_at.distance_to(_rest_pos(side + "_elbow"))
		var lower: float = (_rest_pos(side + "_elbow") as Vector3).distance_to(_rest_pos(side + "_hand"))
		var start: Vector3 = shoulder_at - (_rest_pos("torso") as Vector3)
		var wrist := to_local * (anchor + Vector3(sign * BALL_RADIUS * 1.05, -0.12, -0.02) * _k)
		var solved := FcLimbIK.solve(start, upper, lower, wrist, Vector3(sign * 0.5, -0.7, -0.35))
		var posed_sh := _local_rotation(sh, Basis.from_euler(pose["joints"][side + "_shoulder"]).get_rotation_quaternion())
		var posed_el := _local_rotation(el, Basis.from_euler(pose["joints"][side + "_elbow"]).get_rotation_quaternion())
		var ik_sh := _local_rotation(sh, (solved["basis"] as Basis).get_rotation_quaternion())
		var ik_el := _local_rotation(el, Quaternion(Vector3.RIGHT, -float(solved["bend"])))
		skeleton.set_bone_pose_rotation(sh, posed_sh.slerp(ik_sh, grip))
		skeleton.set_bone_pose_rotation(el, posed_el.slerp(ik_el, grip))


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


## Where the current state is in its loop, 0 to 1 (the dribble bounce is timed from this).
func cycle_phase() -> float:
	return _phase()


func current_pose() -> Dictionary:
	return _current_pose()


## Where the right hand is in the world (a ball can be held or bounced from there): the middle of the palm.
func hand_position() -> Vector3:
	if skeleton == null or not skeleton.is_inside_tree():
		return global_position
	var bone: Transform3D = _forward_kinematics()[_hand_bone]
	# the palm lies a little way along the hand: straight down in the rest pose, whatever the axes of the bone are
	var hand_rest := (_parent_rest[_hand_bone] as Quaternion) * (_rest_rot[_hand_bone] as Quaternion) if imported else Quaternion.IDENTITY
	var palm := bone * (hand_rest.inverse() * Vector3(0.0, -0.03 * _hs, 0.0))
	return skeleton.global_transform * palm


## How many generated pieces the body has (lofts, ellipsoids, tubes): hair and facial hair add some.
func part_count() -> int:
	if imported:
		return skeleton.get_child_count()
	return builder.part_count() if builder != null else 0


func joint_names() -> Array:
	return _bone.keys()


## The number of triangles and vertices of the whole body (for the performance budget).
func triangle_count() -> int:
	if imported:
		var total := 0
		for node in skeleton.get_children():
			if node is MeshInstance3D and (node as MeshInstance3D).visible and (node as MeshInstance3D).mesh != null:
				for s in (node as MeshInstance3D).mesh.get_surface_count():
					total += ((node as MeshInstance3D).mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		return total
	return builder.triangle_total() if builder != null else 0
