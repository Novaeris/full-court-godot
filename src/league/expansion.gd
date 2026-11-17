class_name FcExpansion
extends RefCounted
## League expansion (D-031: up to 64 teams): new franchises join in cities the league does not
## use yet, the conferences and divisions are redrawn for the new size, and the existing owners
## share an expansion fee. The new teams fill their rosters in an expansion draft: every existing team
## protects PROTECTED_PER_TEAM players, the new teams then take turns picking the best unprotected
## player, and no existing team loses more than one player. Spots still empty are filled with
## weaker generated players. The new teams also get a staff, an arena and a business, exactly like
## the teams the league started with. The plan (which size, which cities) is derived from the league and
## the year, so it can be shown to the owners before the vote and carried out identically after.

const MIN_GAP_YEARS := 3
## Players each existing team may protect from the expansion draft.
const PROTECTED_PER_TEAM := 8
## The fee each new franchise pays, as a share of the average franchise value; the existing owners split it.
const FEE_SHARE_OF_VALUE := 0.30
## New teams start weaker: their players are rated this much lower than a founding team's.
const WEAKER_BY := 5.0

var world: FcWorld
var league_id: int
var data := FcGenerationData.load_default()


func _init(game_world: FcWorld, league: int) -> void:
	world = game_world
	league_id = league


## The next size the league could grow to and where the new teams would be, or {} if it cannot grow
## (already at the ceiling, no valid size, or too few unused cities).
## {"size", "delta", "cities": [city entries from the data]}.
func plan(year: int) -> Dictionary:
	var league: FcLeague = world.leagues.get_by_id(league_id)
	var current := league.team_count()
	var size := 0
	for count in FcLeagueStructure.valid_team_counts():
		if count >= current + 2 and count <= FcLeagueStructure.MAX_TEAMS_IN_SAVE and not FcLeagueStructure.valid_structures(count).is_empty():
			size = count
			break
	if size == 0:
		return {}
	var delta := size - current
	var used := {}
	var areas := {}
	for tid in league.all_team_ids():   # a city a team has left is free again
		var c: FcCity = world.cities.get_by_id(world.teams.get_by_id(tid).city_id)
		used[c.name] = true
		areas[c.area] = true
	var candidates: Array = []
	for entry in data.world["cities"]:
		if areas.has(entry["area"]) and not used.has(str(entry["name"])):
			candidates.append(entry)
	if candidates.size() < delta:
		return {}
	candidates.sort_custom(func(a, b):
		if int(a["population"]) != int(b["population"]):
			return int(a["population"]) > int(b["population"])
		return str(a["name"]) < str(b["name"]))
	# among the biggest unused cities, a seeded pick
	var pool: Array = candidates.slice(0, mini(candidates.size(), delta * 3))
	var rng := FcRng.new(hash("expansion:%d:%d" % [league_id, year]))
	var cities: Array = []
	while cities.size() < delta:
		cities.append(pool.pop_at(rng.range_int(0, pool.size() - 1)))
	return {"size": size, "delta": delta, "cities": cities}


## The players an AI team protects (and the choice made for the owner if they do not choose): the
## best PROTECTED_PER_TEAM by market value.
func default_protected(team_id: int, year: int) -> Array[int]:
	var market := FcPlayerMarket.new(FcPlayerRatings.load_default())
	var scored: Array = []
	for pid in world.teams.get_by_id(team_id).roster.player_ids:
		var p: FcPlayer = world.players.get_by_id(pid)
		scored.append([market.value(p, p.age_on(FcDate.new(year + 1, 7, 1))), pid])
	scored.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	var out: Array[int] = []
	for entry in scored.slice(0, PROTECTED_PER_TEAM):
		out.append(entry[1])
	return out


## How many players each new team will take in the expansion draft.
func picks_per_new_team(delta: int, existing_count: int) -> int:
	return mini(world.rules_of_league(league_id).roster_min, floori(float(existing_count) / maxf(1.0, delta)))


## The fee each existing owner receives if the league expands (dollars).
func fee_per_owner(plan_delta: int) -> int:
	var total := 0.0
	var count := 0
	for tid in world.leagues.get_by_id(league_id).all_team_ids():
		var b: FcTeamBusiness = world.businesses.get_by_id(tid)
		if b != null:
			total += b.valuation
			count += 1
	if count == 0:
		return 0
	return roundi(total / count * FEE_SHARE_OF_VALUE * plan_delta / count / 100000.0) * 100000


