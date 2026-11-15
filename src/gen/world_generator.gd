class_name FcWorldGenerator
extends RefCounted
## Builds a complete, internally consistent league from one seed and a
## customizable FcGenerationConfig: teams placed in real cities (chosen by
## area, by size, or an exact list), a league structure of conferences and
## divisions grouped geographically, full rosters with contracts, coaching and
## front-office staff with contracts, and a pool of free agents.
##
## Teams, players and staff are ORIGINAL (generated); only places and country
## names are real. No real franchises, logos or player names are used.
##
## Reproducible: the same seed and config always produce the identical world.
## Each stage (city choice, each team, free agents) uses its own forked random
## stream, so changing one stage does not reshuffle the others.
##
## Call validate() first: generate() assumes a valid config. It does NOT create
## league rules (season length, playoffs, salary cap) or history.

const CONFERENCE_NAMES := {
	1: ["League"],
	2: ["Western", "Eastern"],
	3: ["Western", "Central", "Eastern"],
	4: ["Far West", "West", "East", "Far East"],
}
const DIVISION_NAMES := {2: ["South", "North"], 3: ["South", "Central", "North"]}

## Accented letters are reduced to plain A-Z when building team abbreviations.
const LETTER_FOLDING := {
	"Á": "A", "À": "A", "Â": "A", "Ã": "A", "Ä": "A",
	"É": "E", "È": "E", "Ê": "E", "Í": "I", "Ó": "O",
	"Ô": "O", "Ö": "O", "Ú": "U", "Ü": "U", "Ç": "C", "Ñ": "N",
}

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


## The cities this config would use (data dictionaries from world.json), in
## team order. A UI can use this to preview a league before generating it.
func select_cities(rng: FcRng) -> Array:
	var cities: Array = _data.world["cities"]
	if not config.city_keys.is_empty():
		var index := {}
		for c in cities:
			index[c["key"]] = c
		var exact: Array = []
		for key in config.city_keys:
			exact.append(index[key])
		return exact

	var candidates: Array = []
	for c in cities:
		if config.areas.is_empty() or config.areas.has(c["area"]):
			candidates.append(c)
	var n := config.team_count
	if config.selection_mode == "largest":
		candidates.sort_custom(func(a, b):
			if int(a["population"]) != int(b["population"]):
				return int(a["population"]) > int(b["population"])
			return str(a["name"]) < str(b["name"]))
		return candidates.slice(0, n)

	var chosen: Array = []
	var pool := candidates.duplicate()
	for i in n:
		var weights: Array = []
		for c in pool:
			weights.append(float(c["population"]))
		var pick := rng.weighted_index(weights)
		chosen.append(pool[pick])
		pool.remove_at(pick)
	return chosen


func generate(seed_value: int) -> FcWorld:
	var root := FcRng.new(seed_value)
	var world := FcWorld.new(_defs)
	var used_names := {}
	var reference := FcDate.new(config.start_season, 7, 1)
	var entries := select_cities(root.fork("cities"))
	var team_count := entries.size()

	var custom_names: Array = config.team_nicknames.values()
	var nickname_pool: Array = []
	for nick in _shuffled(root.fork("nicknames"), _data.world["nicknames"]):
		if not custom_names.has(nick):
			nickname_pool.append(nick)
	var schemes: Array = _shuffled(root.fork("colors"), _data.world["color_schemes"])
	var used_abbreviations := {}
	var used_arena_names := {}
	var teams: Array[FcTeam] = []
	var nick_cursor := 0

	for i in team_count:
		var entry: Dictionary = entries[i]
		var team_rng := root.fork("team:%d" % i)
		var city := _make_city(world, entry)
		var arena := _make_arena(world, team_rng, city, used_arena_names)
		var team := FcTeam.new(world.ids.next_id(FcWorld.KIND_TEAM))
		team.city_id = city.id
		team.arena_id = arena.id
		if config.team_nicknames.has(entry["key"]):
			team.identity.nickname = str(config.team_nicknames[entry["key"]])
		elif nick_cursor < nickname_pool.size():
			team.identity.nickname = str(nickname_pool[nick_cursor])
			nick_cursor += 1
		else:
			team.identity.nickname = "Team %d" % (i + 1)
		team.identity.abbreviation = _make_abbreviation(city.name, used_abbreviations)
		team.identity.founded_year = team_rng.range_int(1950, 2015)
		var scheme: Array = schemes[i % schemes.size()]
		team.branding.primary_color = scheme[0]
		team.branding.secondary_color = scheme[1]
		team.branding.accent_color = scheme[2]
		team.roster.max_size = maxi(FcRoster.DEFAULT_MAX_SIZE, config.roster_size)
		world.teams.add(team)
		teams.append(team)
		var country: String = entry["country"]
		_fill_roster(world, team, team_rng.fork("players"), used_names, reference, country)
		_hire_staff(world, team, team_rng.fork("staff"), used_names, reference, country)

	world.leagues.add(_build_league(world, teams, entries))
	_add_free_agents(world, root.fork("free_agents"), used_names, reference)
	return world


