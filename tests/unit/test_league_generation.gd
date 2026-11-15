extends FcTestCase
## Customizable leagues: size, areas, exact cities, conferences and divisions.

const SEED := 4242

var data: FcGenerationData
var defs: FcDefinitionSet


func before_each() -> void:
	data = FcGenerationData.load_default()
	defs = FcDefinitionSet.load_default()


func _config() -> FcGenerationConfig:
	return FcGenerationConfig.load_default(data)


func _generate(cfg: FcGenerationConfig, seed_value: int = SEED) -> FcWorld:
	return FcWorldGenerator.new(data, defs, cfg).generate(seed_value)


func _areas_of(w: FcWorld) -> Dictionary:
	var out := {}
	for c in w.cities.all():
		out[c.area] = true
	return out


func _errors_contain(errors: Array[String], text: String) -> bool:
	for e in errors:
		if text in e:
			return true
	return false


# --- data ------------------------------------------------------------------

func test_real_world_city_data() -> void:
	var cities: Array = data.world["cities"]
	assert_true(cities.size() >= 100, "enough cities to build large leagues")
	var by_area := {}
	for c in cities:
		by_area[c["area"]] = int(by_area.get(c["area"], 0)) + 1
	for area in ["north_america", "south_america", "europe", "asia", "oceania", "africa"]:
		assert_true(by_area.get(area, 0) >= 5, "area %s has cities" % area)
	assert_true(by_area["north_america"] >= 30 and by_area["europe"] >= 25)


func test_every_country_has_name_pools_and_every_city_a_country() -> void:
	assert_eq(data.validate(), [] as Array[String])
	var names := FcNameGenerator.new(data)
	var rng := FcRng.new(1)
	for key in names.country_keys():
		var n := names.generate(rng, key)
		assert_true(not n["first"].is_empty() and not n["last"].is_empty(), key)


# --- choosing teams --------------------------------------------------------

func test_default_league_is_north_american_30_teams() -> void:
	var w := _generate(_config())
	assert_eq(w.validate(), [] as Array[String])
	assert_eq(w.teams.count(), 30)
	assert_eq(_areas_of(w).keys(), ["north_america"])


func test_choose_europe() -> void:
	var cfg := _config()
	cfg.areas = ["europe"] as Array[String]
	cfg.team_count = 20
	cfg.conference_count = 2
	cfg.divisions_per_conference = 2
	var w := _generate(cfg)
	assert_eq(w.validate(), [] as Array[String])
	assert_eq(_areas_of(w).keys(), ["europe"])
	assert_eq(w.teams.count(), 20)


func test_mixed_areas_and_any_area() -> void:
	var cfg := _config()
	cfg.areas = ["north_america", "europe"] as Array[String]
	cfg.team_count = 40
	var w := _generate(cfg)
	assert_eq(w.validate(), [] as Array[String])
	assert_eq(_areas_of(w).size(), 2)
	var anywhere := _config()
	anywhere.areas = [] as Array[String]
	anywhere.team_count = 60
	anywhere.selection_mode = "largest"
	var w2 := _generate(anywhere)
	assert_eq(w2.validate(), [] as Array[String])
	assert_true(_areas_of(w2).size() >= 4, "the 60 biggest cities span many areas")


func test_largest_mode_picks_biggest_cities_and_is_seed_independent() -> void:
	var cfg := _config()
	cfg.selection_mode = "largest"
	cfg.team_count = 12
	var a := _generate(cfg, 1)
	var b := _generate(cfg, 2)
	var names_a: Array = a.cities.all().map(func(c): return c.name)
	var names_b: Array = b.cities.all().map(func(c): return c.name)
	names_a.sort()
	names_b.sort()
	assert_eq(names_a, names_b, "same cities regardless of seed")
	assert_true(names_a.has("New York") and names_a.has("Los Angeles") and names_a.has("Toronto"))
	assert_true(not names_a.has("Quebec City"))


