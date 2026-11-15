class_name FcWorldGenerator
extends RefCounted
## Builds a complete, internally consistent fictional league from one seed:
## cities, arenas, teams, full rosters with contracts, coaching/front-office
## staff with contracts, and a pool of free agents.
##
## Reproducible: the same seed and config always produce the identical world.
## Each stage (cities, each team, free agents) uses its own forked random
## stream, so changing one stage does not reshuffle the others.
##
## It does NOT create league structure (conferences, schedule) or history;
## those belong to the league-operations systems.

var _data: FcGenerationData
var _defs: FcDefinitionSet
var config: FcGenerationConfig
var _players: FcPlayerGenerator
var _staff: FcStaffGenerator
var _names: FcNameGenerator


func _init(data: FcGenerationData, defs: FcDefinitionSet, generation_config: FcGenerationConfig) -> void:
	_data = data
	_defs = defs
	config = generation_config
	_players = FcPlayerGenerator.new(data, defs)
	_staff = FcStaffGenerator.new(data, defs)
	_names = FcNameGenerator.new(data)


## Convenience: shipped data and default config.
static func create_default() -> FcWorldGenerator:
	var data := FcGenerationData.load_default()
	return FcWorldGenerator.new(data, FcDefinitionSet.load_default(), FcGenerationConfig.load_default(data))


## Problems with the data or config that would prevent generation. Empty = OK.
func validate() -> Array[String]:
	var errors := _data.validate()
	errors.append_array(config.validate(_data))
	return errors


## A ready-to-play state: generated world, user controls the team at
## `user_team_index` (0-based, in creation order).
func new_game_state(seed_value: int, mode: String = FcGameState.MODE_OWNER, user_team_index: int = 0) -> FcGameState:
	var world := generate(seed_value)
	var state := FcGameState.new(world, FcRng.new(seed_value).fork("game"))
	state.mode = mode
	var team_ids := world.teams.ids()
	state.user_team_id = team_ids[clampi(user_team_index, 0, team_ids.size() - 1)]
	state.current_season = config.start_season
	state.current_date = FcDate.new(config.start_season, 7, 1)
	return state


func generate(seed_value: int) -> FcWorld:
	var root := FcRng.new(seed_value)
	var world := FcWorld.new(_defs)
	var used_names := {}
	var reference := FcDate.new(config.start_season, 7, 1)

	var cities: Array = _shuffled(root.fork("cities"), _data.world["cities"])
	var nicknames: Array = _shuffled(root.fork("nicknames"), _data.world["nicknames"])
	var schemes: Array = _shuffled(root.fork("colors"), _data.world["color_schemes"])
	var used_abbreviations := {}
	var used_arena_names := {}

	for i in config.team_count:
		var team_rng := root.fork("team:%d" % i)
		var city := _make_city(world, cities[i])
		var arena := _make_arena(world, team_rng, city, used_arena_names)
		var team := FcTeam.new(world.ids.next_id(FcWorld.KIND_TEAM))
		team.city_id = city.id
		team.arena_id = arena.id
		team.identity.nickname = nicknames[i]
		team.identity.abbreviation = _make_abbreviation(city.name, used_abbreviations)
		team.identity.founded_year = team_rng.range_int(1950, 2015)
		var scheme: Array = schemes[i % schemes.size()]
		team.branding.primary_color = scheme[0]
		team.branding.secondary_color = scheme[1]
		team.branding.accent_color = scheme[2]
		team.roster.max_size = maxi(FcRoster.DEFAULT_MAX_SIZE, config.roster_size)
		world.teams.add(team)
		_fill_roster(world, team, team_rng.fork("players"), used_names, reference)
		_hire_staff(world, team, team_rng.fork("staff"), used_names, reference)

	_add_free_agents(world, root.fork("free_agents"), used_names, reference)
	return world


# --- cities, arenas, teams -------------------------------------------------

