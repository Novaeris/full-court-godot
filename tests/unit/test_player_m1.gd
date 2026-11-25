extends FcTestCase
## Production Phase M1 (docs/development/PLAYER_VISUAL_SPEC.md): the player asset library, the swappable part files, the hand poses and the individuality of
## faces. Needs the M1 GLBs to be imported (godot --import), as CI does.

const SUBJECT := {"key": "m1-test", "name": "Jordan Rivers", "jersey": 23, "position": "SG", "appearance": {"skin": "tone_4", "hair": "braids", "facial_hair": "beard"},
	"physical": {"height_cm": 196, "weight_kg": 92}, "team": {"primary": "#2F6FED", "secondary": "#F4F7FF", "abbreviation": "HOU", "name": "Houston"}}


func _character(subject: Dictionary) -> FcBroadcastCharacter:
	var s := subject.duplicate(true)
	s["model"] = FcPlayerAssetLibrary.library_model()
	return FcBroadcastCharacter.new().setup(s, 0.0)


func test_the_registry_is_complete() -> void:
	var problems := FcPlayerAssetLibrary.registry_problems()
	assert_eq(problems.size(), 0, "every body and every part name a spec can produce exists: %s" % str(problems))


func test_every_player_file_and_part_file_passes_the_validator() -> void:
	for path in ["res://assets/players/fc_player_lean.glb", "res://assets/players/fc_player_athletic.glb", "res://assets/players/fc_player_heavy.glb",
			"res://assets/players/parts/fc_parts_head.glb", "res://assets/players/parts/fc_parts_hair.glb"]:
		assert_eq(FcPlayerModelValidator.validate_path(path).size(), 0, path)


func test_the_validator_refuses_an_unknown_surface_name_and_a_wrong_part_material() -> void:
	assert_eq(FcPlayerModelValidator.material_for("hair_afro"), "hair")
	assert_eq(FcPlayerModelValidator.material_for("skin_head_21"), "skin")
	assert_eq(FcPlayerModelValidator.material_for("lips_1"), "lips")
	assert_eq(FcPlayerModelValidator.material_for("trim"), "trim")
	assert_eq(FcPlayerModelValidator.material_for("mystery"), "", "a name outside the vocabulary has no material")


func test_the_spec_is_a_pure_function_of_the_identity() -> void:
	var visual := FcPlayerVisual.resolve(SUBJECT)
	var archetype := FcBodyArchetype.make(visual)
	var a := FcPlayerAssetLibrary.spec(visual["identity"], archetype)
	var b := FcPlayerAssetLibrary.spec(visual["identity"], archetype)
	assert_eq(a, b)
	assert_eq(a["hair"], "hair_braids")
	assert_true(str(a["facial"]).begins_with("facial_beard_"))
	assert_true(["lean", "athletic", "heavy"].has(a["body"]))


