extends FcTestCase


func test_valid_state_and_team_name() -> void:
	var s := FcTestData.game_state()
	assert_eq(s.validate(), [] as Array[String])
	assert_eq(s.user_team_name(), "Testville Testers")


func test_invalid_state_is_reported() -> void:
	var s := FcTestData.game_state()
	s.mode = "arcade"
	s.user_team_id = 99
	s.current_date = FcDate.new(2026, 2, 30)
	assert_eq(s.validate().size(), 3)
	assert_eq(s.user_team_name(), "")


func test_round_trip_including_random_position() -> void:
	var s := FcTestData.game_state()
	s.mode = FcGameState.MODE_DYNASTY
	s.current_season = 2031
	s.current_date = FcDate.new(2031, 11, 3)
	for i in 25:
		s.rng.next_float()
	var errors: Array[String] = []
	var copy := FcGameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())), FcTestData.defs(), errors)
	assert_eq(errors, [] as Array[String])
	assert_eq(copy.to_dict(), s.to_dict())
	assert_eq(copy.rng.next_float(), s.rng.next_float(), "random stream continues identically")
	assert_eq(copy.current_date.to_iso(), "2031-11-03")


func test_missing_rng_is_reported() -> void:
	var data := FcTestData.game_state().to_dict()
	data.erase("rng")
	var errors: Array[String] = []
	FcGameState.from_dict(data, FcTestData.defs(), errors)
	assert_eq(errors.size(), 1)


func test_agreed_extensions_are_saved_and_old_saves_default() -> void:
	var g := FcGameState.new(FcWorld.new(FcDefinitionSet.load_default()), FcRng.new(1))
	g.agreed_extensions = [4, 9] as Array[int]
	var back := FcGameState.from_dict(JSON.parse_string(JSON.stringify(g.to_dict())), FcDefinitionSet.load_default())
	assert_eq(back.agreed_extensions, [4, 9] as Array[int])
	var old := g.to_dict()
	old.erase("agreed_extensions")
	assert_eq(FcGameState.from_dict(old, FcDefinitionSet.load_default()).agreed_extensions, [] as Array[int])
