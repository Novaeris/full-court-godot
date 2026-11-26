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
## True for a V2 player (MakeHuman base, D-075): morphs baked once from the identity, V2 materials.
var v2: bool = false
## The morph weights this V2 player was baked with (FcPlayerMorphs.weights).
var morph_weights: Dictionary = {}
## V2: how much longer than the model the arms are (from the archetype wingspan: guards about 1.0, centres a few percent more). 1 elsewhere.
var arm_scale: float = 1.0
## V2 levels of detail (FcPlayerLod): automatic LOD chains on the big meshes and distance ranges on the small parts. Tests may switch it off.
static var v2_lods: bool = true
## When true, V2 morphs are not baked in setup(): the caller bakes many characters together with FcPlayerLod.bake_characters (parallel, much faster).
static var defer_v2_bake: bool = false
## Meshes waiting for that bake: [MeshInstance3D, cache key, mesh name].
var pending_bake: Array = []
## The V2 part meshes this player wears (FcPlayerMorphs.parts).
var v2_parts: Array[String] = []
var _key: String = ""
var part_problems: Array[String] = []
var _spine: Array[int] = []           # V2: the x_spine_02 and x_spine_03 bones (empty for other bodies)
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
	uniform["attire"] = str(subject.get("attire", "playing"))
	uniform["kit"] = str(subject.get("kit", "home"))   # V2 uniforms: "home" (team colour), "away" (light, team-colour trim), "alternate" (dark)   # "playing", "referee" or "suit" (a coach): see FcBodyBuilder
	jersey_number = int(uniform["number"])
	_key = str(visual["key"])
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
	v2 = model_path == str(FcPlayerMorphs.data().get("library_model", "v2"))
	if v2:
		path = str(FcPlayerMorphs.data().get("model", ""))
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
	var across := 1.0 if v2 else 0.9 + 0.28 * bulk   # a heavier player is a little wider (V2 bodies get their mass from morphs instead)
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
	if skeleton.find_bone("x_spine_02") >= 0 and skeleton.find_bone("x_spine_03") >= 0:
		_spine = [skeleton.find_bone("x_spine_02"), skeleton.find_bone("x_spine_03")]
	if library_mode:
		part_problems = FcPlayerAssetLibrary.attach_parts(skeleton, asset_spec)
		_scale_head(float(asset_spec["width_scale"]))
	if v2:
		_dress_v2()
		_scale_arms()
	else:
		_dress_imported(library_mode)
	if str(uniform["attire"]) == "playing" and not ((library_mode or v2) and FcJerseyGraphics.available()):
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