func test_exact_city_list_in_order() -> void:
	var cfg := _config()
	cfg.city_keys = ["london", "paris", "madrid", "tokyo", "sydney", "lagos", "sao_paulo", "new_york"] as Array[String]
	cfg.conference_count = 2
	cfg.divisions_per_conference = 2
	var w := _generate(cfg)
	assert_eq(w.validate(), [] as Array[String])
	assert_eq(w.teams.count(), 8)
	assert_eq(w.cities.get_by_id(1).name, "London")
	assert_eq(w.cities.get_by_id(7).name, "São Paulo")
	assert_eq(w.cities.get_by_id(8).area, "north_america")
	assert_eq(w.cities.get_by_id(4).country, "Japan")
	assert_eq(w.teams.get_by_id(7).identity.abbreviation.length() >= 2, true)


func test_custom_team_nicknames() -> void:
	var cfg := _config()
	cfg.city_keys = ["london", "paris", "madrid", "rome"] as Array[String]
	cfg.conference_count = 1
	cfg.divisions_per_conference = 1
	cfg.team_nicknames = {"paris": "Parisians", "rome": "Gladiators"}
	var w := _generate(cfg)
	assert_eq(w.teams.get_by_id(2).identity.nickname, "Parisians")
	assert_eq(w.teams.get_by_id(4).identity.nickname, "Gladiators")
	var seen := {}
	for t in w.teams.all():
		assert_true(not seen.has(t.identity.nickname), "unique nicknames")
		seen[t.identity.nickname] = true


func test_selection_is_reproducible_and_varies_by_seed() -> void:
	var cfg := _config()
	var a := _generate(cfg, 10)
	var b := _generate(cfg, 10)
	var c := _generate(cfg, 11)
	assert_eq(a.to_dict(), b.to_dict())
	var names_a: Array = a.cities.all().map(func(x): return x.name)
	var names_c: Array = c.cities.all().map(func(x): return x.name)
	names_a.sort()
	names_c.sort()
	assert_true(names_a != names_c, "different seeds choose different cities")


func test_accented_and_multiword_city_abbreviations_are_valid() -> void:
	var cfg := _config()
	cfg.city_keys = ["sao_paulo", "bogota", "medellin", "cordoba", "brasilia", "new_york", "new_orleans", "los_angeles", "las_vegas", "san_diego", "san_antonio", "san_francisco"] as Array[String]
	cfg.conference_count = 2
	cfg.divisions_per_conference = 3
	var w := _generate(cfg)
	assert_eq(w.validate(), [] as Array[String])
	var seen := {}
	for t in w.teams.all():
		assert_true(FcChecks.is_abbreviation(t.identity.abbreviation), t.identity.abbreviation)
		assert_true(not seen.has(t.identity.abbreviation), "unique %s" % t.identity.abbreviation)
		seen[t.identity.abbreviation] = true


# --- sizes -----------------------------------------------------------------

func test_many_league_sizes_are_valid() -> void:
	for n in [2, 3, 4, 8, 12, 16, 24, 30, 36, 48]:
		var cfg := _config()
		cfg.areas = [] as Array[String]
		cfg.team_count = n
		cfg.free_agent_count = 10
		var structure := [1, 1]
		if n >= 24:
			structure = [2, 3]
		elif n >= 8:
			structure = [2, 2]
		cfg.conference_count = structure[0]
		cfg.divisions_per_conference = structure[1]
		assert_eq(cfg.validate(data), [] as Array[String], "config for %d teams" % n)
		var w := _generate(cfg)
		assert_eq(w.validate(), [] as Array[String], "world for %d teams" % n)
		assert_eq(w.teams.count(), n)
		assert_eq(w.leagues.get_by_id(1).team_count(), n)


