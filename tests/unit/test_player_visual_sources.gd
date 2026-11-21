extends FcTestCase
## Which visual source each mode uses (D-059): Owner and Career players are procedural (stable per key, ageing without changing who they are), Dynasty
## players use their approved artwork when it exists and fall back (never randomly regenerate) when it is missing or invalid, and one renderer
## serves all three. Identity is deterministic and survives trades, drafts, other modes, ageing and body data.

const ART := "user://test_visual_sources_art.png"
const BAD := "user://test_visual_sources_bad.png"


func after_each() -> void:
	DirAccess.remove_absolute(ART)
	DirAccess.remove_absolute(BAD)


func _identity(subject: Dictionary) -> Dictionary:
	var v := FcPlayerVisual.resolve(subject)
	var id: Dictionary = v["identity"]
	return {"skin": id["skin"], "hair": id["hair"], "face": id["face"], "facial_hair": id["facial_hair"], "build": id["build"], "prop": id["proportions"], "hair_color": (id["hair_color"] as Color).to_html(false)}


func test_owner_and_career_players_are_procedural() -> void:
	for key in ["owner_player:7", "career_player:3"]:
		var v := FcPlayerVisual.resolve(FcPlayerPresentation.subject(key, "A B", {}, 0))
		assert_eq(int(v["tier"]), FcPlayerVisual.TIER_PROCEDURAL, "%s is drawn by the procedural figure" % key)
		assert_eq(str(v["art_path"]), "")


func test_a_trade_a_draft_or_another_mode_never_changes_the_face() -> void:
	var a := _identity(FcPlayerPresentation.subject("owner_player:11", "A B", {"name": "Reds", "primary": "#AA0000", "secondary": "#FFFFFF"}, 5))
	var traded := _identity(FcPlayerPresentation.subject("owner_player:11", "A B", {"name": "Blues", "primary": "#0000AA", "secondary": "#FFEE00"}, 23))
	var free_agent := _identity(FcPlayerPresentation.subject("owner_player:11", "A B", {}, 0))
	assert_eq(a, traded, "a trade changes the kit, not the face")
	assert_eq(a, free_agent)
	var kit_a: Dictionary = FcPlayerVisual.resolve(FcPlayerPresentation.subject("owner_player:11", "A B", {"primary": "#AA0000", "secondary": "#FFFFFF"}, 5))["uniform"]
	var kit_b: Dictionary = FcPlayerVisual.resolve(FcPlayerPresentation.subject("owner_player:11", "A B", {"primary": "#0000AA", "secondary": "#FFEE00"}, 23))["uniform"]
	assert_true(kit_a["primary"] != kit_b["primary"] and int(kit_a["number"]) != int(kit_b["number"]), "the uniform follows the team context")


func test_a_career_player_keeps_the_face_for_twenty_years() -> void:
	var stored := {"skin": "tone_4", "hair": "braids", "face": "face_3", "facial_hair": "goatee"}
	var first := _identity(FcPlayerPresentation.subject("career_player:1", "M O", {}, 11, stored, "", {"age": 19}))
	for age in range(19, 41):
		assert_eq(_identity(FcPlayerPresentation.subject("career_player:1", "M O", {}, 11, stored, "", {"age": age})), first, "the identity at age %d" % age)
	assert_eq(first["skin"], "tone_4", "the options the player built are kept")
	assert_eq(first["hair"], "braids")
	var young := FcPlayerTraits.of("career_player:1", 19)
	var old := FcPlayerTraits.of("career_player:1", 40)
	assert_true(int(old["lines"]) > int(young["lines"]) and int(old["grey"]) >= int(young["grey"]), "ageing shows in lines and grey only")
	for k in ["eye_shape", "nose_w", "lips", "chin", "cheek", "ear", "undertone", "hair_variant"]:
		assert_eq(young[k], old[k], "%s is the same face" % k)