## Carries out the expansion for the season starting after `year`, including the expansion draft.
## `user_protected` is the list the player chose for `user_team_id` (empty = the default choice).
## Returns {} if there is no plan, else {"teams": [new team ids], "size", "fee_each",
## "picks": [[pick number, new team id, player id, team he came from], ...]}.
func execute(year: int, user_team_id: int = 0, user_protected: Array = []) -> Dictionary:
	var plan_data := plan(year)
	if plan_data.is_empty():
		return {}
	var league: FcLeague = world.leagues.get_by_id(league_id)
	var rules := world.rules_of_league(league_id)
	var existing_ids := league.all_team_ids()
	var fee_each := fee_per_owner(plan_data["delta"])
	var new_year := year + 1
	var rng := FcRng.new(hash("expansion-teams:%d:%d" % [league_id, year]))

	var cfg := FcGenerationConfig.load_default(data)
	cfg.start_season = new_year
	cfg.roster_size = rules.roster_min
	cfg.roster_min = rules.roster_min
	cfg.roster_max = rules.roster_max
	cfg.top_player_level -= WEAKER_BY
	cfg.bottom_player_level -= WEAKER_BY
	var gen := FcWorldGenerator.new(data, world.definitions, cfg)
	var reference := FcDate.new(new_year, 7, 1)

	var used_names := {}
	for p in world.players.all():
		used_names[p.identity.full_name()] = true
	for m in world.staff.all():
		used_names[m.identity.full_name()] = true
	var used_abbreviations := {}
	var used_nicknames := {}
	var used_arena_names := {}
	for t in world.teams.all():
		used_abbreviations[t.identity.abbreviation] = true
		used_nicknames[t.identity.nickname] = true
	for a in world.arenas.all():
		used_arena_names[a.name] = true
	var nicknames: Array = []
	for nick in gen._shuffled(rng.fork("nicknames"), data.world["nicknames"]):
		if not used_nicknames.has(nick):
			nicknames.append(nick)
	var schemes: Array = gen._shuffled(rng.fork("colors"), data.world["color_schemes"])

	var new_teams: Array[FcTeam] = []
	for i in plan_data["delta"]:
		var entry: Dictionary = plan_data["cities"][i]
		var team_rng := rng.fork("team:%d" % i)
		var city := gen._make_city(world, entry)
		var arena := gen._make_arena(world, team_rng, city, used_arena_names)
		var team := FcTeam.new(world.ids.next_id(FcWorld.KIND_TEAM))
		team.city_id = city.id
		team.arena_id = arena.id
		team.identity.nickname = str(nicknames[i]) if i < nicknames.size() else "Team %d" % (league.team_count() + i + 1)
		team.identity.abbreviation = gen._make_abbreviation(city.name, used_abbreviations)
		team.identity.founded_year = new_year
		var scheme: Array = schemes[i % schemes.size()]
		team.branding.primary_color = scheme[0]
		team.branding.secondary_color = scheme[1]
		team.branding.accent_color = scheme[2]
		team.roster.max_size = rules.roster_max
		world.teams.add(team)
		new_teams.append(team)
		gen._hire_staff(world, team, team_rng.fork("staff"), used_names, reference, str(entry["country"]))

	# the expansion draft, then generated players for the spots it leaves empty
	var protected_map := {}
	for tid in existing_ids:
		protected_map[tid] = user_protected if (tid == user_team_id and not user_protected.is_empty()) else default_protected(tid, year)
	var picks := _expansion_draft(new_teams, existing_ids, protected_map, new_year, user_team_id, rng.fork("draft"))
	for i in new_teams.size():
		_add_filler(gen, new_teams[i], rules.roster_min - new_teams[i].roster.size(), rng.fork("filler%d" % i), used_names, reference, str(plan_data["cities"][i]["country"]), rules.cap)

	# the league is redrawn for its new size: conferences west to east, divisions south to north
	var structure := _structure_for(plan_data["size"], league.conferences.size())
	gen.config.conference_count = structure["conferences"]
	gen.config.divisions_per_conference = structure["divisions_per_conference"]
	var all_ids: Array[int] = existing_ids.duplicate()
	for t in new_teams:
		all_ids.append(t.id)
	redraw(all_ids, structure)

	# the rules still have to fit the new league
	var games := rules.season.games_per_team(league)
	rules.season = FcSeasonRules.suggest(league, games)
	if not rules.playoffs.validate(league).is_empty():
		rules.playoffs = FcPlayoffRules.suggest(league)
	if rules.draft.lottery_teams > 0:
		rules.draft = FcDraftRules.suggest(league.team_count())

	# businesses for the new teams, and the fee for the old ones
	var finance := FcFinanceEngine.new(world)
	var money_scale := finance.scale_for(rules)
	var price_scale := finance.price_scale_for(rules, league)
	for t in new_teams:
		world.businesses.add(finance.initial_business(t, money_scale, price_scale))
	for tid in existing_ids:
		var b: FcTeamBusiness = world.businesses.get_by_id(tid)
		if b != null:
			b.cash += fee_each
	var ids: Array[int] = []
	var names: Array[String] = []
	for t in new_teams:
		ids.append(t.id)
		names.append(world.team_display_name(t.id))
	world.add_news(FcDate.new(new_year, 6, 1), "staff", "The league expands to %d teams: %s join. Each existing owner receives an expansion fee of $%.1fM." % [plan_data["size"], " and ".join(names), fee_each / 1e6])
	return {"teams": ids, "size": plan_data["size"], "fee_each": fee_each, "picks": picks}


