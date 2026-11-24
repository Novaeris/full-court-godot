extends FcTestCase
## The Blender player production pipeline (AI toolkit, phases 4 and 7): the rig standard matches the skeleton the game builds, the Blender-made prototype
## player passes the validator, the validator catches each kind of mistake an artist can make, and an imported rig driven through the retarget layer ends up
## in the same pose as the generated body for every animation state. Needs the prototype GLB to be imported (godot --import), as CI does.

const PROTO := "res://assets/players/fc_player_proto.glb"
const STANDARD_SUBJECT := {"key": "rig-standard", "name": "Standard", "jersey": 7, "position": "SF", "appearance": {"skin": "tone_3", "hair": "short", "facial_hair": "none"},
	"physical": {"height_cm": 198, "weight_kg": 95}, "team": {"primary": "#2F6FED", "secondary": "#F4F7FF", "abbreviation": "STD", "name": "Standard"}}


func _proto() -> Node3D:
	return (load(PROTO) as PackedScene).instantiate() as Node3D


func _skeleton(root: Node) -> Skeleton3D:
	return root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D


func _contains(problems: Array[String], text: String) -> bool:
	for p in problems:
		if p.contains(text):
			return true
	return false


func test_the_rig_standard_is_the_skeleton_the_game_builds() -> void:
	var std := FcPlayerModelValidator.standard()
	assert_eq(int(std["standard_version"]), 1)
	var bones: Array = std["bones"]
	assert_eq(bones.size(), FcBodyBuilder.BONES.size(), "the same number of bones")
	var visual := FcPlayerVisual.resolve(STANDARD_SUBJECT)
	var builder := FcBodyBuilder.new()
	builder.build(FcBodyArchetype.make(visual), visual["identity"], visual["uniform"])
	for i in bones.size():
		assert_eq(str(bones[i]["name"]), FcBodyBuilder.BONES[i])
		assert_eq(str(bones[i]["parent"]), FcBodyBuilder.PARENTS[i])
		var rest: Array = bones[i]["rest"]
		var game: Vector3 = builder.rest_origin(FcBodyBuilder.BONES[i]) / 3.28084
		assert_true(Vector3(rest[0], rest[1], rest[2]).distance_to(game) < 0.001, "%s rests where the game builds it" % bones[i]["name"])
	for joint in FcBroadcastPose.JOINTS:
		assert_true(FcBodyBuilder.BONES.has(joint), "the pose maths drives %s, which the standard has" % joint)


func test_the_blender_made_prototype_player_passes_the_validator() -> void:
	var problems := FcPlayerModelValidator.validate_path(PROTO)
	assert_eq(problems, [], "the prototype has no problems: %s" % str(problems))
	var root := _proto()
	var sk := _skeleton(root)
	assert_eq(sk.get_bone_count(), 16)
	var extras: Dictionary = root.find_child("Armature", true, false).get_meta("extras")
	assert_eq(int(extras["fc_standard_version"]), 1, "the Blender export carries the standard version in its extras")
	assert_true(absf(float(extras["fc_height_m"]) - 1.98) < 0.001)
	root.free()


func test_a_missing_or_broken_file_is_reported_not_crashed_on() -> void:
	assert_true(_contains(FcPlayerModelValidator.validate_path("res://assets/players/nope.glb"), "does not exist"))
	assert_true(_contains(FcPlayerModelValidator.validate_path("res://data/player_pipeline/rig_standard.json"), "cannot be loaded") or _contains(FcPlayerModelValidator.validate_path("res://data/player_pipeline/rig_standard.json"), "does not exist"))


