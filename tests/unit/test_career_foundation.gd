extends FcTestCase
## Career Mode foundation (phase 1): the shared player build rules, archetypes, the career profile, saving and the
## version 1 to 2 migration. Nothing here touches Owner Mode.

var defs: FcDefinitionSet


func before_each() -> void:
	defs = FcDefinitionSet.load_default()


func _named(spec: Dictionary) -> Dictionary:
	spec["first_name"] = "Jordan"
	spec["last_name"] = "Vale"
	spec["jersey_number"] = 7
	return spec


func _good(archetype: String = "floor_general", position: int = 1) -> Dictionary:
	return _named(FcPlayerBuild.default_spec(archetype, position, defs))


func _world(seed_value: int = 920) -> FcWorld:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 10
	return FcWorldGenerator.new(data, defs, cfg).generate(seed_value)


# --- archetypes and rules ------------------------------------------------------------------------

func test_every_archetype_is_valid_data_and_its_default_build_passes_validation() -> void:
	assert_true(FcArchetypes.keys().size() >= 10, "the brief's examples plus custom")
	for key in FcArchetypes.keys():
		var a := FcArchetypes.get_archetype(key)
		assert_true(not (a["positions"] as Array).is_empty(), "%s suits some position" % key)
		for attr in a["bonus"]:
			assert_true(defs.attributes.has_key(attr), "%s uses a real attribute (%s)" % [key, attr])
		for position in a["positions"]:
			var spec := _good(key, int(position))
			var errors := FcPlayerBuild.validate(spec, defs)
			assert_eq(errors, [] as Array[String], "%s at position %d: %s" % [key, position, str(errors)])
			assert_true(FcPlayerBuild.budget_used(spec["attributes"]) <= int(FcBuildRules.rules()["budget_points"]), "%s fits the budget" % key)


func test_a_hybrid_build_is_just_changed_attributes_and_stays_valid() -> void:
	var spec := _good("floor_general", 1)
	spec["attributes"]["three_point"] = 70   # a point guard who also shoots: a hybrid, no new archetype needed
	spec["attributes"]["passing"] = 60
	assert_eq(FcPlayerBuild.validate(spec, defs), [] as Array[String])


func test_the_rules_come_from_data_and_carry_a_version() -> void:
	assert_eq(FcPlayerBuild.ruleset_version(), int(FcBuildRules.rules()["ruleset_version"]))
	assert_eq(int(FcBuildRules.rules()["attribute_floor"]), 25)
	assert_eq(int(FcBuildRules.rules()["attribute_cap"]), 99)


# --- validation boundaries -----------------------------------------------------------------------

func test_names_positions_hand_number_and_appearance_are_checked() -> void:
	var spec := _good()
	spec["first_name"] = ""
	spec["last_name"] = "x".repeat(40)
	spec["position"] = 9
	spec["secondary_position"] = 9
	spec["handedness"] = 5
	spec["jersey_number"] = 100
	spec["archetype"] = "nonsense"
	spec["country"] = ""
	spec["country"] = ""
	spec["appearance"] = {"skin": "purple"}
	var text := " | ".join(FcPlayerBuild.validate(spec, defs))
	for fragment in ["first name is required", "last name can be at most", "choose a position", "secondary position is not valid", "dominant hand", "jersey number", "unknown archetype", "choose a country", "skin option", "hair option"]:
		assert_true(fragment in text, "reports: %s" % fragment)
	spec = _good()
	spec["secondary_position"] = spec["position"]
	assert_true("must differ" in " ".join(FcPlayerBuild.validate(spec, defs)))
	spec["secondary_position"] = 2
	assert_eq(FcPlayerBuild.validate(spec, defs), [] as Array[String], "a different secondary position is fine")


func test_physical_limits_and_proportions() -> void:
	for case in [["height_cm", 150, "height must be"], ["height_cm", 240, "height must be"], ["weight_kg", 40, "weight must be"], ["wingspan_cm", 300, "wingspan must be"]]:
		var spec := _good()
		spec[case[0]] = case[1]
		assert_true(case[2] in " ".join(FcPlayerBuild.validate(spec, defs)), "%s %d" % [case[0], case[1]])
	var odd := _good()
	odd["wingspan_cm"] = int(odd["height_cm"]) + 30
	assert_true("compared with height" in " ".join(FcPlayerBuild.validate(odd, defs)), "arms far longer than the body allows")
	var heavy := _good()
	heavy["height_cm"] = 170
	heavy["wingspan_cm"] = 175
	heavy["weight_kg"] = 150
	assert_true("does not fit the height" in " ".join(FcPlayerBuild.validate(heavy, defs)), "body mass index")


