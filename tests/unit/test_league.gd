extends FcTestCase


func _league() -> FcLeague:
	var l := FcLeague.new(1, "Test League")
	var east := FcConference.new(1, "East")
	var west := FcConference.new(2, "West")
	var d1 := FcDivision.new(1, "North")
	var d2 := FcDivision.new(2, "South")
	var d3 := FcDivision.new(3, "Pacific")
	d1.team_ids.append_array([1, 2])
	d2.team_ids.append_array([3, 4])
	d3.team_ids.append_array([5, 6])
	east.divisions.append_array([d1, d2])
	west.divisions.append(d3)
	l.conferences.append_array([east, west])
	return l


func _errors_contain(errors: Array[String], text: String) -> bool:
	for e in errors:
		if text in e:
			return true
	return false


func test_valid_league_and_queries() -> void:
	var l := _league()
	assert_eq(l.validate(), [] as Array[String])
	assert_eq(l.team_count(), 6)
	assert_eq(l.all_team_ids(), [1, 2, 3, 4, 5, 6] as Array[int])
	assert_eq(l.all_divisions().size(), 3)
	assert_eq(l.division_of_team(4).name, "South")
	assert_eq(l.conference_of_team(4).name, "East")
	assert_eq(l.conference_of_team(5).name, "West")
	assert_true(l.division_of_team(99) == null)
	assert_true(l.contains_team(6) and not l.contains_team(7))


func test_add_and_remove_team() -> void:
	var l := _league()
	assert_eq(l.add_team(3, 7), OK)
	assert_eq(l.team_count(), 7)
	assert_eq(l.add_team(3, 7), ERR_ALREADY_EXISTS)
	assert_eq(l.add_team(1, 7), ERR_ALREADY_EXISTS, "cannot be in two divisions")
	assert_eq(l.add_team(99, 8), ERR_DOES_NOT_EXIST)
	assert_eq(l.add_team(1, 0), ERR_INVALID_PARAMETER)
	assert_eq(l.remove_team(7), OK)
	assert_eq(l.remove_team(7), ERR_DOES_NOT_EXIST)
	assert_eq(l.team_count(), 6)


func test_validation_catches_problems() -> void:
	var l := _league()
	l.name = " "
	l.conferences[0].divisions[0].team_ids.append(3)
	l.conferences[1].divisions[0].team_ids.append(-1)
	l.conferences[1].divisions[0].name = ""
	l.conferences[0].divisions[1].id = 1
	l.conferences[1].id = 1
	var errors := l.validate()
	assert_true(_errors_contain(errors, "needs a name"))
	assert_true(_errors_contain(errors, "appears twice"))
	assert_true(_errors_contain(errors, "invalid team id"))
	assert_true(_errors_contain(errors, "duplicate division id"))
	assert_true(_errors_contain(errors, "duplicate conference id"))
	assert_true(not FcLeague.new(1, "Empty").validate().is_empty(), "no conferences")
	var no_division := FcLeague.new(1, "X")
	no_division.conferences.append(FcConference.new(1, "C"))
	assert_true(not no_division.validate().is_empty(), "conference without divisions")


func test_league_round_trip() -> void:
	var l := _league()
	var copy := FcLeague.from_dict(JSON.parse_string(JSON.stringify(l.to_dict())))
	assert_eq(copy.to_dict(), l.to_dict())
	assert_eq(copy.team_count(), 6)
	assert_eq(copy.conference_of_team(5).name, "West")


func test_world_league_integrity() -> void:
	var w := FcTestData.world()
	assert_eq(w.validate(), [] as Array[String], "worlds without leagues stay valid")
	var l := FcLeague.new(1, "L")
	var c := FcConference.new(1, "C")
	var d := FcDivision.new(1, "D")
	d.team_ids.append(1)
	c.divisions.append(d)
	l.conferences.append(c)
	w.leagues.add(l)
	assert_eq(w.validate(), [] as Array[String])
	assert_eq(w.league_of_team(1).id, 1)

	d.team_ids.append(77)
	assert_true(_errors_contain(w.validate(), "team 77 does not exist"))
	d.team_ids.erase(77)

	w.cities.add(FcTestData.city(2))
	w.arenas.add(FcTestData.arena(2, 2))
	w.teams.add(FcTestData.team(2, 2, 2))
	assert_true(_errors_contain(w.validate(), "team 2 is not in any league"))

	var other := FcLeague.new(2, "Other")
	var oc := FcConference.new(2, "OC")
	var od := FcDivision.new(2, "OD")
	od.team_ids.append_array([1, 2])
	oc.divisions.append(od)
	other.conferences.append(oc)
	w.leagues.add(other)
	assert_true(_errors_contain(w.validate(), "team 1 is in leagues"))


func test_world_round_trip_includes_leagues() -> void:
	var w := FcTestData.world()
	var l := _league()
	w.leagues.add(l)
	var copy := FcWorld.from_dict(JSON.parse_string(JSON.stringify(w.to_dict())), w.definitions)
	assert_eq(copy.leagues.count(), 1)
	assert_eq(copy.to_dict(), w.to_dict())


func test_old_snapshot_without_leagues_loads() -> void:
	var data := FcTestData.world().to_dict()
	data.erase("leagues")
	var errors: Array[String] = []
	var w := FcWorld.from_dict(data, FcTestData.defs(), errors)
	assert_eq(errors, [] as Array[String])
	assert_eq(w.leagues.count(), 0)


func test_city_area_round_trip_and_old_saves() -> void:
	var c := FcTestData.city(3)
	c.area = "europe"
	assert_eq(FcCity.from_dict(c.to_dict()).area, "europe")
	var old := c.to_dict()
	old.erase("area")
	assert_eq(FcCity.from_dict(old).area, "", "saves from before areas existed")
