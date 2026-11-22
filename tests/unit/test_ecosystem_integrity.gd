extends FcTestCase
## Cross-mode integrity (Phase 1): the three modes must agree on definitions, position rules and rating calculations, and every
## reference in the bundled content and the shared data files must resolve. Owner and Career use the canonical FcPlayer; Dynasty
## keeps published player definitions and card editions and BUILDS FcPlayer instances for simulation (FcDynastyCatalog.make_player),
## so the checks here compare those two paths rather than demanding one shared instance.
## The scene-level cycle between the modes is in tests/live/test_live_mode_transitions.gd.

const DIR := "user://test_ecosystem"

var defs: FcDefinitionSet
var ctl: FcDynastyController


func before_each() -> void:
	FcSafeFile.remove_tree(DIR)
	defs = FcDefinitionSet.load_default()
	var prefs := FcPreferences.new(DIR.path_join("prefs.cfg"))
	prefs.content_root = DIR.path_join("content")
	var service := FcContentService.new(prefs, defs)
	ctl = FcDynastyController.new(service, defs, FcDynastyStore.new(DIR.path_join("profiles")))


func after_each() -> void:
	FcSafeFile.remove_tree(DIR)


# --- positions: one list, derived from FcPosition ------------------------------------------------------------------

func test_every_position_list_is_the_one_in_fc_position() -> void:
	var from_ids: Array = []
	for id in FcPosition.ABBREVIATIONS:
		if int(id) != FcPosition.Id.NONE:
			from_ids.append(FcPosition.ABBREVIATIONS[id])
	assert_eq(FcPosition.PLAYABLE, from_ids, "PLAYABLE is the abbreviation table without 'none', in id order")
	assert_eq(FcContentValidator.POSITIONS, FcPosition.PLAYABLE, "content validation")
	assert_eq(FcDynastyContentRules.STARTER_POSITIONS, FcPosition.PLAYABLE, "starter-lineup rule")
	assert_eq(FcDynastyScreensCollection.POSITIONS, [""] + FcPosition.PLAYABLE, "collection filter: 'any' plus the five")
	for slot in FcDynastyRoster.SLOT_POSITIONS.size():
		assert_eq(FcPosition.abbreviation(FcDynastyRoster.SLOT_POSITIONS[slot]), FcPosition.PLAYABLE[slot], "roster slot %d" % slot)
	for abbr in FcPosition.PLAYABLE:
		assert_true(FcPosition.is_valid(FcDynastyCatalog._position_id(abbr)), "%s parses to a real position id" % abbr)
		assert_eq(FcPosition.abbreviation(FcDynastyCatalog._position_id(abbr)), abbr, "%s round-trips" % abbr)


# --- one rating calculation ------------------------------------------------------------------------------------------

func test_dynasty_players_are_rated_by_the_same_calculation_as_owner_players() -> void:
	var catalog := ctl.catalog
	assert_true(catalog.is_playable(), "the bundled release loads: %s" % catalog.lineup_problem())
	var shared := FcPlayerRatings.load_default()
	var checked := 0
	for card_id in catalog.card_ids():
		var p := catalog.make_player(card_id, 1)
		assert_eq(p.validate(), [] as Array[String], "%s builds a valid FcPlayer: %s" % [card_id, str(p.validate())])
		assert_eq(roundi(shared.overall(p)), int(catalog.view(card_id)["overall"]), "%s: the card's overall is the shared rating" % card_id)
		# the FcPlayer survives the save round trip the other modes rely on, with the same rating
		var again := FcPlayer.from_dict(p.to_dict(), defs)
		assert_eq(roundi(shared.overall(again)), roundi(shared.overall(p)), "%s: rating survives a save round trip" % card_id)
		checked += 1
	assert_true(checked >= 40, "checked every bundled card (%d)" % checked)


func test_a_dynasty_player_and_a_generated_player_with_equal_attributes_rate_equally() -> void:
	var gen_data := FcGenerationData.load_default()
	var gen := FcPlayerGenerator.new(gen_data, defs)
	var owner_player := gen.generate(FcRng.new(4242), 1, FcPlayerSpec.new())
	assert_true(owner_player != null, "the Owner-mode generator produces a player")
	var card_id: String = ctl.catalog.card_ids()[0]
	var built := ctl.catalog.make_player(card_id, 2)
	# give the Owner-style player the card's published ratings: the rating must then match exactly
	for key in ctl.catalog.view(card_id)["attributes"]:
		owner_player.attributes.set_clamped(str(key), int(ctl.catalog.view(card_id)["attributes"][key]))
	var shared := FcPlayerRatings.load_default()
	assert_eq(shared.overall(owner_player), shared.overall(built), "the same attributes give the same rating in either mode")
	for key in defs.attributes.keys():
		assert_eq(owner_player.attributes.get_value(str(key)), built.attributes.get_value(str(key)), "%s agrees (one attribute definition set)" % key)