# --- league structure ------------------------------------------------------

## Groups teams geographically: conferences split west to east (by longitude),
## then each conference splits south to north (by latitude) into divisions.
## Sizes are as even as possible. A league mixing North America and Europe
## naturally gets Americas/Europe-style conferences.
func _build_league(world: FcWorld, teams: Array[FcTeam], entries: Array) -> FcLeague:
	var league := FcLeague.new(world.ids.next_id(FcWorld.KIND_LEAGUE), config.league_name)
	var order: Array = range(teams.size())
	order.sort_custom(func(a, b):
		var lon_a := float(entries[a]["lon"])
		var lon_b := float(entries[b]["lon"])
		return lon_a < lon_b if lon_a != lon_b else a < b)

	var conf_count := config.conference_count
	var div_count := config.divisions_per_conference
	var conf_sizes := _even_split(teams.size(), conf_count)
	var cursor := 0
	for c in conf_count:
		var members: Array = order.slice(cursor, cursor + conf_sizes[c])
		cursor += conf_sizes[c]
		members.sort_custom(func(a, b):
			var lat_a := float(entries[a]["lat"])
			var lat_b := float(entries[b]["lat"])
			return lat_a < lat_b if lat_a != lat_b else a < b)
		var conference := FcConference.new(world.ids.next_id(FcWorld.KIND_CONFERENCE), _conference_name(c, conf_count))
		var div_sizes := _even_split(members.size(), div_count)
		var d_cursor := 0
		for d in div_count:
			var division := FcDivision.new(world.ids.next_id(FcWorld.KIND_DIVISION), _division_name(d, div_count, conference.name))
			for idx in members.slice(d_cursor, d_cursor + div_sizes[d]):
				division.team_ids.append(teams[idx].id)
			d_cursor += div_sizes[d]
			conference.divisions.append(division)
		league.conferences.append(conference)
	return league


static func _even_split(total: int, parts: int) -> Array[int]:
	var out: Array[int] = []
	var base := floori(float(total) / parts)
	var extra := total % parts
	for i in parts:
		out.append(base + (1 if i < extra else 0))
	return out


static func _conference_name(index: int, count: int) -> String:
	if CONFERENCE_NAMES.has(count):
		return CONFERENCE_NAMES[count][index]
	return "Conference %s" % char(65 + index)


static func _division_name(index: int, count: int, conference_name: String) -> String:
	if count == 1:
		return conference_name
	if DIVISION_NAMES.has(count):
		return DIVISION_NAMES[count][index]
	return "Division %s" % char(65 + index)


# --- cities, arenas, teams -------------------------------------------------

func _make_city(world: FcWorld, entry: Dictionary) -> FcCity:
	var c := FcCity.new(world.ids.next_id(FcWorld.KIND_CITY))
	c.name = str(entry["name"])
	c.region = str(entry["region"])
	c.country = _names.country_name(str(entry["country"]))
	c.area = str(entry["area"])
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
	var initials := ""
	var new_word := true
	for ch in city_name.to_upper():
		var plain: String = LETTER_FOLDING.get(ch, ch)
		if plain >= "A" and plain <= "Z":
			letters += plain
			if new_word:
				initials += plain
			new_word = false
		else:
			new_word = true
	var candidates: Array[String] = [letters.substr(0, 3)]
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

func _fill_roster(world: FcWorld, team: FcTeam, rng: FcRng, used_names: Dictionary, reference: FcDate, team_country: String) -> void:
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
		spec.country_key = _names.pick_origin(rng, team_country, config.home_country_share)
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
		spec.country_key = _names.pick_origin(rng, "", 0.0)
		spec.reference_date = reference
		spec.used_names = used_names
		world.players.add(_players.generate(rng, world.ids.next_id(FcWorld.KIND_PLAYER), spec))


## An evenly spread, shuffled list of positions (PG,SG,SF,PF,C repeating).
func _roster_positions(rng: FcRng, count: int) -> Array[int]:
	var list: Array[int] = []
	for i in count:
		list.append(FcPosition.Id.PG + (i % 5))
	return _shuffled(rng, list)


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

func _hire_staff(world: FcWorld, team: FcTeam, rng: FcRng, used_names: Dictionary, reference: FcDate, team_country: String) -> void:
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
			# Staff are mostly local: the league's own country, sometimes anywhere.
			var origin := _names.pick_origin(rng, team_country, 0.8)
			var member := _staff.generate(rng, world.ids.next_id(FcWorld.KIND_STAFF), int(job[0]), level, reference, used_names, origin)
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
