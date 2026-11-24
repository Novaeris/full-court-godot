extends FcTestCase
## 3D overhaul M4: the arena is dressed from the arena identity (seat colours, banners, truss, ribbon, scorer table, courtside), officials and coaches are
## characters in their own clothes, and the crowd cards are drawn as people. Nothing here needs a window.


func _identity(abbr: String = "HOM", color: String = "2F6FED") -> Dictionary:
	return FcArenaIdentity.make({"home": {"abbr": abbr, "name": "Home Team", "color": Color.html(color)}, "away": {"abbr": "AWY", "name": "Away", "color": Color.html("F28A2E")}})


func test_seat_colours_follow_the_teams_and_the_bowl() -> void:
	var id := _identity()
	var lower: Color = FcArenaDressing.seat_color(id, 0, 2)
	var upper: Color = FcArenaDressing.seat_color(id, 0, 12)
	assert_true(lower != upper, "the lower bowl and the upper bowl differ")
	assert_true(FcArenaDressing.seat_color(id, 3, 2) != lower, "the visitors end is in the visitors colour")
	assert_true(FcArenaDressing.seat_color(id, 0, 2) != FcArenaDressing.seat_color(id, 0, 3), "alternate rows differ")
	var other := _identity("XYZ", "C0392B")
	assert_true(FcArenaDressing.seat_color(other, 0, 2) != lower, "a different home team has different seats")


func test_the_scene_is_dressed_and_a_different_team_gets_a_different_arena() -> void:
	var a := FcCourtScene.new()
	a.crowd_count = 300
	a.build(Color.html("2F6FED"), Color.html("F28A2E"), "HOM", _identity("HOM", "2F6FED"))
	var b := FcCourtScene.new()
	b.crowd_count = 300
	b.build(Color.html("C0392B"), Color.html("F28A2E"), "XYZ", _identity("XYZ", "C0392B"))
	assert_eq(int(a.dressing["seat_aisles"]), 4 * 16 * 4, "four aisles on each tier of each side")
	assert_true(int(a.dressing["banners"]) >= 3 and int(a.dressing["banners"]) <= 6, "3 to 6 banners")
	assert_eq(int(a.dressing["lamps"]), 16, "sixteen lamps on the truss")
	assert_eq(int(a.dressing["staff"]), 5, "five people at the scorer table")
	assert_eq(int(a.dressing["courtside"]), 11 * 2 * 2 + 14, "courtside spectators behind both baskets and along the near sideline")
	assert_eq(a.dressing["banners"] == b.dressing["banners"] and a.identity["key"] == b.identity["key"], false, "two arenas are not the same")
	a.set_bench_figures_visible(false)
	a.free()
	b.free()


func test_officials_and_coaches_are_dressed_and_numberless() -> void:
	var ref := FcBroadcastCharacter.new().setup({"key": "official:0", "name": "o", "jersey": 0, "position": "SG", "attire": "referee", "physical": {"height_cm": 183, "weight_kg": 82}, "team": {"primary": "#26272B", "secondary": "#F2F2F2"}})
	var coach := FcBroadcastCharacter.new().setup({"key": "coach:0", "name": "c", "jersey": 0, "position": "SF", "attire": "suit", "physical": {"height_cm": 188, "weight_kg": 92}, "team": {"primary": "#14233A", "secondary": "#F2F2F2"}})
	var player := FcBroadcastCharacter.new().setup({"key": "p", "name": "p", "jersey": 5, "position": "SF", "physical": {"height_cm": 198, "weight_kg": 95}, "team": {"primary": "#2F6FED", "secondary": "#F4F7FF"}})
	for c in [ref, coach]:
		assert_true(c.uniform["attire"] != "playing")
		for name in FcBodyBuilder.SURFACES:
			assert_true((c.builder.surface(name) as FcMeshSurface).is_valid(), "%s surface %s is valid" % [c.uniform["attire"], name])
		assert_eq((c.builder.surface("socks") as FcMeshSurface).vertex_count(), 0, "trousers, so no socks")
		assert_true(c.find_children("*", "Label3D", true, false).is_empty(), "no number on an official or a coach")
	assert_true(not player.find_children("*", "Label3D", true, false).is_empty(), "a player has his number")
	assert_true((coach.builder.surface("jersey") as FcMeshSurface).vertex_count() > (ref.builder.surface("jersey") as FcMeshSurface).vertex_count(), "a coach jacket has long sleeves, a referee shirt short ones")
	assert_true((ref.builder.surface("shorts") as FcMeshSurface).vertex_count() > (player.builder.surface("shorts") as FcMeshSurface).vertex_count(), "long trousers are more cloth than shorts")
	for n in [ref, coach, player]:
		n.free()


func test_sitting_and_coaching_poses_are_valid_and_the_seated_hips_are_at_seat_height() -> void:
	for state in ["sit", "coach"]:
		assert_true(FcBroadcastPose.STATES.has(state))
	var c := FcBroadcastCharacter.new().setup({"key": "sit", "name": "s", "jersey": 5, "position": "SF", "physical": {"height_cm": 198, "weight_kg": 95}, "team": {"primary": "#2F6FED", "secondary": "#F4F7FF"}})
	c.pose_at("sit", 0.3)
	var pelvis_y: float = (c._forward_kinematics()[0] as Transform3D).origin.y
	assert_true(pelvis_y > 1.2 and pelvis_y < 2.3, "the hips of a seated player are %.2f ft up: bench height" % pelvis_y)
	var standing := FcBroadcastCharacter.new().setup({"key": "sit", "name": "s", "jersey": 5, "position": "SF", "physical": {"height_cm": 198, "weight_kg": 95}, "team": {"primary": "#2F6FED", "secondary": "#F4F7FF"}})
	assert_true(pelvis_y < (standing._forward_kinematics()[0] as Transform3D).origin.y - 1.0, "much lower than standing")
	c.free()
	standing.free()


func test_the_crowd_shader_draws_people() -> void:
	var shader := load("res://src/ui/broadcast3d/crowd.gdshader") as Shader
	assert_true(shader != null)
	for word in ["skin_a", "hair_dark", "fan_arms", "ALPHA_SCISSOR_THRESHOLD", "cheer"]:
		assert_true(shader.code.contains(word), "the crowd shader has %s" % word)
	assert_true(load("res://src/ui/broadcast3d/led_ribbon.gdshader") != null, "the LED ribbon shader loads")