func test_dynasty_card_players_keep_their_published_positions() -> void:
	for card_id in ctl.catalog.card_ids():
		var v := ctl.catalog.view(card_id)
		var p := ctl.catalog.make_player(card_id, 1)
		assert_eq(FcPosition.abbreviation(p.primary_position), v["position"], "%s primary position" % card_id)
		if str(v["secondary"]) != "":
			assert_eq(FcPosition.abbreviation(p.secondary_position), v["secondary"], "%s secondary position" % card_id)
			assert_true(p.secondary_position != p.primary_position, "%s: secondary differs from primary" % card_id)


# --- shared data files agree with the definitions -----------------------------------------------------------------------

func test_attribute_keys_in_every_data_file_exist_in_the_definitions() -> void:
	var problems: Array[String] = []
	# bundled player definitions
	for path in _json_files("res://data/content_starter/players"):
		var d: Dictionary = FcSafeFile.read_json_object(path)
		for key in d.get("attributes", {}):
			if not defs.attributes.has_key(str(key)):
				problems.append("%s: unknown attribute %s" % [path, key])
		for key in d.get("tendencies", {}):
			if not defs.tendencies.has_key(str(key)):
				problems.append("%s: unknown tendency %s" % [path, key])
	# generation: position profiles
	var profiles: Dictionary = FcSafeFile.read_json_object("res://data/generation/position_profiles.json")
	for pos in profiles.get("positions", {}):
		for key in profiles["positions"][pos].get("offsets", {}):
			if not defs.attributes.has_key(str(key)):
				problems.append("position_profiles %s: unknown attribute %s" % [pos, key])
		for key in profiles["positions"][pos].get("tendency_offsets", {}):
			if not defs.tendencies.has_key(str(key)):
				problems.append("position_profiles %s: unknown tendency %s" % [pos, key])
	# career: archetype bonuses and badge requirements
	for a in FcArchetypes.all():
		for key in a.get("bonus", {}):
			if not defs.attributes.has_key(str(key)):
				problems.append("archetype %s: unknown attribute %s" % [a.get("key", "?"), key])
	for b in FcBadges.all():
		for key in b.get("requires", {}).get("attributes", {}):
			if not defs.attributes.has_key(str(key)):
				problems.append("badge %s: unknown attribute %s" % [b.get("key", "?"), key])
	assert_eq(problems, [] as Array[String], "every attribute key resolves: %s" % str(problems))


func test_badges_name_real_composites_and_prerequisites() -> void:
	var composites: Dictionary = FcPlayerRatings.load_default().compute(FcTestData.player(1, defs))
	var keys := FcBadges.keys()
	var problems: Array[String] = []
	for b in FcBadges.all():
		for effect in b.get("effects", {}):
			if not composites.has(str(effect)):
				problems.append("badge %s: effect '%s' is not a rating composite" % [b.get("key", "?"), effect])
		for need in b.get("requires", {}).get("badges", []):
			if not keys.has(str(need)):
				problems.append("badge %s: prerequisite '%s' does not exist" % [b.get("key", "?"), need])
	assert_eq(problems, [] as Array[String], str(problems))
	# every badge a bundled card or player carries is a real badge (Dynasty reads the Career badge list)
	for card_id in ctl.catalog.card_ids():
		for badge in ctl.catalog.view(card_id)["badges"]:
			assert_true(keys.has(str(badge)), "%s: badge %s is in data/career/badges.json" % [card_id, badge])


# --- the bundled Founding Series: reference closure -----------------------------------------------------------------------

func test_the_bundled_release_passes_the_shared_validator() -> void:
	var report := FcContentValidator.validate_release_dir("res://data/content_starter", FcVersion.GAME_VERSION, defs)
	assert_true(report.is_ok(), "the bundled release validates: %s %s" % [report.message, str(report.problems)])


