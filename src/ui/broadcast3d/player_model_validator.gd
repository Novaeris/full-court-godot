class_name FcPlayerModelValidator
extends RefCounted
## Checks an imported player model (a GLB made in Blender, see docs/development/ASSET_PRODUCTION_PIPELINE.md) against the Full Court player rig standard in
## data/player_pipeline/rig_standard.json, and reports every problem in plain words (an empty list means the model is valid). It is the gate between
## "an artist exported a file" and "the game may use it": the character class refuses a model with problems, the project validator and CI run it over every
## model in assets/players, and the tests prove it catches each kind of mistake.
##
## What it checks: one skeleton; the 16 standard bones with the standard parents (extra bones are allowed only if their names start with "x_" and their
## parent exists); the rest pose (arms and legs hang, the left side is +X, head above neck above torso above pelvis, the soles on the floor); the declared
## height (armature extra fc_height_m) against the real height and the allowed range; the face toward +Z; the standard surfaces present with a skin and
## materials of the same name; at least one hair mesh named hair_<style>; the triangle budget; every vertex weighted and the weights summing to one.

const STANDARD_PATH := "res://data/player_pipeline/rig_standard.json"
const REQUIRED_SURFACES := ["skin", "features", "jersey", "shorts", "socks", "shoes", "sole"]
## Approved optional surfaces and the material each must carry (the game recolours materials by name). A mesh whose name matches no prefix here and is not a
## required surface is refused, so the vocabulary stays closed (M1, docs/development/PLAYER_VISUAL_SPEC.md).
const MATERIAL_BY_PREFIX := {
	"hair_": "hair", "facial_": "hair", "brow_": "hair", "skin_head_": "skin", "nose_": "skin", "nostrils_": "features", "eyes_": "features",
	"lips_": "lips", "acc_": "accessory",
}
const OPTIONAL_SURFACES := ["trim"]
## A swappable part file (assets/players/parts/*.glb) holds only head parts, hair, facial hair and accessories on the standard skeleton.
const PART_MAX_TRIANGLES := 6000
## Model standard 2 (V2 players, D-075): the same 16 standard bones, but a standard bone may hang under a chain of x_ bones that descends from its standard
## parent (MakeHuman spine and clavicles), meshes may carry morph targets named fcb_ (body) or fcf_ (face), and the surfaces below are allowed. A level of
## detail is the same surface name with a "__lod1" or "__lod2" suffix. Required: the body skin and the eyes.
const V2_REQUIRED := ["skin", "eyes"]
const V2_SURFACES := {
	"skin": "skin", "eyes": "eyes", "lashes": "lashes", "brow_": "brows", "hair_": "hair", "facial_": "hair", "jersey": "jersey", "shorts": "shorts",
	"socks": "socks", "shoes": "shoes", "sole": "sole", "trim": "trim", "equip_": "equipment", "acc_": "accessory",
}
const V2_MAX_TRIANGLES := {"": 60000, "__lod1": 20000, "__lod2": 8000}
const V2_PART_MAX_TRIANGLES := 16000

static var _standard: Dictionary = {}


## The rig standard (loaded once).
static func standard() -> Dictionary:
	if _standard.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STANDARD_PATH))
		_standard = parsed if parsed is Dictionary else {}
	return _standard


## Loads the model at `path` and validates it. Problems include "cannot be loaded" for a missing or broken file.
static func validate_path(path: String) -> Array[String]:
	var out: Array[String] = []
	if not ResourceLoader.exists(path):
		out.append("%s does not exist or has not been imported (run godot --import)" % path)
		return out
	var packed := load(path) as PackedScene
	if packed == null:
		out.append("%s cannot be loaded as a scene" % path)
		return out
	var root := packed.instantiate()
	if "/v2/parts/" in path:
		out.append_array(validate_v2_scene(root, false))
	elif "/parts/" in path:
		out.append_array(validate_part_scene(root))
	elif model_version(root) >= 2:
		out.append_array(validate_v2_scene(root))
	else:
		out.append_array(validate_scene(root))
	root.free()
	return out