func test_attribute_floor_cap_and_unknown_keys() -> void:
	var spec := _good()
	spec["attributes"]["layups"] = 24
	spec["attributes"]["dunking"] = 90
	spec["attributes"]["bogus"] = 50
	spec["attributes"].erase("blocks")
	var text := " | ".join(FcPlayerBuild.validate(spec, defs))
	assert_true("layups must be 25-85" in text and "dunking must be 25-85" in text and "unknown attribute bogus" in text and "attribute blocks is missing" in text)


func test_the_point_budget_is_enforced_and_saving_points_buys_others() -> void:
	var spec := _good("custom", 3)
	var budget := int(FcBuildRules.rules()["budget_points"])
	var attrs: Dictionary = spec["attributes"]
	var keys: Array = attrs.keys()
	var spend := 0
	for key in keys:   # raise everything to the same level until the budget is gone
		attrs[key] = 40 + 15
		spend += 15
	assert_true(spend > budget)
	assert_true("only %d are available" % budget in " ".join(FcPlayerBuild.validate(spec, defs)))
	for key in keys.slice(0, 10):   # lowering some attributes frees points for others
		attrs[key] = 30
	assert_eq(FcPlayerBuild.validate(spec, defs), [] as Array[String], "10 attributes 10 below the baseline pay for the rest")


func test_potential_is_capped_by_the_body_and_sets_attribute_ceilings() -> void:
	var small := _good("floor_general", 1)
	small["height_cm"] = 175
	small["wingspan_cm"] = 178
	small["weight_kg"] = 72
	var tall := _good("rim_protector", 5)
	tall["height_cm"] = 220
	tall["wingspan_cm"] = 232
	tall["weight_kg"] = 125
	assert_true(FcPlayerBuild.potential_cap(small) < FcPlayerBuild.potential_cap(tall), "a bigger frame allows a higher ceiling")
	small["potential"] = FcPlayerBuild.potential_cap(small) + 1
	assert_true("allows a potential of at most" in " ".join(FcPlayerBuild.validate(small, defs)))
	# the body bends the ceilings: a tall player blocks higher and is slower; a small one handles higher
	assert_true(FcPlayerBuild.attribute_ceiling("blocks", tall) > FcPlayerBuild.attribute_ceiling("blocks", small))
	assert_true(FcPlayerBuild.attribute_ceiling("speed", tall) < FcPlayerBuild.attribute_ceiling("speed", small))
	assert_true(FcPlayerBuild.attribute_ceiling("ball_handling", small) > FcPlayerBuild.attribute_ceiling("ball_handling", tall))
	# higher potential raises every ceiling, and no ceiling leaves the allowed range
	var low := _good()
	low["potential"] = 45
	var high := _good()
	high["potential"] = 90
	for key in defs.attributes.keys():
		assert_true(FcPlayerBuild.attribute_ceiling(key, high) >= FcPlayerBuild.attribute_ceiling(key, low), key)
		assert_between(FcPlayerBuild.attribute_ceiling(key, high), 45, 99, key)


func test_a_start_value_above_the_ceiling_is_refused() -> void:
	var spec := _good("custom", 5)
	spec["height_cm"] = 215
	spec["wingspan_cm"] = 220
	spec["attributes"]["speed"] = 85
	spec["potential"] = 40
	var ceiling := FcPlayerBuild.attribute_ceiling("speed", spec)
	assert_true(ceiling < 85)
	assert_true("speed cannot start above %d" % ceiling in " ".join(FcPlayerBuild.validate(spec, defs)))


func test_validation_never_throws_on_garbage() -> void:
	for spec in [{}, {"attributes": 5}, {"appearance": 3, "attributes": {}}, {"height_cm": "tall", "position": null}]:
		assert_true(not FcPlayerBuild.validate(spec, defs).is_empty())


# --- creating the player ---------------------------------------------------------------------------