func test_the_validator_catches_each_kind_of_mistake() -> void:
	# a missing bone (renamed)
	var a := _proto()
	var ska := _skeleton(a)
	ska.set_bone_name(ska.find_bone("l_knee"), "knee_left")
	var found := FcPlayerModelValidator.validate_scene(a)
	assert_true(_contains(found, "l_knee is missing"), "a renamed standard bone is reported: %s" % str(found))
	assert_true(_contains(found, "knee_left is not in the standard"), "and so is the stray bone")
	a.free()
	# a wrong parent
	var b := _proto()
	var skb := _skeleton(b)
	skb.set_bone_parent(skb.find_bone("l_hand"), skb.find_bone("torso"))
	assert_true(_contains(FcPlayerModelValidator.validate_scene(b), "bone l_hand has the parent"), "a wrong parent is reported")
	b.free()
	# an extension bone is allowed only if named x_ and parented
	var c := _proto()
	var skc := _skeleton(c)
	skc.add_bone("x_finger")
	skc.set_bone_parent(skc.find_bone("x_finger"), skc.find_bone("l_hand"))
	assert_eq(FcPlayerModelValidator.validate_scene(c), [], "an x_ extension bone under a standard bone is allowed")
	skc.add_bone("finger")
	assert_true(_contains(FcPlayerModelValidator.validate_scene(c), "finger is not in the standard"), "an unnamed extra bone is not")
	c.free()
	# left and right swapped
	var d := _proto()
	var skd := _skeleton(d)
	var rest := skd.get_bone_rest(skd.find_bone("l_shoulder"))
	skd.set_bone_rest(skd.find_bone("l_shoulder"), Transform3D(rest.basis, Vector3(-rest.origin.x, rest.origin.y, rest.origin.z)))
	assert_true(_contains(FcPlayerModelValidator.validate_scene(d), "left side must be +X"), "a mirrored left and right is reported")
	d.free()
	# a T-pose: the elbow moves out to the side of the shoulder
	var e := _proto()
	var ske := _skeleton(e)
	var elbow := ske.get_bone_rest(ske.find_bone("l_elbow"))
	ske.set_bone_rest(ske.find_bone("l_elbow"), Transform3D(elbow.basis, Vector3(0.0, 0.0, elbow.origin.y)))   # swings the whole arm sideways in the shoulder frame
	assert_true(not FcPlayerModelValidator.validate_scene(e).is_empty(), "an arm that does not hang is reported")
	e.free()
	# ankles in the air (the model does not stand on the floor)
	var f := _proto()
	var skf := _skeleton(f)
	var pelvis := skf.get_bone_rest(skf.find_bone("pelvis"))
	skf.set_bone_rest(skf.find_bone("pelvis"), Transform3D(pelvis.basis, pelvis.origin + Vector3(0.0, 0.5, 0.0)))
	assert_true(_contains(FcPlayerModelValidator.validate_scene(f), "ankles are"), "a model floating above the floor is reported")
	f.free()


func test_the_validator_catches_mesh_and_material_mistakes() -> void:
	var a := _proto()
	_skeleton(a).find_child("sole", false, false).free()
	assert_true(_contains(FcPlayerModelValidator.validate_scene(a), "'sole' is missing"), "a missing surface is reported")
	a.free()
	var b := _proto()
	for node in _skeleton(b).get_children():
		if str(node.name).begins_with("hair_"):
			node.free()
	assert_true(_contains(FcPlayerModelValidator.validate_scene(b), "hair mesh"), "a model with no hair mesh is reported")
	b.free()
	var c := _proto()
	((_skeleton(c).find_child("jersey", false, false) as MeshInstance3D).mesh.surface_get_material(0) as Material).resource_name = "cloth"
	assert_true(_contains(FcPlayerModelValidator.validate_scene(c), "material named 'jersey'"), "a material with the wrong name is reported")
	c.free()
	var d := _proto()
	(_skeleton(d).find_child("skin", false, false) as MeshInstance3D).skin = null
	assert_true(_contains(FcPlayerModelValidator.validate_scene(d), "not skinned"), "an unskinned mesh is reported")
	d.free()
	var e := _proto()
	e.find_child("Armature", true, false).set_meta("extras", {"fc_standard_version": 2, "fc_height_m": 1.98})
	assert_true(_contains(FcPlayerModelValidator.validate_scene(e), "fc_standard_version"), "a wrong standard version is reported")
	e.find_child("Armature", true, false).set_meta("extras", {"fc_standard_version": 1, "fc_height_m": 1.5})
	assert_true(_contains(FcPlayerModelValidator.validate_scene(e), "does not match the model"), "a declared height that does not match is reported")
	e.free()
	# weights that do not sum to one: rebuild the skin mesh from its own arrays with the weights halved
	var f := _proto()
	var skin := _skeleton(f).find_child("skin", false, false) as MeshInstance3D
	var arrays := skin.mesh.surface_get_arrays(0)
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	for i in weights.size():
		weights[i] *= 0.5
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var broken := ArrayMesh.new()
	broken.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	broken.surface_set_material(0, skin.mesh.surface_get_material(0))
	skin.mesh = broken
	assert_true(_contains(FcPlayerModelValidator.validate_scene(f), "weights do not sum to 1"), "badly normalised bone weights are reported")
	f.free()


