extends FcTestCase

var defs: FcDefinitionSet


func before_each() -> void:
	defs = FcDefinitionSet.load_default()


func _errors_contain(errors: Array[String], text: String) -> bool:
	for e in errors:
		if text in e:
			return true
	return false


func test_shipped_staff_definitions() -> void:
	assert_eq(defs.validate(), [] as Array[String])
	assert_eq(defs.staff_skills.size(), 17)
	assert_eq(defs.staff_skills.categories(), ["coaching", "front_office", "scouting", "business", "medical"] as Array[String])
	assert_eq(defs.philosophy.size(), 7)


func test_roles() -> void:
	assert_true(FcStaffRole.is_valid(FcStaffRole.Id.SCOUT))
	assert_true(not FcStaffRole.is_valid(FcStaffRole.Id.NONE))
	assert_true(not FcStaffRole.is_valid(7))
	assert_eq(FcStaffRole.display_name(FcStaffRole.Id.GENERAL_MANAGER), "General Manager")
	assert_true(FcStaffRole.is_unique_per_team(FcStaffRole.Id.HEAD_COACH))
	assert_true(not FcStaffRole.is_unique_per_team(FcStaffRole.Id.SCOUT))


func test_valid_staff_member() -> void:
	var s := FcTestData.staff(1, defs)
	assert_eq(s.validate(), [] as Array[String])
	assert_eq(s.age_on(FcDate.new(2026, 3, 8)), 50)
	assert_eq(s.age_on(FcDate.new(2026, 3, 9)), 51)


func test_invalid_staff_reported() -> void:
	var s := FcTestData.staff(0, defs)
	s.identity.first_name = ""
	s.primary_role = FcStaffRole.Id.NONE
	s.reputation = 101
	s.experience_years = -1
	assert_true(s.validate().size() >= 5, str(s.validate()))


func test_staff_retirement_consistency() -> void:
	var s := FcTestData.staff(1, defs)
	s.status = FcStaffMember.Status.RETIRED
	assert_true(not s.validate().is_empty())
	s.retired_season = 2035
	assert_eq(s.validate(), [] as Array[String])
	s.status = FcStaffMember.Status.ACTIVE
	assert_true(not s.validate().is_empty())


func test_staff_round_trip() -> void:
	var s := FcTestData.staff(5, defs)
	s.reputation = 83
	s.skills.set_value("offensive_strategy", 90)
	s.philosophy.set_value("pace_preference", 95)
	s.personality.set_value("ego", 70)
	var copy := FcStaffMember.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())), defs)
	assert_eq(copy.to_dict(), s.to_dict())
	assert_eq(copy.skills.get_value("offensive_strategy"), 90)
	assert_eq(copy.validate(), [] as Array[String])


func test_staff_holds_no_job_or_pay() -> void:
	var d := FcTestData.staff(1, defs).to_dict()
	assert_true(not d.has("team_id") and not d.has("salary") and not d.has("role"), "jobs live on contracts")


func test_staff_contract_queries() -> void:
	var c := FcTestData.staff_contract(1, 2, 3)
	assert_eq(c.validate(), [] as Array[String])
	assert_eq(c.start_season(), 2026)
	assert_eq(c.end_season(), 2027)
	assert_eq(c.salary_for(2027), 850000)
	assert_eq(c.salary_for(2040), 0)
	assert_eq(c.total_value(), 1650000)
	assert_true(c.is_in_force_in(2026))
	c.status = FcContract.Status.TERMINATED
	assert_true(not c.is_in_force_in(2026))


func test_staff_contract_validation() -> void:
	var c := FcStaffContract.new(0)
	assert_true(c.validate().size() >= 4)
	var gap := FcTestData.staff_contract(1, 2, 3)
	gap.years[1].season = 2030
	assert_true(not gap.validate().is_empty(), "non-consecutive")
	var role := FcTestData.staff_contract(1, 2, 3)
	role.role = FcStaffRole.Id.NONE
	assert_true(not role.validate().is_empty(), "invalid role")
	var date := FcTestData.staff_contract(1, 2, 3)
	date.signed_on = FcDate.new(2026, 4, 31)
	assert_true(not date.validate().is_empty(), "invalid date")


func test_staff_contract_round_trip() -> void:
	var c := FcTestData.staff_contract(1, 2, 3, FcStaffRole.Id.SCOUT)
	c.signed_on = FcDate.new(2026, 8, 20)
	var copy := FcStaffContract.from_dict(c.to_dict())
	assert_eq(copy.to_dict(), c.to_dict())
	assert_eq(copy.role, FcStaffRole.Id.SCOUT)


