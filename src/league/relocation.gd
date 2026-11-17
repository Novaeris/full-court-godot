class_name FcRelocation
extends RefCounted
## A franchise moving to another city (D-031): approved by the owners at the meeting (two thirds).
## Struggling AI teams ask on their own (losing money, a weak fan base); the player can propose a
## move of their own team. The move gives the team a new city and a new arena, costs it part of
## its fan base and brand, charges a relocation fee that is shared by the other owners, and the
## conferences and divisions are redrawn from the new map. The team keeps its name and players.

## A team does not move again within this many years.
const MIN_GAP_YEARS := 10
## The fee, as a share of the moving team's franchise value, split among the other owners.
const FEE_SHARE_OF_VALUE := 0.15
## The new arena's quality, and how much of the brand survives the move.
const NEW_ARENA_QUALITY := 75
const BRAND_KEPT := 0.85
## The chance in a year that a struggling AI team asks to move (when one qualifies).
const REQUEST_CHANCE := 0.35
## What counts as struggling: lost money last season and the fan base is below this.
const STRUGGLING_FAN_INTEREST := 45

var world: FcWorld
var league_id: int
var data := FcGenerationData.load_default()


func _init(game_world: FcWorld, league: int) -> void:
	world = game_world
	league_id = league


## Where a team would move: the biggest unused city of the areas the league already uses that is
## clearly bigger than its current one (a seeded choice among the best three). {} if there is none.
## {"city": entry from the data}.
func plan(team_id: int, year: int) -> Dictionary:
	var team: FcTeam = world.teams.get_by_id(team_id)
	var current: FcCity = world.cities.get_by_id(team.city_id)
	var used := {}
	var areas := {}
	for tid in world.leagues.get_by_id(league_id).all_team_ids():
		var city: FcCity = world.cities.get_by_id(world.teams.get_by_id(tid).city_id)
		used[city.name] = true
		areas[city.area] = true
	var candidates: Array = []
	for entry in data.world["cities"]:
		if areas.has(entry["area"]) and not used.has(str(entry["name"])) and int(entry["population"]) > current.population * 1.1:
			candidates.append(entry)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a, b):
		if int(a["population"]) != int(b["population"]):
			return int(a["population"]) > int(b["population"])
		return str(a["name"]) < str(b["name"]))
	var top := candidates.slice(0, mini(3, candidates.size()))
	var rng := FcRng.new(hash("relocation:%d:%d" % [team_id, year]))
	return {"city": top[rng.range_int(0, top.size() - 1)]}


## The fee a team would pay and each of the other owners would receive.
func fee_for(team_id: int) -> Dictionary:
	var business: FcTeamBusiness = world.businesses.get_by_id(team_id)
	var others: int = world.leagues.get_by_id(league_id).team_count() - 1
	var fee := roundi((business.valuation if business != null else 0) * FEE_SHARE_OF_VALUE / 100000.0) * 100000
	return {"fee": fee, "each": roundi(float(fee) / maxf(1.0, others) / 100000.0) * 100000}


## May this team move (not within MIN_GAP_YEARS of its last move)? `log` is [[year, team id, ...], ...].
func allowed(team_id: int, year: int, log: Array) -> bool:
	for row in log:
		if row[1] == team_id and year - row[0] < MIN_GAP_YEARS:
			return false
	return not plan(team_id, year).is_empty()


## The AI team most in need of a move this year (it lost money last season, its fan base is weak,
## and it may move), or 0. The player's own team is never chosen: the player proposes for it.
func struggling_team(year: int, user_team_id: int, log: Array) -> int:
	var finance := FcFinanceEngine.new(world)
	var worst := 0
	var worst_profit := INF
	for tid in world.leagues.get_by_id(league_id).all_team_ids():
		if tid == user_team_id or not allowed(tid, year, log):
			continue
		var business: FcTeamBusiness = world.businesses.get_by_id(tid)
		var rec := finance.record_of(tid, year)
		if business == null or rec == null or rec.profit() >= 0 or business.fan_interest >= STRUGGLING_FAN_INTEREST:
			continue
		if rec.profit() < worst_profit:
			worst_profit = rec.profit()
			worst = tid
	return worst


## Moves the team. Returns {} if it cannot, else {"team", "from", "to", "fee"}.
func execute(team_id: int, year: int) -> Dictionary:
	var plan_data := plan(team_id, year)
	if plan_data.is_empty():
		return {}
	var team: FcTeam = world.teams.get_by_id(team_id)
	var business: FcTeamBusiness = world.businesses.get_by_id(team_id)
	var league: FcLeague = world.leagues.get_by_id(league_id)
	var rules := world.rules_of_league(league_id)
	var old_city: FcCity = world.cities.get_by_id(team.city_id)
	var entry: Dictionary = plan_data["city"]
	var gen := FcWorldGenerator.new(data, world.definitions, FcGenerationConfig.load_default(data))
	var rng := FcRng.new(hash("relocation-arena:%d:%d" % [team_id, year]))
	var used_arena_names := {}
	for a in world.arenas.all():
		used_arena_names[a.name] = true
	var used_abbreviations := {}
	for t in world.teams.all():
		if t.id != team_id:
			used_abbreviations[t.identity.abbreviation] = true
	var city := gen._make_city(world, entry)
	var arena := gen._make_arena(world, rng, city, used_arena_names)
	team.city_id = city.id
	team.arena_id = arena.id
	team.identity.abbreviation = gen._make_abbreviation(city.name, used_abbreviations)

	# a new market, a new arena, a smaller fan base
	var finance := FcFinanceEngine.new(world)
	var market := finance.market_factor(city)
	var base_interest := clampi(roundi(42.0 + 10.0 * (market - 1.0)), 30, 70)
	if business != null:
		business.fan_interest = clampi(roundi(0.5 * business.fan_interest + 0.5 * base_interest) - 5, 5, 100)
		business.brand = clampi(roundi(business.brand * BRAND_KEPT), 5, 100)
		business.facilities_level = NEW_ARENA_QUALITY
		business.projects = []   # arena projects were for the old building
		business.suites_level = 0
		# the fee goes to the other owners
		var fees := fee_for(team_id)
		var paid := mini(business.cash, fees["fee"])
		business.cash -= paid
		business.debt += fees["fee"] - paid
		for tid in league.all_team_ids():
			if tid != team_id:
				var other: FcTeamBusiness = world.businesses.get_by_id(tid)
				if other != null:
					other.cash += fees["each"]

	# the map changed: conferences and divisions are drawn again for the same number of teams
	var expansion := FcExpansion.new(world, league_id)
	expansion.redraw(league.all_team_ids(), expansion._structure_for(league.team_count(), league.conferences.size()))
	var fee_paid: int = fee_for(team_id)["fee"]
	world.add_news(FcDate.new(year + 1, 6, 1), "staff", "The %s move from %s to %s. The other owners share a relocation fee of $%.1fM." % [team.identity.nickname, old_city.name, city.name, fee_paid / 1e6], team_id)
	if not rules.validate(league).is_empty():
		rules.playoffs = FcPlayoffRules.suggest(league)
		rules.season = FcSeasonRules.suggest(league, rules.season.games_per_team(league))
	return {"team": team_id, "from": old_city.name, "to": city.name, "fee": fee_paid}