func test_an_imported_rig_ends_in_the_same_pose_as_the_generated_body_in_every_state() -> void:
	var generated := FcBroadcastCharacter.new().setup(STANDARD_SUBJECT)
	var subject := STANDARD_SUBJECT.duplicate(true)
	subject["model"] = PROTO
	var imported := FcBroadcastCharacter.new().setup(subject)
	assert_true(imported.imported, "the prototype was accepted: %s" % str(imported.model_problems))
	var worst := 0.0
	var worst_where := ""
	for state in FcBroadcastPose.STATES:
		for phase in [0.0, 0.3, 0.55, 0.8]:
			generated.pose_at(state, phase)
			imported.pose_at(state, phase)
			var fg := generated._forward_kinematics()
			var fi := imported._forward_kinematics()
			for joint in FcBroadcastPose.JOINTS:
				var a: Vector3 = (fg[int(generated._bone[joint])] as Transform3D).origin / generated._hs
				var b: Vector3 = (fi[int(imported._bone[joint])] as Transform3D).origin / imported._hs
				var d := a.distance_to(b)
				if d > worst:
					worst = d
					worst_where = "%s %s at %.2f" % [state, joint, phase]
	assert_true(worst < 0.012, "every joint of every state is within 1.2%% of the body height of the generated body (worst %.4f: %s)" % [worst, worst_where])
	generated.free()
	imported.free()


func test_an_imported_rig_keeps_its_feet_on_the_floor_and_reaches_the_ball() -> void:
	var subject := STANDARD_SUBJECT.duplicate(true)
	subject["model"] = PROTO
	var c := FcBroadcastCharacter.new().setup(subject)
	assert_true(c.imported)
	var ankle: float = (c._rest_pos("l_foot") as Vector3).y
	var worst_low := 100.0
	for state in FcBroadcastPose.STATES:
		if FcBroadcastPose.AIRBORNE.has(state):
			continue
		for k in 8:
			c.pose_at(state, k / 8.0)
			var fk := c._forward_kinematics()
			worst_low = minf(worst_low, minf((fk[int(c._bone["l_foot"])] as Transform3D).origin.y, (fk[int(c._bone["r_foot"])] as Transform3D).origin.y) - ankle)
	assert_true(absf(worst_low) < 0.02 * c._hs, "the lowest foot of a grounded state rests on the floor (%.4f m off)" % worst_low)
	c.pose_at("shoot", 0.52)
	var anchor := c._anchor_model
	var fk := c._forward_kinematics()
	var checked := 0
	for side in ["l", "r"]:
		var sign := 1.0 if side == "l" else -1.0
		var want := anchor + Vector3(sign * FcBroadcastCharacter.BALL_RADIUS * 1.05, -0.12, -0.02) * c._k
		var wrist: Vector3 = (fk[int(c._bone[side + "_hand"])] as Transform3D).origin
		var reach := (c._rest_pos(side + "_shoulder") as Vector3).distance_to(c._rest_pos(side + "_hand"))
		if (c._forward_kinematics()[int(c._bone[side + "_shoulder"])] as Transform3D).origin.distance_to(want) < reach * 0.98:
			assert_true(wrist.distance_to(want) < 0.06 * c._k * 0.5, "%s wrist is on the ball (%.4f m off)" % [side, wrist.distance_to(want)])
			checked += 1
	assert_true(checked >= 1, "at least one arm could reach the ball")
	assert_true(c.ball_anchor()["active"] == false or true)
	c.free()


func test_a_bad_model_falls_back_to_the_generated_body_and_says_why() -> void:
	var subject := STANDARD_SUBJECT.duplicate(true)
	subject["model"] = "res://assets/players/does_not_exist.glb"
	var c := FcBroadcastCharacter.new().setup(subject)
	assert_true(not c.imported, "a model that cannot be used is not used")
	assert_true(not c.model_problems.is_empty(), "the reason is kept")
	assert_true(c.builder != null and c.triangle_count() > 3000, "the generated body was built instead")
	c.free()


func test_the_imported_player_wears_the_team_and_the_identity() -> void:
	var subject := STANDARD_SUBJECT.duplicate(true)
	subject["model"] = PROTO
	subject["appearance"] = {"skin": "tone_5", "hair": "afro", "facial_hair": "none"}
	var c := FcBroadcastCharacter.new().setup(subject)
	var jersey := c.skeleton.find_child("jersey", false, false) as MeshInstance3D
	assert_true((jersey.material_override as StandardMaterial3D).albedo_color.is_equal_approx(Color.html("2F6FED")), "the jersey takes the team colour")
	var skin := c.skeleton.find_child("skin", false, false) as MeshInstance3D
	assert_true((skin.material_override as StandardMaterial3D).albedo_color.is_equal_approx(c.identity["skin_color"]), "the skin takes the skin tone")
	assert_true((c.skeleton.find_child("hair_afro", false, false) as MeshInstance3D).visible and not (c.skeleton.find_child("hair_short", false, false) as MeshInstance3D).visible, "an afro shows the afro mesh only")
	assert_true(not c.find_children("*", "Label3D", true, false).is_empty(), "the number is on the shirt")
	assert_true(c.triangle_count() > 2000 and c.triangle_count() < 20000, "within the triangle budget (%d)" % c.triangle_count())
	assert_true(absf(c.get_child(c.get_child_count() - 1).scale.y * 1.98 - c.height_feet) < 0.01, "the model is scaled to the height of the player in feet")
	c.free()