## Every problem with an instantiated model (empty = valid).
static func validate_scene(root: Node) -> Array[String]:
	var out: Array[String] = []
	var std := standard()
	if std.is_empty():
		out.append("the rig standard file is missing or not valid JSON")
		return out
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() != 1:
		out.append("the model must contain exactly one skeleton (it has %d)" % skeletons.size())
		return out
	var sk := skeletons[0] as Skeleton3D
	out.append_array(_check_bones(sk, std))
	if not out.is_empty():
		return out   # the rest of the checks read bones by name
	out.append_array(_check_rest_pose(sk))
	out.append_array(_check_meshes(root, sk, std))
	return out


## The material name a mesh must carry ("" when the mesh name is not an approved surface).
static func material_for(mesh_name: String) -> String:
	if mesh_name in REQUIRED_SURFACES or mesh_name in OPTIONAL_SURFACES:
		return mesh_name
	for prefix in MATERIAL_BY_PREFIX:
		if mesh_name.begins_with(prefix):
			return MATERIAL_BY_PREFIX[prefix]
	return ""


## Every problem with an instantiated PART file (empty = valid): the standard skeleton, then each mesh named from the approved vocabulary, skinned, weighted
## and within the per-part triangle budget. A part file is not a player: it has no required surfaces and no height.
static func validate_part_scene(root: Node) -> Array[String]:
	var out: Array[String] = []
	var std := standard()
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() != 1:
		out.append("a part file must contain exactly one skeleton (it has %d)" % skeletons.size())
		return out
	var sk := skeletons[0] as Skeleton3D
	out.append_array(_check_bones(sk, std))
	if not out.is_empty():
		return out
	var count := 0
	for node in sk.get_children():
		if not (node is MeshInstance3D):
			continue
		count += 1
		var m := node as MeshInstance3D
		var name := str(m.name)
		var wanted := material_for(name)
		if wanted == "" or name in REQUIRED_SURFACES:
			out.append("part mesh '%s' is not an approved part name (hair_, facial_, brow_, skin_head_, nose_, nostrils_, eyes_, lips_, acc_)" % name)
			continue
		if m.mesh == null or m.mesh.get_surface_count() == 0:
			out.append("part %s has no geometry" % name)
			continue
		if m.skin == null:
			out.append("part %s is not skinned to the skeleton" % name)
		var material := m.mesh.surface_get_material(0)
		if material == null or material.resource_name != wanted:
			out.append("part %s must have a material named '%s'" % [name, wanted])
		var triangles := 0
		for surface in m.mesh.get_surface_count():
			var arrays := m.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			triangles += indices.size() / 3
			out.append_array(_check_weights(name, arrays, m))
		if triangles > PART_MAX_TRIANGLES:
			out.append("part %s has %d triangles (over the part budget of %d)" % [name, triangles, PART_MAX_TRIANGLES])
	if count == 0:
		out.append("the part file has no meshes")
	return out


## The model standard a scene declares (armature extra fc_model_version; 1 when absent).
static func model_version(root: Node) -> int:
	var armature := root.find_child("Armature", true, false)
	var extras: Dictionary = armature.get_meta("extras", {}) if armature != null and armature.has_meta("extras") else {}
	return int(extras.get("fc_model_version", 1))


## The material a V2 surface must carry, with any LOD suffix removed ("" when the name is not a V2 surface).
static func v2_material_for(mesh_name: String) -> String:
	var base := mesh_name.get_slice("__", 0)
	for key in V2_SURFACES:
		if base == key or (str(key).ends_with("_") and base.begins_with(key)):
			return V2_SURFACES[key]
	return ""