func test_a_valid_build_becomes_a_real_player_and_a_profile_with_a_stable_id() -> void:
	var w := _world()
	var spec := _good("sharpshooter", 3)
	var made := FcPlayerBuild.create(w, spec, 2026, FcRng.new(5))
	assert_true(made.has("player") and made.has("profile"), str(made.get("errors", "")))
	var p: FcPlayer = made["player"]
	var profile: FcCareerProfile = made["profile"]
	assert_eq(w.players.get_by_id(p.id), p)
	assert_eq(p.identity.full_name(), "Jordan Vale")
	assert_eq(p.age_on(FcDate.new(2026, 7, 1)), 19)
	assert_eq(p.physical.wingspan_cm, int(spec["wingspan_cm"]))
	assert_eq(p.attributes.get_value("three_point"), int(spec["attributes"]["three_point"]))
	assert_eq(p.development.potential, int(spec["potential"]))
	assert_true(FcCareerProfile.is_valid_profile_id(profile.profile_id))
	assert_eq(profile.player_id, p.id)
	assert_eq(profile.archetype_key, "sharpshooter")
	assert_eq(profile.build_version, FcPlayerBuild.ruleset_version())
	assert_eq(profile.validate(), [] as Array[String])
	assert_eq(p.validate(), [] as Array[String], "an ordinary valid FcPlayer: no second player type")
	assert_eq(w.validate(2026), [] as Array[String], "the world stays valid with a new free agent in it")
	var again := FcPlayerBuild.create(_world(), spec, 2026, FcRng.new(5))
	assert_eq(again["profile"].profile_id, profile.profile_id, "the same seed gives the same id")
	assert_true(FcPlayerBuild.create(_world(), spec, 2026, FcRng.new(6))["profile"].profile_id != profile.profile_id, "another seed another id")


func test_an_invalid_build_creates_nothing() -> void:
	var w := _world()
	var before := w.players.count()
	var spec := _good()
	spec["first_name"] = ""
	var made := FcPlayerBuild.create(w, spec, 2026, FcRng.new(1))
	assert_true(made.has("errors") and not made.has("player"))
	assert_eq(w.players.count(), before)


# --- the profile record ----------------------------------------------------------------------------

func test_profile_ids_are_well_formed_and_validated() -> void:
	assert_true(FcCareerProfile.is_valid_profile_id("fcp_0123456789abcdef"))
	for bad in ["", "fcp_123", "xxx_0123456789abcdef", "fcp_0123456789abcdeg", "fcp_0123456789ABCDEF"]:
		assert_true(not FcCareerProfile.is_valid_profile_id(bad), bad)
	var rng := FcRng.new(77)
	var ids := {}
	for i in 200:
		ids[FcCareerProfile.make_profile_id(rng)] = true
	assert_eq(ids.size(), 200, "ids do not repeat")


func test_profile_validation_catches_bad_progression_state() -> void:
	var p := FcCareerProfile.new()
	p.profile_id = "fcp_0123456789abcdef"
	p.player_id = 5
	assert_eq(p.validate(), [] as Array[String])
	p.xp = -1
	p.badges_equipped = ["catch_and_shoot"]
	var text := " ".join(p.validate())
	assert_true("cannot be negative" in text and "equipped but not owned" in text)
	p.xp = 0
	p.badges_owned = ["a", "b", "c", "d", "e", "f"]
	p.badges_equipped = ["a", "b", "c", "d", "e", "f"]
	assert_true("at most 5 badges" in " ".join(p.validate()))
	p.stage = 99
	assert_true("stage" in " ".join(p.validate()))


func test_profile_round_trips_through_json_and_has_a_stable_checksum() -> void:
	var p := FcCareerProfile.new()
	p.profile_id = FcCareerProfile.make_profile_id(FcRng.new(3))
	p.player_id = 12
	p.archetype_key = "post_scorer"
	p.appearance = {"skin": "tone_2", "hair": "fade"}
	p.jersey_number = 23
	p.stage = FcCareerProfile.Stage.PROFESSIONAL
	p.xp = 1234
	p.level = 6
	p.development_points = 4
	p.skill_points = 2
	p.reputation = 31
	p.currency = 900
	p.badges_owned = ["rebound_chaser"]
	p.badges_equipped = ["rebound_chaser"]
	p.decisions = [{"year": 2027, "key": "agent", "choice": "veteran"}]
	p.history = [{"year": 2026, "team_id": 3, "games": 70, "points": 12.5}]
	p.owner_account = "acct_x"
	var through_json := FcCareerProfile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_eq(through_json.to_dict(), p.to_dict())
	assert_eq(through_json.checksum(), p.checksum())
	through_json.xp += 1
	assert_true(through_json.checksum() != p.checksum(), "any change changes the fingerprint")
	assert_eq(FcCareerProfile.from_dict({}).level, 1, "defaults for missing fields")


# --- saving, versions and migration ------------------------------------------------------------------