func _make_city(world: FcWorld, entry: Dictionary) -> FcCity:
	var c := FcCity.new(world.ids.next_id(FcWorld.KIND_CITY))
	c.name = str(entry["name"])
	c.region = str(entry["region"])
	c.country = str(_data.world.get("country", "Aldoria"))
	c.population = int(entry["population"])
	c.economy_index = int(entry["economy"])
	world.cities.add(c)
	return c


func _make_arena(world: FcWorld, rng: FcRng, city: FcCity, used: Dictionary) -> FcArena:
	var a := FcArena.new(world.ids.next_id(FcWorld.KIND_ARENA))
	a.city_id = city.id
	var patterns: Array = _data.world["arena_patterns"]
	var landmarks: Array = _data.world["landmarks"]
	var arena_name := ""
	for attempt in 20:
		var pattern: String = patterns[rng.range_int(0, patterns.size() - 1)]
		var landmark: String = landmarks[rng.range_int(0, landmarks.size() - 1)]
		arena_name = pattern.replace("{city}", city.name).replace("{landmark}", landmark)
		if not used.has(arena_name):
			break
	used[arena_name] = true
	a.name = arena_name
	a.capacity = clampi(roundi(rng.gaussian(18500.0, 1800.0) / 100.0) * 100, 15000, 22000)
	a.year_built = rng.range_int(1990, 2023)
	world.arenas.add(a)
	return a


## 2-4 letter code from the city name, unique among teams.
func _make_abbreviation(city_name: String, used: Dictionary) -> String:
	var letters := ""
	for ch in city_name.to_upper():
		if ch >= "A" and ch <= "Z":
			letters += ch
	var candidates: Array[String] = [letters.substr(0, 3)]
	var initials := ""
	for word in city_name.to_upper().split(" "):
		if not word.is_empty():
			initials += word[0]
	if initials.length() >= 2:
		candidates.append(initials.substr(0, 4))
	for i in range(2, letters.length()):
		candidates.append(letters.substr(0, 2) + letters[i])
	for candidate in candidates:
		if candidate.length() >= 2 and not used.has(candidate):
			used[candidate] = true
			return candidate
	for first in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
		for second in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
			var code: String = "%s%s%s" % [letters.substr(0, 1), first, second]
			if not used.has(code):
				used[code] = true
				return code
	return letters.substr(0, 3)


# --- players ---------------------------------------------------------------

func _fill_roster(world: FcWorld, team: FcTeam, rng: FcRng, used_names: Dictionary, reference: FcDate) -> void:
	var strength := rng.gaussian(0.0, config.team_strength_sd)
	var positions := _roster_positions(rng, config.roster_size)
	for slot in config.roster_size:
		var t := float(slot) / float(maxi(1, config.roster_size - 1))
		var base := lerpf(config.top_player_level, config.bottom_player_level, pow(t, 0.7))
		var age := clampi(roundi(rng.gaussian(26.5, 3.8)), 19, 38)
		var prime_level := base + strength + rng.gaussian(0.0, 5.0)
		var level := clampf(FcPlayerGenerator.age_adjusted_level(prime_level, age), 20.0, 92.0)
		var spec := FcPlayerSpec.new()
		spec.age = age
		spec.position = positions[slot]
		spec.level = level
		spec.country_key = _pick_country(rng)
		spec.reference_date = reference
		spec.used_names = used_names
		var player := _players.generate(rng, world.ids.next_id(FcWorld.KIND_PLAYER), spec)
		world.players.add(player)
		team.roster.add(player.id)
		world.contracts.add(_player_contract(world, rng, player.id, team.id, level))


func _add_free_agents(world: FcWorld, rng: FcRng, used_names: Dictionary, reference: FcDate) -> void:
	var positions := _roster_positions(rng, maxi(1, config.free_agent_count))
	for i in config.free_agent_count:
		var age := clampi(roundi(rng.gaussian(28.0, 5.0)), 19, 38)
		var spec := FcPlayerSpec.new()
		spec.age = age
		spec.position = positions[i]
		spec.level = clampf(FcPlayerGenerator.age_adjusted_level(rng.gaussian(42.0, 7.0), age), 20.0, 62.0)
		spec.country_key = _pick_country(rng)
		spec.reference_date = reference
		spec.used_names = used_names
		world.players.add(_players.generate(rng, world.ids.next_id(FcWorld.KIND_PLAYER), spec))