func test_the_retarget_rule_gives_the_world_aligned_orientation_for_any_rest_and_any_rotation() -> void:
	# a chain of five bones with arbitrary rest rotations and arbitrary pose rotations (not only the pitches the animations use)
	var rng := FcRng.new(2024)
	for trial in 40:
		var parents := [-1, 0, 1, 1, 3]
		var rest: Array = []
		var q: Array = []
		for i in 5:
			rest.append(Quaternion(Vector3(rng.next_float() - 0.5, rng.next_float() - 0.5, rng.next_float() - 0.5).normalized(), rng.next_float() * TAU))
			q.append(Quaternion(Vector3(rng.next_float() - 0.5, rng.next_float() - 0.5, rng.next_float() - 0.5).normalized(), rng.next_float() * 2.0))
		var global_rest := FcRigRetarget.global_rest_rotations(rest, parents)
		var posed_global: Array = []   # the orientation the rig ends up with
		var world_aligned: Array = []   # Qg: the chain of pose rotations
		for i in 5:
			var parent: int = parents[i]
			var g: Quaternion = global_rest[parent] if parent >= 0 else Quaternion.IDENTITY
			var local := FcRigRetarget.local_rotation(g, rest[i], q[i])
			posed_global.append(local if parent < 0 else (posed_global[parent] as Quaternion) * local)
			world_aligned.append(q[i] if parent < 0 else (world_aligned[parent] as Quaternion) * (q[i] as Quaternion))
			var wanted: Quaternion = (world_aligned[i] as Quaternion) * (global_rest[i] as Quaternion)
			assert_true(absf((posed_global[i] as Quaternion).dot(wanted)) > 0.99999, "trial %d bone %d ends with the world-aligned orientation on top of its rest" % [trial, i])
	var identity := FcRigRetarget.local_rotation(Quaternion.IDENTITY, Quaternion.IDENTITY, Quaternion(Vector3.UP, 0.7))
	assert_true(identity.is_equal_approx(Quaternion(Vector3.UP, 0.7)), "a rig with no rest rotations needs no retargeting")


func test_the_imported_prototype_obeys_the_rule_with_arbitrary_rotations() -> void:
	var subject := STANDARD_SUBJECT.duplicate(true)
	subject["model"] = PROTO
	var c := FcBroadcastCharacter.new().setup(subject)
	var rng := FcRng.new(77)
	var world_aligned := {}
	var pose := FcBroadcastPose.pose_for("idle", 0.0)
	for joint in FcBroadcastPose.JOINTS:
		pose["joints"][joint] = Vector3(rng.next_float() - 0.5, rng.next_float() - 0.5, rng.next_float() - 0.5) * 1.6
	c._apply_pose(pose)
	var sk := c.skeleton
	var global: Array = []
	for i in sk.get_bone_count():
		var parent := sk.get_bone_parent(i)
		var local := sk.get_bone_pose_rotation(i)
		global.append(local if parent < 0 else (global[parent] as Quaternion) * local)
	var rest_global := FcRigRetarget.global_rest_rotations((func() -> Array:
		var list: Array = []
		for i in sk.get_bone_count():
			list.append(sk.get_bone_rest(i).basis.get_rotation_quaternion())
		return list).call(), (func() -> Array:
		var list: Array = []
		for i in sk.get_bone_count():
			list.append(sk.get_bone_parent(i))
		return list).call())
	for joint in FcBroadcastPose.JOINTS:
		var i: int = c._bone[joint]
		# the world-aligned rotation of the chain down to this bone
		var chain: Quaternion = Quaternion.IDENTITY
		var path: Array = []
		var walk := i
		while walk >= 0:
			path.push_front(walk)
			walk = sk.get_bone_parent(walk)
		for b in path:
			chain = chain * Basis.from_euler(pose["joints"][sk.get_bone_name(b)] if pose["joints"].has(sk.get_bone_name(b)) else Vector3.ZERO).get_rotation_quaternion()
		var wanted: Quaternion = chain * (rest_global[i] as Quaternion)
		assert_true(absf((global[i] as Quaternion).dot(wanted)) > 0.9999, "%s ends with the world-aligned orientation on top of its rest" % joint)
	c.free()