func test_a_career_state_saves_and_reloads_with_its_player_and_profile() -> void:
	var w := _world()
	var made := FcPlayerBuild.create(w, _good("point_forward", 3), 2026, FcRng.new(9))
	var state := FcGameState.new(w, FcRng.new(1))
	state.mode = FcGameState.MODE_CAREER
	state.user_team_id = 0
	state.career_profiles.append(made["profile"])
	assert_eq(state.validate(), [] as Array[String], str(state.validate()))
	var back := FcGameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), defs)
	assert_eq(back.mode, FcGameState.MODE_CAREER)
	assert_eq(back.career_profiles.size(), 1)
	assert_eq(back.career_profiles[0].checksum(), made["profile"].checksum())
	assert_eq(back.validate(), [] as Array[String])
	var reloaded: FcPlayer = back.world.players.get_by_id(made["player"].id)
	assert_eq(reloaded.attributes.to_dict(), made["player"].attributes.to_dict(), "the player's attributes survive")


## D-041 contract: profile_id is text and only unique inside one save (it is deterministic from the seed), while player_id is the
## world's integer id and still resolves after a save round trip.
func test_profile_id_contract_text_id_and_integer_player_id_survive_a_save() -> void:
	var made := FcPlayerBuild.create(_world(), _good("point_forward", 3), 2026, FcRng.new(9))
	var profile: FcCareerProfile = made["profile"]
	assert_true(typeof(profile.profile_id) == TYPE_STRING, "profile_id is text")
	assert_true(typeof(profile.player_id) == TYPE_INT, "player_id is the world's integer id")
	var state := FcGameState.new(_world(), FcRng.new(1))
	var made2 := FcPlayerBuild.create(state.world, _good("point_forward", 3), 2026, FcRng.new(9))
	assert_eq(made2["profile"].profile_id, profile.profile_id, "the same seed in another world repeats the id: unique per save, not global")
	state.mode = FcGameState.MODE_CAREER
	state.user_team_id = 0
	state.career_profiles.append(made2["profile"])
	var back := FcGameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), defs)
	var again: FcCareerProfile = back.career_profiles[0]
	assert_eq(again.profile_id, profile.profile_id, "the text id survives the save unchanged")
	assert_eq(again.player_id, made2["player"].id)
	assert_true(back.world.players.get_by_id(again.player_id) != null, "the integer player id still resolves after reload")


func test_state_validation_catches_a_profile_without_a_player_and_duplicate_ids() -> void:
	var w := _world()
	var made := FcPlayerBuild.create(w, _good(), 2026, FcRng.new(2))
	var state := FcGameState.new(w, FcRng.new(1))
	state.mode = FcGameState.MODE_CAREER
	var profile: FcCareerProfile = made["profile"]
	state.career_profiles.append(profile)
	state.career_profiles.append(FcCareerProfile.from_dict(profile.to_dict()))
	assert_true("used twice" in " ".join(state.validate()))
	state.career_profiles.clear()
	profile.player_id = 999999
	state.career_profiles.append(profile)
	assert_true("does not exist" in " ".join(state.validate()))


func test_owner_mode_states_do_not_carry_or_need_career_data() -> void:
	var w := _world()
	var owner := FcGameState.new(w, FcRng.new(1))
	owner.user_team_id = w.teams.ids()[0]
	assert_eq(owner.mode, FcGameState.MODE_OWNER)
	assert_eq(owner.validate(), [] as Array[String])
	assert_eq(FcGameState.from_dict(JSON.parse_string(JSON.stringify(owner.to_dict())), defs).career_profiles.size(), 0)


func test_the_data_version_is_current_and_a_version_one_save_migrates_to_it() -> void:
	assert_eq(FcVersion.DATA_VERSION, 5, "version 4 added the public image and timeline (see test_career_public); version 5 the Franchise Experience data (D-077)")
	var dir := "user://test_saves_career"
	var old := FcSaveManager.new(dir)
	old.current_data_version = 1   # an old game wrote this
	var w := _world()
	var state := FcGameState.new(w, FcRng.new(1))
	state.user_team_id = w.teams.ids()[0]
	assert_true(old.save("slot_1", state).is_ok())
	var current := FcSaveManager.new(dir)
	var r := current.load_slot("slot_1", defs)
	assert_true(r.is_ok(), r.message)
	assert_eq(r.state.career_profiles.size(), 0, "the migration adds an empty career section")
	assert_eq(r.state.user_team_id, state.user_team_id)
	var migrated := FcSaveMigrator.new().migrate({"mode": "owner"}, 1, 2)
	assert_true(migrated["ok"] and migrated["payload"].has("career_profiles"))
	var d := DirAccess.open(dir)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(dir)