## An evenly spread, shuffled list of positions (PG,SG,SF,PF,C repeating).
func _roster_positions(rng: FcRng, count: int) -> Array[int]:
	var list: Array[int] = []
	for i in count:
		list.append(FcPosition.Id.PG + (i % 5))
	return _shuffled(rng, list)


func _pick_country(rng: FcRng) -> String:
	var home := _names.home_country()
	if not rng.chance(config.international_share):
		return home
	var others: Array[String] = []
	for k in _names.country_keys():
		if k != home:
			others.append(k)
	return home if others.is_empty() else others[rng.range_int(0, others.size() - 1)]


## Contract already partly served: it started up to (length - 1) seasons ago.
func _player_contract(world: FcWorld, rng: FcRng, player_id: int, team_id: int, level: float) -> FcContract:
	var t := pow(clampf((level - 35.0) / 55.0, 0.0, 1.0), 2.2)
	var base := lerpf(float(config.min_salary), float(config.max_salary), t)
	var total_years := rng.range_int(config.min_contract_years, config.max_contract_years)
	var elapsed := rng.range_int(0, total_years - 1)
	var first_season := config.start_season - elapsed
	var c := FcContract.new(world.ids.next_id(FcWorld.KIND_CONTRACT))
	c.player_id = player_id
	c.team_id = team_id
	c.signed_on = FcDate.new(first_season, 7, 1)
	for i in total_years:
		var salary := clampi(roundi(base * pow(1.05, i) / 10000.0) * 10000, config.min_salary, config.max_salary)
		c.years.append(FcContractYear.new(first_season + i, salary))
	return c


# --- staff -----------------------------------------------------------------

func _hire_staff(world: FcWorld, team: FcTeam, rng: FcRng, used_names: Dictionary, reference: FcDate) -> void:
	var jobs: Array = [
		[FcStaffRole.Id.GENERAL_MANAGER, 1, 55.0],
		[FcStaffRole.Id.HEAD_COACH, 1, 55.0],
		[FcStaffRole.Id.ASSISTANT_COACH, config.assistant_coaches, 50.0],
		[FcStaffRole.Id.SCOUT, config.scouts, 50.0],
		[FcStaffRole.Id.MEDICAL, config.medical_staff, 52.0],
		[FcStaffRole.Id.BUSINESS_EXECUTIVE, config.business_executives, 52.0],
	]
	for job in jobs:
		for n in int(job[1]):
			var level := clampf(rng.gaussian(float(job[2]), 11.0), 30.0, 85.0)
			var member := _staff.generate(rng, world.ids.next_id(FcWorld.KIND_STAFF), int(job[0]), level, reference, used_names, _pick_country(rng))
			world.staff.add(member)
			world.staff_contracts.add(_staff_contract(world, rng, member, team.id, int(job[0])))


func _staff_contract(world: FcWorld, rng: FcRng, member: FcStaffMember, team_id: int, role: int) -> FcStaffContract:
	var total_years := rng.range_int(1, 3)
	var elapsed := rng.range_int(0, total_years - 1)
	var first_season := config.start_season - elapsed
	var c := FcStaffContract.new(world.ids.next_id(FcWorld.KIND_STAFF_CONTRACT))
	c.staff_id = member.id
	c.team_id = team_id
	c.role = role
	c.signed_on = FcDate.new(first_season, 7, 1)
	var salary := _staff.salary_for(role, member.reputation)
	for i in total_years:
		c.years.append(FcContractYear.new(first_season + i, roundi(salary * pow(1.04, i) / 10000.0) * 10000))
	return c


# --- helpers ---------------------------------------------------------------

## Fisher-Yates shuffle using the seeded generator; returns a new array.
func _shuffled(rng: FcRng, source: Array):
	var out := source.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := rng.range_int(0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out
