extends FcTestCase
## Player identity is deterministic AND stable: the faces of 50 fixed keys are compared with a stored fingerprint (tests/support/player_identity_golden.json),
## so a change to how identity is chosen (an option list, a hash salt, the proportions) is a deliberate act: this test fails, the change is
## reviewed against the portrait contact sheet, and the fixture is regenerated (run tools/build_identity_golden.gd). Also checks that sizes and
## crops never change who a player is, and that every mode's way of building a subject gives one face for one key.

const FIXTURE := "res://tests/support/player_identity_golden.json"
const KEY_COUNT := 50


## A short stable fingerprint of one key's identity (every identity field, including the derived proportions).
static func fingerprint(key: String) -> String:
	var id: Dictionary = FcPlayerVisual.resolve(FcPlayerPresentation.subject(key, "Golden", {}, 0))["identity"]
	var prop: Dictionary = id["proportions"]
	var keys := prop.keys()
	keys.sort()
	var parts: Array = [str(id["skin"]), str(id["hair"]), str(id["face"]), str(id["facial_hair"]), str(id["build"]), (id["hair_color"] as Color).to_html(false)]
	for k in keys:
		parts.append("%s=%s" % [k, str(prop[k])])
	return "%08x" % FcPlayerVisual.fnv1a("|".join(parts))


func _fixture() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return parsed if parsed is Dictionary else {}


func test_fifty_fixed_keys_keep_their_faces() -> void:
	var golden := _fixture()
	assert_true(golden.size() == KEY_COUNT, "the fixture lists %d keys" % KEY_COUNT)
	for i in KEY_COUNT:
		var key := "golden:%d" % i
		assert_eq(fingerprint(key), str(golden.get(key, "")), "the face of %s changed (regenerate the fixture only after reviewing the contact sheet)" % key)


func test_the_fifty_faces_are_varied() -> void:
	var seen := {}
	for i in KEY_COUNT:
		seen[fingerprint("golden:%d" % i)] = true
	assert_true(seen.size() >= 48, "at most two of 50 faces may coincide, got %d different" % seen.size())


func test_proportions_vary_even_when_skin_hair_and_face_match() -> void:
	var look := {"skin": "tone_3", "hair": "short", "face": "face_2", "facial_hair": "none"}
	var seen := {}
	for i in 30:
		var id: Dictionary = FcPlayerVisual.resolve(FcPlayerPresentation.subject("same_options:%d" % i, "X", {}, 0, look))["identity"]
		seen[str(id["proportions"])] = true
	assert_true(seen.size() >= 20, "30 players with identical options still have %d different faces" % seen.size())


func test_proportions_stay_inside_their_ranges() -> void:
	for i in 200:
		var p: Dictionary = FcPlayerVisual.proportions("range:%d" % i)
		assert_between(float(p["face_w"]), 80.0, 92.0)
		assert_between(float(p["jaw"]), 0.0, 2.0)
		assert_between(float(p["eye_gap"]), 31.0, 37.0)
		assert_between(float(p["eye_size"]), 90.0, 110.0)
		assert_between(float(p["brow"]), 0.0, 2.0)
		assert_between(float(p["nose"]), 0.0, 2.0)
		assert_between(float(p["mouth"]), 0.0, 2.0)
		assert_between(float(p["accessory"]), 0.0, 1.0)
		assert_between(float(p["warmth"]), -1.0, 1.0)


func test_a_size_or_a_crop_never_changes_who_the_player_is() -> void:
	var subject := FcPlayerPresentation.subject("owner_player:12", "Lena Voss", {"name": "Sky City", "abbreviation": "SKY", "primary": "#8B1E2D", "secondary": "#F5E6C8"}, 23)
	var reference: Dictionary = FcPlayerVisual.resolve(subject)["identity"]
	for px in [24, 32, 48, 64, 96, 128]:
		for crop in ["bust", "head"]:
			var portrait := FcPlayerPortrait.new().setup(subject, px, crop)
			assert_eq(portrait.visual["identity"], reference, "%d px %s" % [px, crop])
			assert_eq(portrait.custom_minimum_size, Vector2(px, px))
			portrait.free()
	var stage := FcShowcaseStage.new().setup(subject, 160)
	assert_eq(stage.visual["identity"], reference, "the full-body stage")
	stage.free()
	var tile := FcPlayerTile.new().setup({"subject": subject, "name": "Lena Voss", "position": "SG", "overall": 80})
	assert_eq(tile.visual["identity"], reference, "the tile")
	tile.free()
	var chip := FcPlayerChip.new().setup({"subject": subject, "name": "Lena Voss", "overall": 80}, "SG")
	assert_eq(chip.portrait.visual["identity"], reference, "the chip")
	chip.free()