func test_largest_possible_league() -> void:
	var cfg := _config()
	cfg.areas = [] as Array[String]
	cfg.team_count = 100
	cfg.conference_count = 4
	cfg.divisions_per_conference = 5
	cfg.free_agent_count = 0
	assert_eq(cfg.validate(data), [] as Array[String])
	var w := _generate(cfg)
	assert_eq(w.validate(), [] as Array[String])
	assert_eq(w.teams.count(), 100)


# --- structure -------------------------------------------------------------

func test_structure_is_even_and_complete() -> void:
	var cfg := _config()
	var w := _generate(cfg)
	var league: FcLeague = w.leagues.get_by_id(1)
	assert_eq(league.name, "Full Court League")
	assert_eq(league.conferences.size(), 2)
	assert_eq(league.team_count(), 30)
	var conference_sizes: Array = []
	for c in league.conferences:
		assert_eq(c.divisions.size(), 3)
		var in_conference := 0
		for d in c.divisions:
			assert_eq(d.team_ids.size(), 5, "30 teams / 6 divisions")
			in_conference += d.team_ids.size()
		conference_sizes.append(in_conference)
	assert_eq(conference_sizes, [15, 15])
	for t in w.teams.all():
		assert_true(league.contains_team(t.id))


func test_uneven_sizes_differ_by_at_most_one() -> void:
	var cfg := _config()
	cfg.team_count = 31
	cfg.conference_count = 3
	cfg.divisions_per_conference = 2
	var w := _generate(cfg)
	assert_eq(w.validate(), [] as Array[String])
	var sizes: Array = []
	for d in w.leagues.get_by_id(1).all_divisions():
		sizes.append(d.team_ids.size())
	assert_true(sizes.max() - sizes.min() <= 1, "division sizes %s" % str(sizes))
	assert_eq(sizes.reduce(func(a, b): return a + b), 31)


func test_conferences_are_geographic() -> void:
	var cfg := _config()
	cfg.areas = ["north_america", "europe"] as Array[String]
	cfg.city_keys = ["new_york", "los_angeles", "chicago", "toronto", "london", "paris", "madrid", "berlin"] as Array[String]
	cfg.conference_count = 2
	cfg.divisions_per_conference = 2
	var w := _generate(cfg)
	var league: FcLeague = w.leagues.get_by_id(1)
	var western: Array = []
	var eastern: Array = []
	for t in w.teams.all():
		var city: FcCity = w.cities.get_by_id(t.city_id)
		var conf := league.conference_of_team(t.id).name
		(western if conf == "Western" else eastern).append(city.name)
	western.sort()
	eastern.sort()
	assert_eq(western, ["Chicago", "Los Angeles", "New York", "Toronto"], "the Americas")
	assert_eq(eastern, ["Berlin", "London", "Madrid", "Paris"], "Europe")


func test_divisions_group_north_and_south() -> void:
	var cfg := _config()
	cfg.city_keys = ["miami", "atlanta", "dallas", "houston", "boston", "seattle", "chicago", "new_york"] as Array[String]
	cfg.conference_count = 1
	cfg.divisions_per_conference = 2
	var w := _generate(cfg)
	var league: FcLeague = w.leagues.get_by_id(1)
	var south := league.all_divisions()[0]
	var north := league.all_divisions()[1]
	assert_eq(south.name, "South")
	assert_eq(north.name, "North")
	var south_cities: Array = south.team_ids.map(func(id): return w.cities.get_by_id(w.teams.get_by_id(id).city_id).name)
	assert_true(south_cities.has("Miami") and south_cities.has("Houston"))
	var north_cities: Array = north.team_ids.map(func(id): return w.cities.get_by_id(w.teams.get_by_id(id).city_id).name)
	assert_true(north_cities.has("Seattle") and north_cities.has("Boston"))


func test_league_name_is_configurable() -> void:
	var cfg := _config()
	cfg.league_name = "Atlantic Basketball Association"
	cfg.team_count = 12
	assert_eq(_generate(cfg).leagues.get_by_id(1).name, "Atlantic Basketball Association")


# --- nationalities ---------------------------------------------------------

