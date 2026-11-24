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


static func _check_bones(sk: Skeleton3D, std: Dictionary) -> Array[String]:
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