func test_the_library_dresses_a_player_from_the_identity() -> void:
	var c := _character(SUBJECT)
	assert_true(c.imported, "the library body loads")
	assert_eq(c.part_problems.size(), 0, str(c.part_problems))
	var names := {}
	for node in c.skeleton.get_children():
		if node is MeshInstance3D and (node as MeshInstance3D).visible:
			names[str(node.name)] = node
	assert_true(names.has(str(c.asset_spec["head"])), "the head")
	assert_true(names.has("hair_braids"), "the braids")
	assert_true(not names.has("hair_short"), "the default hair is hidden")
	assert_true(not names.has("features"), "the default eyes are hidden")
	var skin := (names["skin"] as MeshInstance3D).material_override as StandardMaterial3D
	assert_eq(skin.albedo_color, (c.identity["skin_color"] as Color), "the skin takes the skin tone of the identity")
	assert_eq(((names[str(c.asset_spec["head"])] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color, skin.albedo_color, "the head matches the body")
	c.free()


func test_players_with_the_same_colours_share_materials() -> void:
	FcPlayerAssetLibrary.clear_cache()
	var a := _character(SUBJECT)
	var other := SUBJECT.duplicate(true)
	other["key"] = "m1-test-2"
	other["appearance"] = {"skin": "tone_4", "hair": "braids", "facial_hair": "beard"}
	var b := _character(other)
	var sa := (a.skeleton.find_child("skin", false, false) as MeshInstance3D).material_override
	var sb := (b.skeleton.find_child("skin", false, false) as MeshInstance3D).material_override
	assert_true(sa == sb, "one skin material for one tone")
	a.free()
	b.free()


func test_every_hair_and_facial_hair_style_attaches() -> void:
	for hair in ["bald", "short", "fade", "afro", "braids", "locs", "curly", "long"]:
		for facial in ["none", "stubble", "goatee", "beard"]:
			var s := SUBJECT.duplicate(true)
			s["appearance"] = {"skin": "tone_2", "hair": hair, "facial_hair": facial}
			var c := _character(s)
			assert_eq(c.part_problems.size(), 0, "%s %s: %s" % [hair, facial, str(c.part_problems)])
			c.free()


func test_a_player_stays_within_the_triangle_budget() -> void:
	var c := _character(SUBJECT)
	assert_true(c.triangle_count() <= 20000, "%d triangles" % c.triangle_count())
	c.free()


func test_faces_are_individual_and_deterministic() -> void:
	var looks := {}
	for i in 200:
		var visual := FcPlayerVisual.resolve({"key": "player-%d" % i, "position": "SF", "physical": {"height_cm": 198, "weight_kg": 95}})
		var spec := FcPlayerAssetLibrary.spec(visual["identity"], FcBodyArchetype.make(visual))
		looks["%s|%s|%s|%s|%s|%s" % [spec["head"], spec["nose"], spec["lips"], spec["brow"], spec["eyes"], spec["hair"]]] = true
		var again := FcPlayerAssetLibrary.spec(FcPlayerVisual.resolve({"key": "player-%d" % i, "position": "SF", "physical": {"height_cm": 198, "weight_kg": 95}})["identity"], FcBodyArchetype.make(visual))
		assert_eq(spec, again, "the same key gives the same look")
	assert_true(looks.size() >= 150, "200 similar players give %d distinct looks" % looks.size())


func test_hand_poses_curl_toward_the_palm_and_close_on_the_ball() -> void:
	var relaxed := FcHandPoses.finger_rotations("idle", "l", 0.0)
	var gripped := FcHandPoses.finger_rotations("idle", "l", 1.0)
	assert_eq(relaxed.size(), 15, "five digits, three joints, one hand (a two-joint M1 hand ignores the third)")
	var open_angle := (relaxed["x_l_index_1"] as Quaternion).get_angle()
	var grip_angle := (gripped["x_l_index_1"] as Quaternion).get_angle()
	assert_true(grip_angle > open_angle, "the grip closes the fingers more than the relaxed hand")
	# the two hands mirror each other: the same curl in opposite directions about the front-to-back axis
	var right := FcHandPoses.finger_rotations("idle", "r", 1.0)
	var l_axis := (gripped["x_l_middle_1"] as Quaternion).get_axis()
	var r_axis := (right["x_r_middle_1"] as Quaternion).get_axis()
	assert_true(l_axis.dot(r_axis) < 0.0, "mirrored")
	assert_eq(FcHandPoses.pose_name("shoot", "r"), "shooting")
	assert_eq(FcHandPoses.pose_name("dribble_l", "l"), "dribbling")
	assert_eq(FcHandPoses.pose_name("idle", "l"), "relaxed")


func test_fingers_move_in_every_state_and_never_leave_the_hand() -> void:
	var c := _character(SUBJECT)
	assert_true(c._finger_bones.size() == 20, "the model carries 20 finger bones")
	for state in FcBroadcastPose.STATES:
		c.pose_at(state, 0.4)
		var wrist: Vector3 = c._forward_kinematics()[c._bone["l_hand"]].origin
		var tip_bone: int = c._finger_bones["x_l_middle_2"]
		var tip: Vector3 = c._forward_kinematics()[tip_bone].origin
		assert_true(wrist.distance_to(tip) < 0.2 * c._hs / 1.98 * 1.2, "%s: the finger stays on the hand" % state)
	c.free()


func test_the_jersey_graphics_key_and_surname() -> void:
	assert_eq(FcJerseyGraphics.surname_of("Jordan Rivers"), "RIVERS")
	assert_eq(FcJerseyGraphics.surname_of(""), "")
	assert_true(FcJerseyGraphics.key_for(7, "A", "HOU", Color.WHITE, Color.BLACK) != FcJerseyGraphics.key_for(8, "A", "HOU", Color.WHITE, Color.BLACK))


func test_the_portrait_render_key_follows_the_look_and_the_subject_round_trips() -> void:
	var visual := FcPlayerVisual.resolve(SUBJECT)
	var again := FcPlayerVisual.resolve(SUBJECT)
	assert_eq(FcPlayerRender.key_for(visual), FcPlayerRender.key_for(again), "the same player is the same picture")
	assert_true(FcPlayerRender.key_for(visual) != FcPlayerRender.key_for(visual, "full"), "a full-body picture is a different picture")
	var traded := SUBJECT.duplicate(true)
	traded["team"] = {"primary": "#C8352B", "secondary": "#FFFFFF", "abbreviation": "DAL", "name": "Dallas"}
	assert_true(FcPlayerRender.key_for(visual) != FcPlayerRender.key_for(FcPlayerVisual.resolve(traded)), "new colours are a new picture")
	var subject := FcPlayerRender.subject_from_visual(visual)
	var back := FcPlayerVisual.resolve(subject)
	assert_eq(back["identity"]["skin"], visual["identity"]["skin"])
	assert_eq(back["identity"]["hair"], visual["identity"]["hair"])
	assert_eq(back["identity"]["face"], visual["identity"]["face"])
	assert_eq(JSON.stringify(back["identity"]["proportions"]), JSON.stringify(visual["identity"]["proportions"]), "the face is the same face")
	assert_true(FcPlayerRender.texture_for(visual) == null, "off by default: the 2D figure is drawn")


func test_fingers_rest_on_the_ball_when_both_hands_hold_it() -> void:
	var c := _character(SUBJECT)
	var radius := FcBroadcastCharacter.BALL_RADIUS * c._k
	var checked := 0
	for state in FcBroadcastPose.TWO_HAND:
		for phase in [0.2, 0.4, 0.6]:
			c.pose_at(state, phase)
			if c._grip < 0.99:
				continue
			var fk := c._forward_kinematics()
			for side in ["l", "r"]:
				for digit in ["index", "middle"]:
					var joint: Vector3 = (fk[c._finger_bones["x_%s_%s_2" % [side, digit]]] as Transform3D).origin
					var d := joint.distance_to(c._anchor_model) / radius
					assert_between(d, 0.65, 1.3, "%s %.1f %s %s: the finger lies on the ball (%.2f radii from its centre)" % [state, phase, side, digit, d])
					checked += 1
	assert_true(checked >= 40, "enough grips were checked (%d)" % checked)
	c.free()


func test_the_library_players_are_not_the_default_until_promoted() -> void:
	assert_true(not FcPlayerAssetLibrary.promoted(), "the founder has not promoted them yet (D-074)")
	var saved := FcBroadcast3DView.player_model
	FcBroadcast3DView.player_model = ""
	assert_eq(FcBroadcast3DView.effective_model(), "", "the generated body stays the default")
	FcBroadcast3DView.player_model = "library"
	assert_eq(FcBroadcast3DView.effective_model(), "library", "an explicit choice still wins")
	FcBroadcast3DView.player_model = saved