func test_players_are_mostly_local() -> void:
	var cfg := _config()
	cfg.city_keys = ["madrid", "barcelona", "valencia", "lisbon"] as Array[String]
	cfg.conference_count = 1
	cfg.divisions_per_conference = 1
	cfg.home_country_share = 0.9
	var w := _generate(cfg)
	var local := 0
	var total := 0
	for t in w.teams.all():
		var country: String = w.cities.get_by_id(t.city_id).country
		for pid in t.roster.player_ids:
			total += 1
			if w.players.get_by_id(pid).identity.country == country:
				local += 1
	assert_true(float(local) / total > 0.85, "most players are from the team's country")


func test_home_share_zero_gives_global_mix() -> void:
	var cfg := _config()
	cfg.home_country_share = 0.0
	cfg.team_count = 12
	var w := _generate(cfg)
	var countries := {}
	for p in w.players.all():
		countries[p.identity.country] = true
	assert_true(countries.size() >= 8, "many nationalities appear (%d)" % countries.size())
	assert_true(countries.has("United States"))


# --- validation of user choices -------------------------------------------

func test_config_validation_messages() -> void:
	var cfg := _config()
	cfg.areas = ["atlantis"] as Array[String]
	assert_true(_errors_contain(cfg.validate(data), "unknown area 'atlantis'"))

	cfg = _config()
	cfg.areas = ["oceania"] as Array[String]
	cfg.team_count = 30
	assert_true(_errors_contain(cfg.validate(data), "exceeds the 5 cities available"))

	cfg = _config()
	cfg.city_keys = ["london", "nowhere", "london"] as Array[String]
	var errors := cfg.validate(data)
	assert_true(_errors_contain(errors, "unknown city 'nowhere'"))
	assert_true(_errors_contain(errors, "listed twice"))

	cfg = _config()
	cfg.team_count = 10
	assert_true(_errors_contain(cfg.validate(data), "cannot fill"), "10 teams cannot fill 2x3 divisions of 2+")

	cfg = _config()
	cfg.team_count = 1
	assert_true(_errors_contain(cfg.validate(data), "at least 2 teams"))

	cfg = _config()
	cfg.conference_count = 0
	assert_true(_errors_contain(cfg.validate(data), "at least 1"))

	cfg = _config()
	cfg.selection_mode = "random_walk"
	cfg.league_name = ""
	errors = cfg.validate(data)
	assert_true(_errors_contain(errors, "selection_mode"))
	assert_true(_errors_contain(errors, "needs a name"))

	cfg = _config()
	cfg.areas = [] as Array[String]
	cfg.team_count = 101
	assert_true(_errors_contain(cfg.validate(data), "nicknames"))


func test_effective_team_count() -> void:
	var cfg := _config()
	assert_eq(cfg.effective_team_count(), 30)
	cfg.city_keys = ["london", "paris", "rome"] as Array[String]
	assert_eq(cfg.effective_team_count(), 3)


func test_custom_league_survives_save_and_load() -> void:
	var cfg := _config()
	cfg.areas = ["europe"] as Array[String]
	cfg.team_count = 16
	cfg.conference_count = 2
	cfg.divisions_per_conference = 2
	cfg.free_agent_count = 10
	var state := FcWorldGenerator.new(data, defs, cfg).new_game_state(SEED)
	assert_eq(state.validate(), [] as Array[String])
	var manager := FcSaveManager.new("user://test_saves_league")
	assert_true(manager.save("euro", state).is_ok())
	var loaded := manager.load_slot("euro", defs)
	assert_true(loaded.is_ok(), loaded.message)
	assert_eq(loaded.warnings, [] as Array[String])
	assert_eq(loaded.state.to_dict(), state.to_dict())
	var league: FcLeague = loaded.state.world.leagues.get_by_id(1)
	assert_eq(league.team_count(), 16)
	manager.delete_slot("euro")
	DirAccess.remove_absolute("user://test_saves_league")
