extends FcTestCase

var defs: FcDefinitionSet


func before_each() -> void:
	defs = FcDefinitionSet.load_default()


func test_valid_player_passes_validation() -> void:
	var p := FcTestData.player(1, defs)
	assert_eq(p.validate(), [] as Array[String])
	assert_eq(p.identity.full_name(), "Test Player1")


func test_age_on_date() -> void:
	var p := FcTestData.player(1, defs)
	assert_eq(p.age_on(FcDate.new(2026, 5, 16)), 24)
	assert_eq(p.age_on(FcDate.new(2026, 5, 17)), 25)


func test_invalid_values_are_reported() -> void:
	var p := FcTestData.player(0, defs)
	p.identity.first_name = "  "
	p.identity.country = ""
	p.identity.birth_date = FcDate.new(2001, 2, 30)
	p.physical.height_cm = 300
	p.physical.weight_kg = 10
	p.development.potential = 101
	p.development.volatility = 2.0
	p.primary_position = FcPosition.Id.NONE
	var errors := p.validate()
	assert_true(errors.size() >= 8, "expected many problems, got %d: %s" % [errors.size(), str(errors)])


func test_secondary_position_rules() -> void:
	var p := FcTestData.player(1, defs)
	p.secondary_position = p.primary_position
	assert_true(not p.validate().is_empty(), "same as primary")
	p.secondary_position = FcPosition.Id.SG
	assert_eq(p.validate(), [] as Array[String])
	p.secondary_position = 9
	assert_true(not p.validate().is_empty(), "invalid position")


func test_retirement_consistency() -> void:
	var p := FcTestData.player(1, defs)
	p.status = FcPlayer.Status.RETIRED
	assert_true(not p.validate().is_empty(), "retired without season")
	p.retired_season = 2040
	assert_eq(p.validate(), [] as Array[String])
	p.status = FcPlayer.Status.ACTIVE
	assert_true(not p.validate().is_empty(), "season on active player")


func test_round_trip() -> void:
	var p := FcTestData.player(7, defs)
	p.identity.nickname = "Ace"
	p.physical.handedness = FcPlayerPhysical.Handedness.LEFT
	p.secondary_position = FcPosition.Id.SG
	p.development.potential = 88
	p.development.development_rate = 1.25
	p.attributes.set_value("three_point", 91)
	p.personality.set_value("loyalty", 12)
	p.tendencies.set_value("drive_tendency", 77)
	var copy := FcPlayer.from_dict(p.to_dict(), defs)
	assert_eq(copy.to_dict(), p.to_dict(), "round trip identical")
	assert_eq(copy.attributes.get_value("three_point"), 91)
	assert_eq(copy.identity.birth_date.to_iso(), "2001-05-17")
	assert_eq(copy.validate(), [] as Array[String])


func test_float_fields_survive_json_exactly() -> void:
	# Regression: raw doubles lose their last bits in JSON text.
	var rng := FcRng.new(99)
	for i in 200:
		var p := FcTestData.player(1, defs)
		p.development.development_rate = rng.range_float(0.5, 1.5)
		p.development.volatility = rng.range_float(0.0, 1.0)
		var copy := FcPlayer.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())), defs)
		assert_eq(copy.development.development_rate, p.development.development_rate, "rate %d" % i)
		assert_eq(copy.development.volatility, p.development.volatility, "volatility %d" % i)


func test_quantize() -> void:
	assert_eq(FcChecks.quantize(0.95715457201004), 0.957)
	assert_eq(FcChecks.quantize(1.0), 1.0)
	assert_eq(FcChecks.quantize(1.23456, 2), 1.23)


func test_loading_sparse_old_save_uses_defaults() -> void:
	var p := FcPlayer.from_dict({"id": 3, "identity": {"first_name": "A", "last_name": "B", "country": "C", "birth_date": "1999-01-01"}}, defs)
	assert_eq(p.attributes.get_value("speed"), 50, "missing attributes default")
	assert_eq(p.physical.height_cm, 198, "missing physical defaults")
	assert_eq(p.validate(), [] as Array[String])


func test_corrupt_birth_date_is_reported_not_crashed() -> void:
	var p := FcPlayer.from_dict({"id": 3, "identity": {"first_name": "A", "last_name": "B", "country": "C", "birth_date": "garbage"}}, defs)
	assert_true(not p.validate().is_empty())


func test_player_holds_no_contract_or_team() -> void:
	var d := FcTestData.player(1, defs).to_dict()
	assert_true(not d.has("contract") and not d.has("team_id") and not d.has("salary"), "relationships live outside the player")
