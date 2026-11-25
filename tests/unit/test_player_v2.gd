extends FcTestCase
## Player visual system V2 (D-075): the MakeHuman-based body, its validator rules (model standard 2), the deterministic morph resolver, body types and the
## once-per-player morph bake. Needs assets/players/v2 to be imported (godot --import), as CI does.

const BODY := "res://assets/players/v2/fc_v2_body.glb"


func _subject(key: String, position: String, h: int, w: int) -> Dictionary:
	return {"key": key, "name": "Test " + key, "jersey": 9, "position": position, "physical": {"height_cm": h, "weight_kg": w}, "model": "v2",
		"appearance": {"skin": "tone_4", "hair": "short", "facial_hair": "none"}, "team": {"primary": "#2F6FED", "secondary": "#F4F7FF", "abbreviation": "HOU"}}


func test_the_v2_body_passes_model_standard_2() -> void:
	assert_eq(FcPlayerModelValidator.validate_path(BODY).size(), 0, str(FcPlayerModelValidator.validate_path(BODY)))


func test_the_v2_validator_knows_its_vocabulary() -> void:
	assert_eq(FcPlayerModelValidator.v2_material_for("skin"), "skin")
	assert_eq(FcPlayerModelValidator.v2_material_for("skin__lod1"), "skin", "a level of detail keeps its surface")
	assert_eq(FcPlayerModelValidator.v2_material_for("brow_009"), "brows")
	assert_eq(FcPlayerModelValidator.v2_material_for("mystery"), "")


func test_morph_weights_are_deterministic_and_bounded() -> void:
	var visual := FcPlayerVisual.resolve(_subject("v2-a", "SF", 201, 98))
	var arche := FcBodyArchetype.make(visual)
	var a := FcPlayerMorphs.weights(visual["identity"], arche, "v2-a")
	assert_eq(a, FcPlayerMorphs.weights(visual["identity"], arche, "v2-a"), "the same player, the same weights")
	for k in a:
		assert_between(float(a[k]), 0.0, 1.0, k)
		assert_true(str(k).begins_with("fcb_") or str(k).begins_with("fcf_"), k)


func test_eight_body_types_follow_position_and_build() -> void:
	var seen := {}
	for pos in [1, 2, 3, 4, 5]:
		for mass in [0.1, 0.5, 0.9]:
			for muscle in [0.2, 0.9]:
				seen[FcPlayerMorphs.body_type({"position": pos, "mass": mass, "muscle": muscle})] = true
	assert_eq(seen.size(), 8, "all eight body types are reachable: %s" % str(seen.keys()))
	assert_eq(FcPlayerMorphs.body_type({"position": 5, "mass": 0.9, "muscle": 0.5}), "heavy_center")
	assert_eq(FcPlayerMorphs.body_type({"position": 1, "mass": 0.1, "muscle": 0.3}), "lean_guard")


func test_faces_differ_between_players() -> void:
	var looks := {}
	for i in 100:
		var visual := FcPlayerVisual.resolve({"key": "face-%d" % i, "position": "SF"})
		var w := FcPlayerMorphs.weights(visual["identity"], FcBodyArchetype.make(visual), "face-%d" % i)
		var sig := []
		for k in w:
			if str(k).begins_with("fcf_") and float(w[k]) > 0.12:
				sig.append("%s:%d" % [k, int(float(w[k]) * 4.0)])
		sig.sort()
		looks[",".join(sig)] = true
	assert_eq(looks.size(), 100, "100 players give 100 different faces")


func test_a_v2_player_bakes_its_morphs_and_keeps_its_skin_weights() -> void:
	var c := FcBroadcastCharacter.new().setup(_subject("v2-bake", "C", 213, 120), 0.0)
	assert_true(c.imported and c.v2, "the V2 body loads: %s" % str(c.model_problems))
	assert_true(c.morph_weights.size() > 10, "morphs were set")
	var skin := c.skeleton.find_child("skin", false, false) as MeshInstance3D
	assert_eq((skin.mesh as ArrayMesh).get_blend_shape_count(), 0, "the mix is baked: no per-frame morphs")
	var arrays := skin.mesh.surface_get_arrays(0)
	assert_true(arrays[Mesh.ARRAY_BONES] != null and arrays[Mesh.ARRAY_WEIGHTS] != null, "the baked mesh is still skinned")
	assert_true(skin.material_override is ShaderMaterial, "the skin shader")
	c.free()


func test_a_v2_player_moves_through_every_state() -> void:
	var c := FcBroadcastCharacter.new().setup(_subject("v2-move", "PG", 188, 84), 0.0)
	for state in FcBroadcastPose.STATES:
		c.pose_at(state, 0.4)
		var fk := c._forward_kinematics()
		var head: Vector3 = (fk[c._bone["head"]] as Transform3D).origin
		var foot: Vector3 = (fk[c._bone["l_foot"]] as Transform3D).origin
		assert_true(head.y > foot.y, "%s: the head stays above the feet" % state)
	c.free()


func test_every_v2_part_the_data_can_choose_exists_and_passes() -> void:
	var parts_path := str(FcPlayerMorphs.data()["parts"])
	assert_eq(FcPlayerModelValidator.validate_path(parts_path).size(), 0, str(FcPlayerModelValidator.validate_path(parts_path)))
	var instance := (load(parts_path) as PackedScene).instantiate()
	var names := []
	for list in (FcPlayerMorphs.data()["hair"] as Dictionary).values() + (FcPlayerMorphs.data()["facial_hair"] as Dictionary).values():
		names.append_array(list)
	names.append_array(["acc_headband", "equip_armsleeve_l", "equip_armsleeve_r", "equip_kneesleeve_l", "equip_kneesleeve_r", "equip_wristband_l", "equip_wristband_r"])
	for n in names:
		assert_true(instance.find_child(str(n), true, false) != null, "%s is in the part file" % n)
	instance.free()


func test_parts_follow_the_identity_and_the_key() -> void:
	var visual := FcPlayerVisual.resolve({"key": "parts-a", "appearance": {"skin": "tone_5", "hair": "locs", "facial_hair": "beard"}})
	var a := FcPlayerMorphs.parts(visual["identity"], "parts-a")
	assert_eq(a, FcPlayerMorphs.parts(visual["identity"], "parts-a"), "deterministic")
	assert_true(a.has("hair_dreads"), "locs are dreadlocks")
	assert_true(a.has("facial_beard_short") or a.has("facial_beard_full"), "a beard")
	var bald := FcPlayerVisual.resolve({"key": "parts-b", "appearance": {"skin": "tone_2", "hair": "bald", "facial_hair": "none"}})
	for p in FcPlayerMorphs.parts(bald["identity"], "parts-b"):
		assert_true(not str(p).begins_with("hair_") and not str(p).begins_with("facial_"), "bald and clean-shaven: %s" % p)


func test_a_v2_player_wears_its_parts_with_the_hair_shader() -> void:
	var s := _subject("v2-hair", "SG", 193, 88)
	s["appearance"] = {"skin": "tone_3", "hair": "afro", "facial_hair": "goatee"}
	var c := FcBroadcastCharacter.new().setup(s, 0.0)
	var afro := c.skeleton.find_child("hair_afro", false, false) as MeshInstance3D
	assert_true(afro != null, "the afro is attached: %s" % str(c.part_problems))
	assert_true(afro.material_override is ShaderMaterial, "hair shader")
	assert_eq((afro.mesh as ArrayMesh).get_blend_shape_count(), 0, "the hair was baked with the face")
	c.free()
