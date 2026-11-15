extends FcTestCase


func _has_error_containing(errors: Array[String], text: String) -> bool:
	for e in errors:
		if text in e:
			return true
	return false


func test_sample_world_is_healthy() -> void:
	var w := FcTestData.world()
	assert_eq(w.validate(), [] as Array[String])
	assert_eq(w.players.count(), 2)
	assert_eq(w.team_of_player(1).id, 1)
	assert_eq(w.active_contract_of(2).player_id, 2)


func test_free_agent_has_no_team() -> void:
	var w := FcTestData.world()
	w.players.add(FcTestData.player(w.ids.next_id(FcWorld.KIND_PLAYER), w.definitions))
	assert_true(w.team_of_player(3) == null)
	assert_true(w.active_contract_of(3) == null)
	assert_eq(w.validate(), [] as Array[String], "free agents are legal")


func test_detects_dangling_references() -> void:
	var w := FcTestData.world()
	w.contracts.add(FcTestData.contract(50, 999, 1))
	w.contracts.add(FcTestData.contract(51, 1, 888))
	w.teams.get_by_id(1).city_id = 777
	w.teams.get_by_id(1).arena_id = 666
	w.arenas.get_by_id(1).city_id = 555
	var errors := w.validate()
	assert_true(_has_error_containing(errors, "player 999 does not exist"))
	assert_true(_has_error_containing(errors, "team 888 does not exist"))
	assert_true(_has_error_containing(errors, "city 777 does not exist"))
	assert_true(_has_error_containing(errors, "arena 666 does not exist"))
	assert_true(_has_error_containing(errors, "city 555 does not exist"))


func test_detects_roster_problems() -> void:
	var w := FcTestData.world()
	# second team that also claims player 1
	w.cities.add(FcTestData.city(2))
	w.arenas.add(FcTestData.arena(2, 2))
	var t2 := FcTestData.team(2, 2, 2)
	t2.roster.add(1)
	t2.roster.add(404)
	w.teams.add(t2)
	var errors := w.validate()
	assert_true(_has_error_containing(errors, "is on rosters of teams"), "double roster")
	assert_true(_has_error_containing(errors, "roster player 404 does not exist"))
	assert_true(_has_error_containing(errors, "no active contract with this team"), "wrong team contract")


func test_detects_rostered_player_without_contract_or_retired() -> void:
	var w := FcTestData.world()
	w.contracts.get_by_id(1).status = FcContract.Status.EXPIRED
	w.players.get_by_id(2).status = FcPlayer.Status.RETIRED
	w.players.get_by_id(2).retired_season = 2030
	var errors := w.validate()
	assert_true(_has_error_containing(errors, "roster player 1 has no active contract"))
	assert_true(_has_error_containing(errors, "roster player 2 is retired"))


func test_detects_two_active_contracts_for_one_player() -> void:
	var w := FcTestData.world()
	w.contracts.add(FcTestData.contract(60, 1, 1))
	assert_true(_has_error_containing(w.validate(), "more than one active contract"))


func test_expired_contract_history_is_allowed() -> void:
	var w := FcTestData.world()
	var old := FcTestData.contract(70, 1, 1)
	old.status = FcContract.Status.EXPIRED
	w.contracts.add(old)
	assert_eq(w.validate(), [] as Array[String], "past contracts do not conflict")
	assert_eq(w.active_contract_of(1).id, 1)


func test_entity_validation_errors_are_labeled() -> void:
	var w := FcTestData.world()
	w.players.get_by_id(1).physical.height_cm = 10
	assert_true(_has_error_containing(w.validate(), "player 1:"))


func test_world_round_trip_preserves_everything() -> void:
	var w := FcTestData.world()
	w.players.get_by_id(1).attributes.set_value("speed", 93)
	var load_errors: Array[String] = []
	var copy := FcWorld.from_dict(w.to_dict(), w.definitions, load_errors)
	assert_eq(load_errors, [] as Array[String])
	assert_eq(copy.to_dict(), w.to_dict())
	assert_eq(copy.validate(), [] as Array[String])
	assert_eq(copy.players.get_by_id(1).attributes.get_value("speed"), 93)
	assert_eq(copy.ids.next_id(FcWorld.KIND_PLAYER), 3, "no id reuse after load")


func test_snapshot_survives_json_text() -> void:
	# Real saves will be text/binary on disk; make sure nothing is lost via JSON.
	var w := FcTestData.world()
	var text := JSON.stringify(w.to_dict())
	var parsed = JSON.parse_string(text)
	var copy := FcWorld.from_dict(parsed, w.definitions)
	assert_eq(copy.validate(), [] as Array[String])
	assert_eq(copy.players.count(), 2)
	assert_eq(copy.contracts.get_by_id(1).total_value(), w.contracts.get_by_id(1).total_value())


func test_loading_duplicate_ids_is_reported() -> void:
	var w := FcTestData.world()
	var data := w.to_dict()
	data["players"].append(data["players"][0].duplicate(true))
	var errors: Array[String] = []
	FcWorld.from_dict(data, w.definitions, errors)
	assert_eq(errors.size(), 1)