## Every problem with a V2 model (empty = valid): the standard bones (with the x_ chain rule), the rest pose, the declared height, the V2 surfaces and
## materials, morph target names, skinning, weights and the triangle budget of each level of detail.
static func validate_v2_scene(root: Node, whole_player: bool = true) -> Array[String]:
	var out: Array[String] = []
	var std := standard()
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() != 1:
		out.append("the model must contain exactly one skeleton (it has %d)" % skeletons.size())
		return out
	var sk := skeletons[0] as Skeleton3D
	out.append_array(_check_bones(sk, std, true))
	if not out.is_empty():
		return out
	out.append_array(_check_rest_pose(sk))
	var triangles := {}
	var names := {}
	for node in sk.get_children():
		if not (node is MeshInstance3D):
			continue
		var m := node as MeshInstance3D
		var name := str(m.name)
		names[name] = m
		var wanted := v2_material_for(name)
		if wanted == "":
			out.append("mesh '%s' is not a V2 surface name" % name)
			continue
		if m.mesh == null or m.mesh.get_surface_count() == 0:
			out.append("mesh %s has no geometry" % name)
			continue
		if m.skin == null:
			out.append("mesh %s is not skinned to the skeleton" % name)
		var material := m.mesh.surface_get_material(0)
		if material == null or material.resource_name != wanted:
			out.append("mesh %s must have a material named '%s'" % [name, wanted])
		var lod := ("__" + name.get_slice("__", 1) if "__" in name else "") if whole_player else name   # a part file: each part has its own budget
		for sidx in m.mesh.get_surface_count():
			var arrays := m.mesh.surface_get_arrays(sidx)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			triangles[lod] = int(triangles.get(lod, 0)) + indices.size() / 3
			out.append_array(_check_weights(name, arrays, m))
		if m.mesh is ArrayMesh:
			for b in (m.mesh as ArrayMesh).get_blend_shape_count():
				var shape := str((m.mesh as ArrayMesh).get_blend_shape_name(b))
				if not (shape.begins_with("fcb_") or shape.begins_with("fcf_")):
					out.append("mesh %s has a morph target '%s' (V2 morphs are named fcb_ or fcf_)" % [name, shape])
	for name in (V2_REQUIRED if whole_player else []):
		if not names.has(name):
			out.append("the V2 surface mesh '%s' is missing" % name)
	for lod in triangles:
		if not whole_player:
			if int(triangles[lod]) > V2_PART_MAX_TRIANGLES:
				out.append("part %s has %d triangles (budget %d)" % [lod, int(triangles[lod]), V2_PART_MAX_TRIANGLES])
			continue
		if int(triangles[lod]) > int(V2_MAX_TRIANGLES.get(lod, 60000)):
			out.append("level of detail '%s' has %d triangles (budget %d)" % [lod, int(triangles[lod]), int(V2_MAX_TRIANGLES.get(lod, 60000))])
	var armature := root.find_child("Armature", true, false)
	var extras: Dictionary = armature.get_meta("extras", {}) if armature != null and armature.has_meta("extras") else {}
	if whole_player and names.has("skin"):
		var height := (names["skin"] as MeshInstance3D).mesh.get_aabb().end.y
		var declared := float(extras.get("fc_height_m", 0.0))
		if declared <= 0.0 or absf(declared - height) > 0.06 * declared:
			out.append("the declared height fc_height_m (%s) does not match the model (%.3f m)" % [str(extras.get("fc_height_m", "missing")), height])
		if height < float(std["limits"]["min_height_m"]) or height > float(std["limits"]["max_height_m"]):
			out.append("height %.3f m is outside the allowed range" % height)
	return out