func test_ageing_changes_the_picture_key_so_a_stale_portrait_is_never_shown() -> void:
	var v19 := FcPlayerVisual.resolve(FcPlayerPresentation.subject("career_player:1", "M O", {}, 11, {}, "", {"age": 19}))
	var v20 := FcPlayerVisual.resolve(FcPlayerPresentation.subject("career_player:1", "M O", {}, 11, {}, "", {"age": 20}))
	assert_true(FcPortraitBake.cache_key(v19, Vector2i(96, 96), "bust") != FcPortraitBake.cache_key(v20, Vector2i(96, 96), "bust"))


func test_dynasty_uses_approved_art_and_falls_back_without_regenerating() -> void:
	var row := {"player_id": "p_curated", "card_id": "c1", "name": "Curated Star", "team": "Harbor Kings"}
	var without := FcPlayerVisual.resolve(FcPlayerPresentation.subject_for_card(row))
	assert_eq(int(without["tier"]), FcPlayerVisual.TIER_PROCEDURAL, "no artwork: the stable procedural figure for this player")
	var image := Image.create_empty(512, 640, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.8, 0.2, 0.2, 1.0))
	image.save_png(ART)
	var with_art := row.duplicate()
	with_art["art_path"] = ART
	var drawn := FcPlayerVisual.resolve(FcPlayerPresentation.subject_for_card(with_art))
	assert_eq(int(drawn["tier"]), FcPlayerVisual.TIER_PORTRAIT, "approved artwork is used when it exists")
	assert_eq(str(drawn["art_path"]), ART)
	var bad := row.duplicate()
	bad["art_path"] = "user://does_not_exist.png"
	var missing := FcPlayerVisual.resolve(FcPlayerPresentation.subject_for_card(bad))
	assert_eq(int(missing["tier"]), FcPlayerVisual.TIER_PROCEDURAL, "a missing file falls back")
	assert_eq(missing["identity"]["proportions"], without["identity"]["proportions"], "to the SAME procedural identity, not a new one")
	var junk := FileAccess.open(BAD, FileAccess.WRITE)
	junk.store_string("this is not a png")
	junk.close()
	var invalid := row.duplicate()
	invalid["art_path"] = BAD
	assert_eq(int(FcPlayerVisual.resolve(FcPlayerPresentation.subject_for_card(invalid))["tier"]), FcPlayerVisual.TIER_PROCEDURAL, "an invalid file falls back")
	assert_eq(int(FcPlayerVisual.monogram_only(FcPlayerPresentation.subject_for_card(row))["tier"]), FcPlayerVisual.TIER_MONOGRAM, "the monogram is still available")


func test_every_edition_of_a_dynasty_player_is_one_face() -> void:
	var base := _identity(FcPlayerPresentation.subject_for_card({"player_id": "p9", "card_id": "p9_base", "name": "N"}))
	var legend := _identity(FcPlayerPresentation.subject_for_card({"player_id": "p9", "card_id": "p9_legend", "name": "N"}))
	assert_eq(base, legend)


func test_the_art_pathway_never_reads_other_modes_keys() -> void:
	var s := FcPlayerPresentation.subject("owner_player:2", "X Y", {}, 0, {}, "user://anything.png")
	assert_eq(int(FcPlayerVisual.resolve(s)["tier"]), FcPlayerVisual.TIER_PROCEDURAL, "an art path that cannot be read changes nothing")


func test_physical_data_flows_into_the_visual_without_touching_identity() -> void:
	var plain := FcPlayerVisual.resolve(FcPlayerPresentation.subject("owner_player:5", "X Y", {}, 0))
	var rich := FcPlayerVisual.resolve(FcPlayerPresentation.subject("owner_player:5", "X Y", {}, 0, {}, "", {"age": 31, "physical": {"height_cm": 206, "weight_kg": 110}, "position": "C"}))
	assert_eq(plain["identity"]["proportions"], rich["identity"]["proportions"])
	assert_eq(int(rich["age"]), 31)
	assert_eq(rich["body_in"]["position"], "C")
	assert_true(not plain.has("age") and not plain.has("body_in"), "nothing is added when nothing is known")
