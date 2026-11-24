extends FcTestCase
## 3D overhaul M1: the body of a 3D player is a pure function of what the game already knows (identity, height, weight, position, key), differs
## between positions the way real positions differ, and the generated skinned mesh is valid (indices in range, weights sum to one, no NaN, a skeleton
## with every joint the pose maths drives). Nothing here needs a window.


func _subject(key: String, position: String, height: int, weight: int, hair: String = "short", facial: String = "none") -> Dictionary:
	return {"key": key, "name": key, "jersey": 7, "position": position, "appearance": {"skin": "tone_3", "hair": hair, "facial_hair": facial},
		"physical": {"height_cm": height, "weight_kg": weight}, "team": {"primary": "#2F6FED", "secondary": "#F4F7FF", "abbreviation": "HOM", "name": "Home"}}


func _archetype(subject: Dictionary) -> Dictionary:
	return FcBodyArchetype.make(FcPlayerVisual.resolve(subject))


func test_the_same_player_always_gets_the_same_body() -> void:
	var a := _archetype(_subject("same", "SF", 201, 98))
	var b := _archetype(_subject("same", "SF", 201, 98))
	assert_eq(a, b, "a body depends on nothing but the subject")
	var other := _archetype(_subject("other", "SF", 201, 98))
	assert_true(a != other, "two players of one position and size are still two bodies (a steady personal variation)")


func test_positions_differ_the_way_real_positions_differ() -> void:
	var guard := _archetype(_subject("g", "PG", 185, 80))
	var center := _archetype(_subject("c", "C", 213, 120))
	assert_true(center["height_feet"] > guard["height_feet"] + 0.8, "a centre is much taller")
	assert_true(center["bulk"] > guard["bulk"], "a centre is thicker")
	assert_true(center["shoulder_x"] > guard["shoulder_x"], "a centre has broader shoulders")
	assert_true(center["wingspan"] > guard["wingspan"], "a centre has longer arms for his height")
	assert_true(center["hand"] > guard["hand"], "a centre has bigger hands")
	assert_true(center["head_h"] < guard["head_h"], "the taller body has the relatively smaller head")
	var lean := _archetype(_subject("l", "SF", 200, 82))
	var heavy := _archetype(_subject("h", "SF", 200, 118))
	assert_true(heavy["mass"] > lean["mass"] and heavy["thigh_r"] > lean["thigh_r"] and heavy["chest_rx"] > lean["chest_rx"], "weight for the height makes the body heavier")


func test_every_proportion_is_in_a_human_range_for_many_players() -> void:
	for i in 60:
		var pos: String = ["PG", "SG", "SF", "PF", "C"][i % 5]
		var a := _archetype(_subject("range:%d" % i, pos, 175 + (i * 7) % 45, 70 + (i * 11) % 60))
		assert_true(a["wingspan"] > 0.98 and a["wingspan"] < 1.1, "wingspan %.3f" % a["wingspan"])
		assert_true(a["head_h"] > 0.11 and a["head_h"] < 0.14, "head %.3f" % a["head_h"])
		assert_true(a["leg_ratio"] > 0.95 and a["leg_ratio"] < 1.05, "legs %.3f" % a["leg_ratio"])
		assert_true(a["shoulder_x"] > 0.1 and a["shoulder_x"] < 0.13, "shoulders %.3f" % a["shoulder_x"])
		assert_true(a["mass"] >= 0.0 and a["mass"] <= 1.0 and a["bulk"] >= 0.0 and a["bulk"] <= 1.0)


func test_the_generated_mesh_is_valid_and_skinned_to_a_complete_skeleton() -> void:
	for hair in ["bald", "short", "fade", "afro", "braids", "locs", "curly", "long"]:
		for facial in ["none", "stubble", "goatee", "beard"]:
			var c := FcBroadcastCharacter.new().setup(_subject("mesh:%s:%s" % [hair, facial], "SG", 196, 90, hair, facial))
			for name in FcBodyBuilder.SURFACES:
				var s: FcMeshSurface = c.builder.surface(name)
				assert_true(s.is_valid(), "%s %s: surface %s is valid" % [hair, facial, name])
			assert_true(c.skeleton.get_bone_count() == FcBodyBuilder.BONES.size(), "the skeleton has every bone")
			assert_true(c.triangle_count() > 3000 and c.triangle_count() < 20000, "%s %s: %d triangles is a sensible budget for ten players" % [hair, facial, c.triangle_count()])
			assert_true(c.body_mesh.skin != null and c.body_mesh.mesh.get_surface_count() >= 6, "a skinned mesh with separate skin, hair, jersey, shorts and shoe surfaces")
			c.free()
	for joint in FcBroadcastPose.JOINTS:
		assert_true(FcBodyBuilder.BONES.has(joint), "the pose maths drives %s, so the skeleton has it" % joint)


func test_five_archetypes_are_visibly_different_bodies() -> void:
	var seen := {}
	var specs := [["PG", 183, 78], ["SG", 193, 87], ["SF", 201, 98], ["PF", 208, 113], ["C", 216, 125]]
	var heights: Array = []
	for spec in specs:
		var c := FcBroadcastCharacter.new().setup(_subject("arch:%s" % spec[0], spec[0], spec[1], spec[2]))
		seen[FcBodyArchetype.describe(c.archetype)] = true
		heights.append(c.height_feet)
		var head: Vector3 = c.builder.rest_origin("head")
		assert_true(head.y > c.height_feet * 0.82 and head.y < c.height_feet, "the head sits near the top of the body")
		assert_true(absf((c.builder.rest_origin("l_shoulder") as Vector3).x + (c.builder.rest_origin("r_shoulder") as Vector3).x) < 0.0001, "the body is symmetric")
		c.free()
	assert_eq(seen.size(), 5, "five different descriptions")
	for i in 4:
		assert_true(heights[i + 1] > heights[i], "heights rise from guard to centre")


func test_the_feet_stand_on_the_floor_in_the_rest_pose() -> void:
	var c := FcBroadcastCharacter.new().setup(_subject("floor", "SF", 201, 98))
	var lowest := 100.0
	for name in ["l_foot", "r_foot"]:
		lowest = minf(lowest, (c.builder.rest_origin(name) as Vector3).y)
	assert_true(lowest > 0.0 and lowest < 0.5, "the ankles are a few inches above the floor and the shoes reach it (%.2f ft)" % lowest)
	var sole: FcMeshSurface = c.builder.surface("sole")
	var floor_y := 100.0
	for v in sole.vertices:
		floor_y = minf(floor_y, v.y)
	assert_true(absf(floor_y) < 0.02, "the soles touch y = 0 (%.3f)" % floor_y)
	c.free()