func test_every_reference_in_the_bundled_release_resolves() -> void:
	var catalog := ctl.catalog
	var content := catalog.content
	for card_id in catalog.card_ids():
		assert_true(content.players.has(str(content.get_card(card_id).get("player_id", ""))), "%s: its player exists" % card_id)
	for pack_id in content.packs:
		for card_id in content.packs[pack_id].get("card_ids", []):
			assert_true(catalog.has_card(str(card_id)), "pack %s lists a real card (%s)" % [pack_id, card_id])
	for challenge_id in content.challenges:
		for card_id in content.challenges[challenge_id].get("rewards", {}).get("card_ids", []):
			assert_true(catalog.has_card(str(card_id)), "challenge %s rewards a real card (%s)" % [challenge_id, card_id])
	var config: Dictionary = content.support.get("dynasty_config", {})
	assert_true(content.packs.has(str(config.get("starter_pack_id", ""))), "the starter pack exists")
	assert_true(catalog.active_season_id() != "" and not catalog.season(catalog.active_season_id()).is_empty(), "an active season exists")


func test_the_economy_has_one_authoritative_source_per_key() -> void:
	# defaults live in data/dynasty/economy.json; the release's dynasty_config may override only keys that exist there
	var defaults: Dictionary = FcDynastyConfig.load_defaults()
	assert_true(not defaults.is_empty(), "economy defaults load")
	var override: Dictionary = ctl.catalog.content.support.get("dynasty_config", {})
	for key in override:
		assert_true(defaults.has(key) or FcDynastyConfig.NON_CONFIG_KEYS.has(key) or str(key).begins_with("starter_"),
			"dynasty_config key '%s' is a known default, a release field or a starter setting" % key)
	var built := FcDynastyConfig.build(override)
	for key in defaults:
		assert_true(built.values.has(key), "the built config answers '%s'" % key)


func _json_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			out.append(dir.path_join(f))
	return out


# --- invalid releases and stale profiles are handled, not trusted ---------------------------------------------------------

func _draft_problems_after(mutate: Callable) -> Array[String]:
	var dir := DIR.path_join("draft")
	FcSafeFile.remove_tree(dir)
	FcContentFixture.write_sample_content(dir)
	mutate.call(dir)
	return FcContentValidator.draft_problems(dir, defs)


func test_dangling_references_are_rejected_by_the_shared_validator() -> void:
	var clean := _draft_problems_after(func(_d): pass)
	assert_eq(clean, [] as Array[String], "the sample draft is clean to begin with: %s" % str(clean))
	var card := _draft_problems_after(func(d):
		var c: Dictionary = FcSafeFile.read_json_object(d.path_join("cards/sample_big_base.json"))
		c["player_id"] = "nobody_at_all"
		FcSafeFile.write_text(d.path_join("cards/sample_big_base.json"), JSON.stringify(c, "\t", true)))
	assert_true(not card.is_empty(), "a card pointing at a missing player is rejected")
	var pack := _draft_problems_after(func(d):
		var p: Dictionary = FcSafeFile.read_json_object(d.path_join("packs/starter_pack.json"))
		p["card_ids"] = ["sample_guard_base", "ghost_card"]
		FcSafeFile.write_text(d.path_join("packs/starter_pack.json"), JSON.stringify(p, "\t", true)))
	assert_true(not pack.is_empty(), "a pack listing a missing card is rejected")


func test_a_roster_card_missing_from_the_release_is_reported_and_skipped_safely() -> void:
	var env := FcDynastyEnv.make(31)
	var profile := env.profile()
	var original: String = str(profile.roster.slots[0])
	assert_true(original != "", "the automatic lineup filled slot 0")
	profile.cards["ghost_card"] = {"quantity": 1, "revision": 1, "snapshot": {}, "mastery": 0}
	profile.roster.slots[0] = "ghost_card"
	var problems := FcDynastyLineup.problems(profile, env.catalog)
	assert_true(str(problems).contains("not in the current content release"), "the lineup says why: %s" % str(problems))
	assert_true(not FcDynastyLineup.is_valid(profile, env.catalog), "an unavailable card makes the lineup invalid")
	var built := FcDynastyMatch.build_team(profile.roster.slots, [], env.catalog, FcDynastyMatch.USER_TEAM_ID, "Stale", "STL", 0)
	assert_eq((built["team"] as FcGameTeam).players.size(), FcDynastyRoster.SIZE - 1, "the missing card is skipped, no crash")
	assert_true(not (built["cards"] as Dictionary).has(1), "no simulated player is made for it")
	FcSafeFile.remove_tree(FcDynastyEnv.DIR)