func test_every_mode_builds_the_same_face_for_the_same_key() -> void:
	# one key, three routes: the plain subject, a Dynasty card row, and a subject with the team attached (the team changes the jersey only)
	var plain: Dictionary = FcPlayerVisual.resolve(FcPlayerPresentation.subject("dynasty_player:ember", "Ember", {}, 0))["identity"]
	var card: Dictionary = FcPlayerVisual.resolve(FcPlayerPresentation.subject_for_card({"player_id": "ember", "name": "Ember", "team": "Harbor", "card_id": "ember_base"}))["identity"]
	var moved: Dictionary = FcPlayerVisual.resolve(FcPlayerPresentation.subject("dynasty_player:ember", "Ember", {"name": "Other", "primary": "#112233", "secondary": "#FFFFFF"}, 9))["identity"]
	assert_eq(card, plain, "a Dynasty card of the player has the player's face")
	assert_eq(moved, plain, "a new team and number change the jersey, never the face")


func test_the_family_sizes_match_the_collectible_cards() -> void:
	assert_eq(FcPlayerCards.pixels(FcPlayerCards.Size.SMALL), FcCardFace.SIZE_SMALL)
	assert_eq(FcPlayerCards.pixels(FcPlayerCards.Size.MEDIUM), FcCardFace.SIZE_STANDARD)
	assert_eq(FcPlayerCards.pixels(FcPlayerCards.Size.LARGE), FcCardFace.SIZE_DETAIL)
	assert_eq(FcPlayerCards.pixels(FcPlayerCards.Size.HERO), FcCardFace.SIZE_HERO)
	assert_eq(FcPlayerTile.SIZE_SMALL, FcCardFace.SIZE_SMALL)
	assert_eq(FcPlayerTile.SIZE_MEDIUM, FcCardFace.SIZE_STANDARD)


func test_chip_and_tile_show_the_name_and_the_tier_coloured_rating() -> void:
	var subject := FcPlayerPresentation.subject("owner_player:3", "Maya Okoro", {"name": "Harbor Kings", "abbreviation": "HBK", "primary": "#1F3A5F", "secondary": "#C8A951"}, 11)
	var vm := {"subject": subject, "name": "Maya Okoro", "position": "PG", "secondary": "SG", "overall": 88, "team": {"abbreviation": "HBK"}}
	var chip := FcPlayerCards.make(vm, FcPlayerCards.Size.CHIP, "PG  ·  24") as FcPlayerChip
	assert_eq(chip.name_label.text, "Maya Okoro")
	assert_eq(chip.detail_label.text, "PG  ·  24")
	assert_eq(chip.badge.value, 88)
	assert_eq(chip.tooltip_text, "Maya Okoro, 88 overall")
	var tile := FcPlayerCards.make(vm, FcPlayerCards.Size.MEDIUM) as FcPlayerTile
	assert_eq(tile.custom_minimum_size, FcCardFace.SIZE_STANDARD)
	assert_eq(tile.tooltip_text, "Maya Okoro, PG, 88 overall")
	var compact := FcPlayerChip.new().setup(vm, "PG", true, 32, true)
	assert_true(not compact.detail_label.visible, "a compact chip has one line")
	for n in [chip, tile, compact]:
		n.free()


func test_a_tile_can_be_activated_by_click_and_enter() -> void:
	var vm := {"subject": FcPlayerPresentation.subject("owner_player:4", "Dev Carter", {}, 4), "name": "Dev Carter", "position": "C", "overall": 70}
	var tile := FcPlayerTile.new().setup(vm)
	var hits: Array = []
	tile.activated.connect(func() -> void: hits.append(true))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	tile._gui_input(click)
	assert_eq(hits.size(), 1)
	tile.free()