## The draft itself: the new teams take turns (in a seeded order), each picking the most valuable
## player who is not protected and whose team has not lost anyone yet.
func _expansion_draft(new_teams: Array[FcTeam], existing_ids: Array[int], protected_map: Dictionary, new_year: int, user_team_id: int, rng: FcRng) -> Array:
	var market := FcPlayerMarket.new(FcPlayerRatings.load_default())
	var per_team := picks_per_new_team(new_teams.size(), existing_ids.size())
	var order: Array = []
	for t in new_teams:
		order.append(t)
	var shuffled: Array = FcWorldGenerator.new(data, world.definitions, FcGenerationConfig.load_default(data))._shuffled(rng, order)
	var lost := {}
	var picks: Array = []
	for round_number in per_team:
		for team in shuffled:
			var best := 0
			var best_from := 0
			var best_value := -INF
			for tid in existing_ids:
				if lost.has(tid):
					continue
				for pid in world.teams.get_by_id(tid).roster.player_ids:
					var contract := world.active_contract_of(pid)
					if pid in protected_map[tid] or contract == null or contract.end_season() < new_year:
						continue   # protected, or a contract that is about to run out
					var p: FcPlayer = world.players.get_by_id(pid)
					var v := market.value(p, p.age_on(FcDate.new(new_year, 7, 1)))
					if v > best_value or (v == best_value and pid < best):
						best_value = v
						best = pid
						best_from = tid
			if best == 0:
				continue
			world.teams.get_by_id(best_from).roster.remove(best)
			team.roster.add(best)
			world.active_contract_of(best).team_id = team.id
			lost[best_from] = true
			picks.append([picks.size() + 1, team.id, best, best_from])
			if best_from == user_team_id:
				world.add_news(FcDate.new(new_year, 6, 2), "signing", "%s was taken by %s in the expansion draft." % [world.player_name(best), world.team_display_name(team.id)], user_team_id)
	return picks


## Fills the empty roster spots of a new team with weaker young players on ordinary contracts.
func _add_filler(gen: FcWorldGenerator, team: FcTeam, count: int, rng: FcRng, used_names: Dictionary, reference: FcDate, country: String, cap: FcCapRules) -> void:
	for i in maxi(0, count):
		var spec := FcPlayerSpec.new()
		spec.age = rng.range_int(20, 27)
		spec.position = FcPosition.Id.PG + (i % 5)
		spec.level = clampf(rng.gaussian(40.0, 5.0), 25.0, 58.0)
		spec.country_key = gen._names.pick_origin(rng, country, gen.config.home_country_share)
		spec.reference_date = reference
		spec.used_names = used_names
		var player := gen._players.generate(rng, world.ids.next_id(FcWorld.KIND_PLAYER), spec)
		world.players.add(player)
		team.roster.add(player.id)
		world.contracts.add(gen._player_contract(world, rng, player.id, team.id, spec.level, cap))


## Draws the conferences (west to east) and divisions (south to north) of the league again for
## these teams from the coordinates of their cities. `structure` is one of the layouts from
## FcLeagueStructure.valid_structures.
func redraw(team_ids: Array[int], structure: Dictionary) -> void:
	var league: FcLeague = world.leagues.get_by_id(league_id)
	var cfg := FcGenerationConfig.load_default(data)
	cfg.conference_count = structure["conferences"]
	cfg.divisions_per_conference = structure["divisions_per_conference"]
	var gen := FcWorldGenerator.new(data, world.definitions, cfg)
	var by_name := {}
	for entry in data.world["cities"]:
		by_name[str(entry["name"])] = entry
	var teams: Array[FcTeam] = []
	var entries: Array = []
	for tid in team_ids:
		var t: FcTeam = world.teams.get_by_id(tid)
		teams.append(t)
		entries.append(by_name.get(world.cities.get_by_id(t.city_id).name, {"lat": 0.0, "lon": 0.0}))
	league.conferences = gen._build_league(world, teams, entries).conferences


## The conference/division layout for a size, keeping the number of conferences if possible.
func _structure_for(size: int, conferences: int) -> Dictionary:
	var options := FcLeagueStructure.valid_structures(size)
	for option in options:
		if option["conferences"] == conferences:
			return option
	return options[0]