static func _check_bones(sk: Skeleton3D, std: Dictionary, chain_allowed: bool = false) -> Array[String]:
	var out: Array[String] = []
	var wanted := {}
	for bone in std["bones"]:
		wanted[str(bone["name"])] = str(bone["parent"])
	for name in wanted:
		var i := sk.find_bone(name)
		if i < 0:
			out.append("the standard bone %s is missing" % name)
			continue
		var parent := sk.get_bone_parent(i)
		var parent_name := sk.get_bone_name(parent) if parent >= 0 else ""
		if chain_allowed:
			# model standard 2: walk up through x_ bones to the first standard bone
			var walk := parent
			while walk >= 0 and sk.get_bone_name(walk).begins_with("x_"):
				walk = sk.get_bone_parent(walk)
			parent_name = sk.get_bone_name(walk) if walk >= 0 else ""
		if parent_name != wanted[name]:
			out.append("bone %s has the parent '%s' but the standard says '%s'" % [name, parent_name, wanted[name]])
	for i in sk.get_bone_count():
		var name := sk.get_bone_name(i)
		if not wanted.has(name):
			if not name.begins_with("x_"):
				out.append("bone %s is not in the standard (extension bones must be named x_something)" % name)
			elif sk.get_bone_parent(i) < 0:
				out.append("extension bone %s has no parent" % name)
	return out


static func _global_rest(sk: Skeleton3D) -> Dictionary:
	var out := {}
	var cache: Array = []
	for i in sk.get_bone_count():
		var local := sk.get_bone_rest(i)
		var parent := sk.get_bone_parent(i)
		cache.append(local if parent < 0 else (cache[parent] as Transform3D) * local)
		out[sk.get_bone_name(i)] = cache[i]
	return out


static func _check_rest_pose(sk: Skeleton3D) -> Array[String]:
	var out: Array[String] = []
	var g := _global_rest(sk)
	var at := func(name: String) -> Vector3: return (g[name] as Transform3D).origin
	for chain in [["l_shoulder", "l_elbow", "l_hand"], ["r_shoulder", "r_elbow", "r_hand"], ["l_hip", "l_knee", "l_foot"], ["r_hip", "r_knee", "r_foot"]]:
		for k in 2:
			var upper: Vector3 = at.call(chain[k])
			var lower: Vector3 = at.call(chain[k + 1])
			if lower.y >= upper.y - 0.01:
				out.append("rest pose: %s must be below %s (arms hang, legs stand)" % [chain[k + 1], chain[k]])
			elif absf(lower.x - upper.x) > 0.35 * upper.distance_to(lower):
				out.append("rest pose: %s is not straight below %s (a T-pose or A-pose is not allowed: the animation maths assume arms hanging)" % [chain[k + 1], chain[k]])
	var left: Vector3 = at.call("l_shoulder")
	var right: Vector3 = at.call("r_shoulder")
	if not (left.x > 0.02 and right.x < -0.02):
		out.append("the left side must be +X (l_shoulder x %.3f, r_shoulder x %.3f)" % [left.x, right.x])
	var pelvis: Vector3 = at.call("pelvis")
	var torso: Vector3 = at.call("torso")
	var neck: Vector3 = at.call("neck")
	var head: Vector3 = at.call("head")
	if not (head.y > neck.y and neck.y > torso.y and torso.y >= pelvis.y - 0.001):
		out.append("rest pose: head must be above neck, neck above torso, torso above pelvis")
	var ankle: float = (at.call("l_foot") as Vector3).y
	if ankle < 0.02 or ankle > 0.2:
		out.append("the ankles are %.3f m above the floor (expected 0.02 to 0.2: the model must stand on y = 0)" % ankle)
	return out