func test_world_with_staff_is_healthy_and_queryable() -> void:
	var w := FcTestData.world()
	assert_eq(w.validate(), [] as Array[String])
	assert_eq(w.staff.count(), 2)
	assert_eq(w.staff_contracts_of_team(1).size(), 2)
	assert_eq(w.staff_in_role(1, FcStaffRole.Id.GENERAL_MANAGER).id, 1)
	assert_eq(w.staff_in_role(1, FcStaffRole.Id.HEAD_COACH).id, 2)
	assert_true(w.staff_in_role(1, FcStaffRole.Id.SCOUT) == null)
	assert_eq(w.active_staff_contract_of(2).role, FcStaffRole.Id.HEAD_COACH)


func test_world_detects_staff_dangling_references() -> void:
	var w := FcTestData.world()
	w.staff_contracts.add(FcTestData.staff_contract(90, 999, 1, FcStaffRole.Id.SCOUT))
	w.staff_contracts.add(FcTestData.staff_contract(91, 1, 888, FcStaffRole.Id.SCOUT))
	var errors := w.validate()
	assert_true(_errors_contain(errors, "staff 999 does not exist"))
	assert_true(_errors_contain(errors, "team 888 does not exist"))


func test_world_detects_duplicate_unique_roles() -> void:
	var w := FcTestData.world()
	var second_coach := FcTestData.staff(w.ids.next_id(FcWorld.KIND_STAFF), w.definitions)
	w.staff.add(second_coach)
	w.staff_contracts.add(FcTestData.staff_contract(95, second_coach.id, 1, FcStaffRole.Id.HEAD_COACH))
	assert_true(_errors_contain(w.validate(), "more than one active Head Coach"))


func test_many_scouts_are_allowed() -> void:
	var w := FcTestData.world()
	for i in 3:
		var scout := FcTestData.staff(w.ids.next_id(FcWorld.KIND_STAFF), w.definitions, FcStaffRole.Id.SCOUT)
		w.staff.add(scout)
		w.staff_contracts.add(FcTestData.staff_contract(100 + i, scout.id, 1, FcStaffRole.Id.SCOUT))
	assert_eq(w.validate(), [] as Array[String])
	assert_eq(w.staff_contracts_of_team(1, FcStaffRole.Id.SCOUT).size(), 3)


func test_world_detects_two_active_jobs_and_retired_employee() -> void:
	var w := FcTestData.world()
	w.cities.add(FcTestData.city(2))
	w.arenas.add(FcTestData.arena(2, 2))
	w.teams.add(FcTestData.team(2, 2, 2))
	w.staff_contracts.add(FcTestData.staff_contract(96, 1, 2, FcStaffRole.Id.GENERAL_MANAGER))
	assert_true(_errors_contain(w.validate(), "staff 1 has more than one active contract"))
	w.staff_contracts.remove(96)
	w.staff.get_by_id(2).status = FcStaffMember.Status.RETIRED
	w.staff.get_by_id(2).retired_season = 2030
	assert_true(_errors_contain(w.validate(), "is retired but has an active contract"))


func test_job_history_is_allowed() -> void:
	var w := FcTestData.world()
	var old := FcTestData.staff_contract(97, 2, 1, FcStaffRole.Id.ASSISTANT_COACH)
	old.status = FcContract.Status.EXPIRED
	w.staff_contracts.add(old)
	assert_eq(w.validate(), [] as Array[String])
	assert_eq(w.active_staff_contract_of(2).role, FcStaffRole.Id.HEAD_COACH)


func test_old_snapshot_without_staff_still_loads() -> void:
	# Saves made before staff existed have no "staff" keys.
	var data := FcTestData.world().to_dict()
	data.erase("staff")
	data.erase("staff_contracts")
	var errors: Array[String] = []
	var w := FcWorld.from_dict(data, FcTestData.defs(), errors)
	assert_eq(errors, [] as Array[String])
	assert_eq(w.staff.count(), 0)
	assert_eq(w.players.count(), 2)


func test_world_round_trip_includes_staff() -> void:
	var w := FcTestData.world()
	var copy := FcWorld.from_dict(JSON.parse_string(JSON.stringify(w.to_dict())), w.definitions)
	assert_eq(copy.to_dict(), w.to_dict())
	assert_eq(copy.staff_contracts.count(), 2)
	assert_eq(copy.ids.next_id(FcWorld.KIND_STAFF), 3)
