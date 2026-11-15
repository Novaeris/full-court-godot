extends FcTestCase


func test_valid_team_passes_validation() -> void:
	assert_eq(FcTestData.team(1, 1, 1).validate(), [] as Array[String])


func test_team_display_name() -> void:
	var t := FcTestData.team(1, 1, 1)
	assert_eq(t.identity.display_name("Harbor City"), "Harbor City Testers")


func test_invalid_team_data_reported() -> void:
	var t := FcTestData.team(0, 0, 0)
	t.identity.nickname = ""
	t.identity.abbreviation = "toolong"
	t.branding.primary_color = "blue"
	t.owner_id = -1
	assert_true(t.validate().size() >= 7, str(t.validate()))


func test_abbreviation_and_color_rules() -> void:
	assert_true(FcChecks.is_abbreviation("HB"))
	assert_true(FcChecks.is_abbreviation("HBRS"))
	assert_true(not FcChecks.is_abbreviation("H"))
	assert_true(not FcChecks.is_abbreviation("hbr"))
	assert_true(FcChecks.is_hex_color("#a1B2c3"))
	assert_true(not FcChecks.is_hex_color("a1b2c3"))
	assert_true(not FcChecks.is_hex_color("#12345"))


func test_roster_add_remove_and_limits() -> void:
	var r := FcRoster.new()
	r.max_size = 2
	assert_eq(r.add(10), OK)
	assert_eq(r.add(10), ERR_ALREADY_EXISTS)
	assert_eq(r.add(0), ERR_INVALID_PARAMETER)
	assert_eq(r.add(11), OK)
	assert_true(r.is_full())
	assert_eq(r.add(12), ERR_PARAMETER_RANGE_ERROR, "full roster")
	assert_eq(r.remove(99), ERR_DOES_NOT_EXIST)
	assert_eq(r.remove(10), OK)
	assert_eq(r.size(), 1)
	assert_true(not r.contains(10))


func test_roster_validation_catches_bad_loaded_data() -> void:
	var r := FcRoster.from_dict({"max_size": 2, "player_ids": [1, 1, 2, 3, -4]})
	assert_true(r.validate().size() >= 3, "duplicate, overflow, invalid id")


func test_team_round_trip() -> void:
	var t := FcTestData.team(4, 2, 3)
	t.owner_id = 9
	t.identity.founded_year = 1985
	t.branding.logo_key = "kings_v2"
	t.roster.add(5)
	t.roster.add(6)
	var copy := FcTeam.from_dict(t.to_dict())
	assert_eq(copy.to_dict(), t.to_dict())
	assert_eq(copy.roster.player_ids, [5, 6] as Array[int])


func test_city_and_arena_validation_and_round_trip() -> void:
	var c := FcTestData.city(1)
	assert_eq(c.validate(), [] as Array[String])
	c.population = 5
	c.economy_index = 101
	assert_eq(c.validate().size(), 2)
	var a := FcTestData.arena(1, 1)
	assert_eq(a.validate(), [] as Array[String])
	assert_eq(FcArena.from_dict(a.to_dict()).to_dict(), a.to_dict())
	a.capacity = 10
	a.city_id = 0
	assert_eq(a.validate().size(), 2)
	assert_eq(FcCity.from_dict(FcTestData.city(3).to_dict()).to_dict(), FcTestData.city(3).to_dict())