static func _check_meshes(root: Node, sk: Skeleton3D, std: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var limits: Dictionary = std["limits"]
	var meshes := {}
	var triangles := 0
	for node in sk.get_children():
		if node is MeshInstance3D:
			meshes[str(node.name)] = node
	for name in REQUIRED_SURFACES:
		if not meshes.has(name):
			out.append("the standard surface mesh '%s' is missing" % name)
	var has_hair := false
	for name in meshes:
		if str(name).begins_with("hair_"):
			has_hair = true
		if material_for(str(name)) == "":
			out.append("mesh '%s' is not an approved surface name" % name)
	if not has_hair:
		out.append("at least one hair mesh named hair_<style> is needed (hair_short, hair_afro, ...)")
	for name in meshes:
		var m := meshes[name] as MeshInstance3D
		if m.mesh == null or m.mesh.get_surface_count() == 0:
			out.append("mesh %s has no geometry" % name)
			continue
		if m.skin == null:
			out.append("mesh %s is not skinned to the skeleton" % name)
		var material := m.mesh.surface_get_material(0)
		var wanted := "hair" if str(name).begins_with("hair_") else str(name)
		if material == null or material.resource_name != wanted:
			out.append("mesh %s must have a material named '%s' (the game recolours materials by name)" % [name, wanted])
		for s in m.mesh.get_surface_count():
			var arrays := m.mesh.surface_get_arrays(s)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			triangles += indices.size() / 3 if indices.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			out.append_array(_check_weights(str(name), arrays, m))
	if triangles > int(limits["max_triangles"]):
		out.append("%d triangles is over the budget of %d" % [triangles, int(limits["max_triangles"])])
	# height: the skin mesh against the declared height
	var armature := root.find_child("Armature", true, false)
	var extras: Dictionary = armature.get_meta("extras", {}) if armature != null and armature.has_meta("extras") else {}
	if int(extras.get("fc_standard_version", 0)) != int(std["standard_version"]):
		out.append("the armature extras must declare fc_standard_version %d (found %s)" % [int(std["standard_version"]), str(extras.get("fc_standard_version", "nothing"))])
	if meshes.has("skin") and meshes.has("features"):
		var skin_box := (meshes["skin"] as MeshInstance3D).mesh.get_aabb()
		var face_box := (meshes["features"] as MeshInstance3D).mesh.get_aabb()
		var height := skin_box.end.y
		if height < float(limits["min_height_m"]) or height > float(limits["max_height_m"]):
			out.append("height %.3f m is outside the allowed %.2f to %.2f m" % [height, float(limits["min_height_m"]), float(limits["max_height_m"])])
		var declared := float(extras.get("fc_height_m", 0.0))
		if declared <= 0.0 or absf(declared - height) > 0.06 * declared:
			out.append("the declared height fc_height_m (%s) does not match the model (%.3f m); hair is not counted" % [str(extras.get("fc_height_m", "missing")), height])
		if face_box.get_center().z <= skin_box.get_center().z:
			out.append("the face must point to +Z (the features mesh is behind the middle of the body)")
	return out


## Every vertex is weighted and the weights of a vertex sum to one.
static func _check_weights(name: String, arrays: Array, m: MeshInstance3D) -> Array[String]:
	var out: Array[String] = []
	var weights: Variant = arrays[Mesh.ARRAY_WEIGHTS]
	var bones: Variant = arrays[Mesh.ARRAY_BONES]
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	if weights == null or bones == null:
		out.append("mesh %s has no bone weights" % name)
		return out
	var w: PackedFloat32Array = weights
	var per := w.size() / maxi(vertices.size(), 1)
	if per < 4 or w.size() % maxi(vertices.size(), 1) != 0:
		out.append("mesh %s has an odd weight layout" % name)
		return out
	var bad := 0
	for v in vertices.size():
		var total := 0.0
		for k in per:
			total += w[v * per + k]
		if absf(total - 1.0) > 0.02:
			bad += 1
	if bad > 0:
		out.append("mesh %s has %d vertices whose weights do not sum to 1" % [name, bad])
	var bind_count := m.skin.get_bind_count() if m.skin != null else 0
	var b: PackedInt32Array = bones
	for index in b:
		if index >= bind_count and bind_count > 0:
			out.append("mesh %s refers to a bone index outside its skin" % name)
			break
	return out