## Dresses a V2 player: sets every fcb_ and fcf_ morph from the identity (FcPlayerMorphs), bakes the mix ONCE into a plain skinned mesh (no per-frame
## morph cost), then gives each surface its shared V2 material and shows the brow style of the identity.
func _dress_v2() -> void:
	morph_weights = FcPlayerMorphs.weights(identity, archetype, _key)
	var hair: Color = identity["hair_color"]
	var primary: Color = uniform["primary"]
	var secondary: Color = uniform["secondary"]
	match str(uniform.get("kit", "home")):
		"away":   # the light kit: the jersey takes the light colour, trim and numbers the team colour
			var team := primary
			primary = secondary if secondary.get_luminance() > 0.6 else Color.WHITE.darkened(0.04)
			secondary = team
		"alternate":
			primary = primary.darkened(0.45)
	var shorts := primary
	var socks := Color.WHITE
	if str(uniform["attire"]) != "playing":
		shorts = primary.darkened(0.3)
		socks = shorts
	var shoe: Color = [Color.WHITE, Color.BLACK.lightened(0.1), secondary, primary.lightened(0.25)][clampi(int(archetype["shoe"]), 0, 3)]
	# the parts this player wears (hair, facial hair, headband, equipment) join the skeleton BEFORE the bake, so they get the same face and body
	v2_parts = FcPlayerMorphs.parts(identity, _key)
	var packed := FcPlayerAssetLibrary.scene(str(FcPlayerMorphs.data().get("parts", "")))
	if packed != null and not v2_parts.is_empty():
		var instance := packed.instantiate()
		for part in v2_parts:
			var src := instance.find_child(part, true, false) as MeshInstance3D
			if src == null:
				part_problems.append("V2 part %s is missing" % part)
				continue
			var copy := src.duplicate() as MeshInstance3D
			skeleton.add_child(copy)
			copy.skeleton = NodePath("..")
		instance.free()
	var brow := FcPlayerMorphs.brow(identity, _key)
	for node in skeleton.get_children():
		if not (node is MeshInstance3D):
			continue
		var mi := node as MeshInstance3D
		var mesh_name := str(mi.name)
		if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).get_blend_shape_count() > 0:
			var am := mi.mesh as ArrayMesh
			for b in am.get_blend_shape_count():
				mi.set_blend_shape_value(b, float(morph_weights.get(str(am.get_blend_shape_name(b)), 0.0)))
			var cache_key := "%s|%s|%d" % [_key, mesh_name, hash(morph_weights)]
			if FcPlayerLod.has_cached(cache_key):
				mi.mesh = FcPlayerLod.cached_mesh(cache_key)
			elif defer_v2_bake:
				pending_bake.append([mi, cache_key, mesh_name])   # FcPlayerLod.bake_characters bakes many players at once, in parallel
			else:
				var baked := mi.bake_mesh_from_current_blend_shape_mix()
				if baked != null:
					mi.mesh = FcPlayerLod.cached(cache_key, baked, mesh_name) if v2_lods else baked
		FcPlayerLod.apply_ranges(mi, mesh_name)
		var base := mesh_name.get_slice("__", 0)
		if base == "skin":
			mi.material_override = FcPlayerV2Materials.skin(identity["skin_color"])
			if body_mesh == null:
				body_mesh = mi
		elif base == "eyes":
			mi.material_override = FcPlayerV2Materials.eyes(FcPlayerMorphs.eye_color(identity, _key))
		elif base == "lashes":
			mi.material_override = FcPlayerV2Materials.card("lashes", "lashes.png", hair.darkened(0.5))
		elif base.begins_with("brow_"):
			mi.visible = base == brow
			mi.material_override = FcPlayerV2Materials.card("brows", base + ".png", hair.lightened(0.15))
		elif base.begins_with("hair_") or base.begins_with("facial_"):
			mi.material_override = FcPlayerV2Materials.hair(hair, false) if base.begins_with("hair_") else FcPlayerV2Materials.hair(hair.darkened(0.05), true)
		elif base == "jersey":
			var number := jersey_number if str(uniform["attire"]) == "playing" else 0
			if FcJerseyGraphics.available():
				mi.material_override = FcJerseyGraphics.jersey_material(self, primary, number, _surname, str(uniform["abbreviation"]), secondary, primary.darkened(0.55), _panel(primary, secondary, 0.05))
			else:
				mi.material_override = FcJerseyGraphics.cloth_material(primary, _panel(primary, secondary, 0.05))
		elif base == "shorts":
			mi.material_override = FcJerseyGraphics.cloth_material(shorts, _panel(shorts, secondary, 0.045))
		elif base == "socks":
			mi.material_override = FcJerseyGraphics.cloth_material(socks)
		elif base == "shoes":
			# the shoe colour of the player, with the other team colour (or white on a dark shoe) as the accent
			var accent: Color = primary if shoe.get_luminance() > 0.5 and absf(shoe.get_luminance() - primary.get_luminance()) > 0.15 else (secondary if shoe != secondary else Color.WHITE)
			mi.material_override = FcPlayerV2Materials.shoe(shoe, accent)
		elif base in ["trim", "sole"] or base.begins_with("equip_") or base.begins_with("acc_"):
			var c: Color = {"trim": secondary, "shoes": shoe, "sole": Color.WHITE}.get(base, secondary if base != "equip_laces" else Color.WHITE)
			mi.material_override = FcPlayerAssetLibrary.shared_material(base.get_slice("_", 0), c, 0.68 if base == "shoes" else 0.8)   # synthetic upper, matte rubber


## Wingspan changes the arms, not the whole body: the upper arm bones are lengthened along their own axis (the forearm and hand follow), by the
## archetype wingspan relative to the reference build (1.03).
func _scale_arms() -> void:
	arm_scale = clampf(float(archetype.get("wingspan", 1.03)) / 1.03, 0.95, 1.06)
	for side in ["l", "r"]:
		var idx: int = _bone[side + "_shoulder"]
		var child: int = _bone[side + "_elbow"]
		var along := (skeleton.get_bone_rest(child).origin).normalized()   # the bone axis in its own frame
		var s := Vector3(lerpf(1.0, arm_scale, absf(along.x)), lerpf(1.0, arm_scale, absf(along.y)), lerpf(1.0, arm_scale, absf(along.z)))
		skeleton.set_bone_pose_scale(idx, s)


## The side panel of a V2 uniform piece: a darker band of the cloth colour edged by piping in the trim colour.
func _panel(cloth: Color, trim: Color, width: float) -> Dictionary:
	return {"color": cloth.darkened(0.32), "piping": trim, "width": width}


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
		var q := Basis.from_euler(pose["joints"][name]).get_rotation_quaternion()
		if name == "torso" and not _spine.is_empty():
			# a V2 spine has three joints: the torso bend is shared (lower back 45%, mid 30%, upper 25%) so the back curves instead of folding at one point
			skeleton.set_bone_pose_rotation(idx, _local_rotation(idx, Quaternion.IDENTITY.slerp(q, 0.45)))
			skeleton.set_bone_pose_rotation(_spine[0], _local_rotation(_spine[0], Quaternion.IDENTITY.slerp(q, 0.30)))
			skeleton.set_bone_pose_rotation(_spine[1], _local_rotation(_spine[1], Quaternion.IDENTITY.slerp(q, 0.25)))
			continue
		skeleton.set_bone_pose_rotation(idx, _local_rotation(idx, q))
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
	# the arms hang from the upper spine on a V2 body (the torso bend is shared along the spine), from the torso otherwise
	var torso_idx: int = _spine[1] if not _spine.is_empty() else int(_bone["torso"])
	var frame_name := skeleton.get_bone_name(torso_idx)
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
		var upper: float = shoulder_at.distance_to(_rest_pos(side + "_elbow")) * arm_scale
		var lower: float = (_rest_pos(side + "_elbow") as Vector3).distance_to(_rest_pos(side + "_hand")) * arm_scale
		var start: Vector3 = shoulder_at - (_rest_pos(frame_name) as Vector3)
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
