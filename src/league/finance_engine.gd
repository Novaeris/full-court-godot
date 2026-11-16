class_name FcFinanceEngine
extends RefCounted
## The business model: what a team earns and spends in a season, and how its
## fan interest, brand, cash, debt and valuation change. All constants are in
## data/simulation/finance.json (scaled by the league's salary cap).
##
## DEMAND: fans willing to attend a game = arena capacity x (a base of how much
## the city cares about the team) x market size x local wealth x arena quality,
## and falls as the ticket price rises (price elasticity). Attendance is
## demand limited by capacity. The best price for revenue is where demand just
## fills the arena (above it, attendance falls faster than the price rises).
##
## SUCCESS FEEDS BUSINESS: winning and playoff runs raise fan interest, which
## lifts attendance, brand, merchandise and sponsorship. Payroll, luxury tax,
## staff, arena upkeep and marketing cost money. A shortfall becomes debt.
## Teams in `human_teams` keep the owner's own price and marketing decisions;
## AI teams set a revenue-maximizing price and default marketing each season.

var world: FcWorld
var k: Dictionary = {}


func _init(game_world: FcWorld) -> void:
	world = game_world
	k = load_constants()


## The arena project definitions: {"projects": [...], "suite_event_bonus": float}.
static func load_arena_projects() -> Dictionary:
	var file := FileAccess.open("res://data/simulation/arena_projects.json", FileAccess.READ)
	var parsed = FcChecks.parse_json(file.get_as_text()) if file != null else null
	return parsed if parsed is Dictionary else {"projects": []}


static func project_def(key: String) -> Dictionary:
	for p in load_arena_projects()["projects"]:
		if p["key"] == key:
			return p
	return {}


## Starts a project if it exists, is not already running, is not already maxed out
## and the team can pay. Returns "" on success or the reason it cannot start.
func start_project(business: FcTeamBusiness, arena: FcArena, key: String, scale: float) -> String:
	var def := project_def(key)
	if def.is_empty():
		return "Unknown project."
	for p in business.projects:
		if p["key"] == key:
			return "That project is already under way."
	if def.has("max_capacity") and arena.capacity + int(def["capacity"]) > int(def["max_capacity"]):
		return "The arena cannot grow beyond %d seats." % int(def["max_capacity"])
	if def.has("max_suites") and business.suites_level >= int(def["max_suites"]):
		return "All suite levels are already built."
	if def.has("facilities") and business.facilities_level >= 100:
		return "The arena is already in perfect condition."
	var cost := roundi(float(def["cost"]) * scale)
	if cost > business.cash:
		return "You need %s in cash (you can borrow on the Finances tab)." % ("$%.1fM" % (cost / 1e6))
	business.cash -= cost
	business.projects.append({"key": key, "seasons_left": int(def["seasons"])})
	return ""


## Called at the end of each season: projects move closer to done and apply their effect when finished.
func advance_projects(business: FcTeamBusiness, arena: FcArena, team_id: int, year: int) -> void:
	var remaining: Array = []
	for p in business.projects:
		p["seasons_left"] = int(p["seasons_left"]) - 1
		if p["seasons_left"] > 0:
			remaining.append(p)
			continue
		var def := project_def(p["key"])
		if def.has("capacity"):
			arena.capacity = mini(int(def["max_capacity"]), arena.capacity + int(def["capacity"]))
		if def.has("suites"):
			business.suites_level = mini(int(def["max_suites"]), business.suites_level + int(def["suites"]))
		if def.has("facilities"):
			business.facilities_level = mini(100, business.facilities_level + int(def["facilities"]))
		world.add_news(FcDate.new(year + 1, 6, 1), "staff", "%s finished a building project: %s" % [world.team_display_name(team_id), def.get("name", p["key"])], team_id)
	business.projects = remaining


static func load_constants() -> Dictionary:
	var file := FileAccess.open("res://data/simulation/finance.json", FileAccess.READ)
	var parsed = FcChecks.parse_json(file.get_as_text()) if file != null else null
	return parsed if parsed is Dictionary else {}


func scale_for(rules: FcLeagueRules) -> float:
	return float(rules.cap.salary_cap) / float(k["reference_cap"])


## Per-game prices scale with season length so the economy balances at any
## season: a 40-game season has twice the ticket price of an 80-game one.
func price_scale_for(rules: FcLeagueRules, league: FcLeague) -> float:
	var home_games := maxf(1.0, rules.season.games_per_team(league) / 2.0)
	return scale_for(rules) * clampf(float(k["home_games_per_season"]) / home_games, 0.5, 4.0)


## Size and wealth of the team's market.
func market_factor(city: FcCity) -> float:
	var size := clampf(0.55 + 0.55 * sqrt(city.population / 3000000.0), 0.6, 1.8)
	return size * (0.8 + 0.4 * city.economy_index / 100.0)


## Fans willing to buy a ticket at `price` for a typical home game.
func demand(business: FcTeamBusiness, city: FcCity, arena: FcArena, scale: float, price: float) -> float:
	var interest := float(k["demand_interest_base"]) + float(k["demand_interest_slope"]) * business.fan_interest / 100.0
	var wealth := 0.8 + 0.4 * city.economy_index / 100.0
	var size := clampf(0.55 + 0.55 * sqrt(city.population / 3000000.0), 0.6, 1.8)
	var facilities := 1.0 + float(k["facilities_demand_bonus"]) * business.facilities_level / 100.0
	var base := arena.capacity * clampf(interest * size, 0.25, 2.0) * wealth * facilities
	var reference_price := float(k["reference_ticket_price"]) * scale
	return base * pow(reference_price / maxf(1.0, price), float(k["price_elasticity"]))


func attendance(business: FcTeamBusiness, city: FcCity, arena: FcArena, scale: float, price: float) -> int:
	return mini(arena.capacity, roundi(demand(business, city, arena, scale, price)))


## The price where demand just fills the arena (the best price for revenue).
func best_price(business: FcTeamBusiness, city: FcCity, arena: FcArena, scale: float) -> int:
	var reference_price := float(k["reference_ticket_price"]) * scale
	var ratio := demand(business, city, arena, scale, reference_price) / arena.capacity
	var p := reference_price * pow(maxf(ratio, 0.05), 1.0 / float(k["price_elasticity"]))
	return clampi(roundi(p), roundi(float(k["price_min"]) * scale), roundi(float(k["price_max"]) * scale))


## A new team's starting business, from its city and arena.
func initial_business(team: FcTeam, scale: float, price_scale: float = -1.0) -> FcTeamBusiness:
	var city: FcCity = world.cities.get_by_id(team.city_id)
	var arena: FcArena = world.arenas.get_by_id(team.arena_id)
	var b := FcTeamBusiness.new(team.id)
	b.fan_interest = clampi(roundi(42.0 + 10.0 * (market_factor(city) - 1.0)), 30, 70)
	b.brand = clampi(roundi(35.0 + 14.0 * (market_factor(city) - 1.0)), 20, 70)
	b.facilities_level = clampi(roundi(40.0 + (2026 - arena.year_built) * -0.6 + 25.0), 25, 85)
	b.marketing_budget = roundi(float(k["default_marketing"]) * scale)
	b.ticket_price = best_price(b, city, arena, scale if price_scale < 0.0 else price_scale)
	b.cash = roundi(float(k["starting_cash"]) * scale)
	b.valuation = estimated_valuation(b, scale)
	return b


## What a franchise is worth before it has played a season: a typical team's revenue
## (about 1.9 times the cap) times the same revenue multiple the books use later.
func estimated_valuation(business: FcTeamBusiness, scale: float) -> int:
	var revenue := 1.9 * float(k["reference_cap"]) * scale
	return roundi(revenue * (float(k["valuation_revenue_multiple"]) + float(k["valuation_brand_multiple"]) * business.brand / 100.0))


# --- owner actions ----------------------------------------------------------------

## Spends money to raise arena quality by `points` (cost per point from finance.json).
## Returns false (nothing changes) if the team cannot afford it.
func invest_in_facilities(business: FcTeamBusiness, points: int, scale: float) -> bool:
	points = clampi(points, 0, 100 - business.facilities_level)
	var cost := roundi(points * float(k["facilities_cost_per_point"]) * scale)
	if cost > business.cash or points <= 0:
		return false
	business.cash -= cost
	business.facilities_level += points
	return true


# --- the season's books ---------------------------------------------------------------

## Settles the finances of every team in the league for a finished season, updates each
## FcTeamBusiness and stores the FcFinanceRecords. Call after the playoffs, before the offseason.
func settle(league_id: int, season: FcSeason, human_teams: Array[int] = []) -> Array[FcFinanceRecord]:
	var league: FcLeague = world.leagues.get_by_id(league_id)
	var rules := world.rules_of_league(league_id)
	var cap := rules.cap
	var scale := scale_for(rules)
	var price_scale := price_scale_for(rules, league)
	var year := season.year
	var standings := FcStandings.compute(league, season.games)

	var rounds_won := {}
	var playoff_home := {}
	var po := season.playoffs
	if po != null:
		for s in po.series:
			if s.is_complete() and not s.is_bye:
				rounds_won[s.winner_id] = int(rounds_won.get(s.winner_id, 0)) + 1
	var regular_home := {}
	for g in season.games:
		if g.series > 0:
			playoff_home[g.home_id] = int(playoff_home.get(g.home_id, 0)) + 1
		elif g.played:
			regular_home[g.home_id] = int(regular_home.get(g.home_id, 0)) + 1

	var payrolls := {}
	var repeats := {}
	for tid in league.all_team_ids():
		payrolls[tid] = world.payroll_of_team(tid, year)
		repeats[tid] = _tax_seasons_in_last_four(tid, year)
	var shared := cap.distribute_luxury_tax(payrolls, repeats)

	# Revenue sharing: big markets pay and small markets receive, so every team can survive.
	# The transfers are based on market size and sum to zero over the league.
	var market_sum := 0.0
	for tid in league.all_team_ids():
		market_sum += market_factor(world.cities.get_by_id(world.teams.get_by_id(tid).city_id))
	var market_mean := market_sum / maxf(1.0, league.all_team_ids().size())

	var records: Array[FcFinanceRecord] = []
	for tid in league.all_team_ids():
		var team: FcTeam = world.teams.get_by_id(tid)
		var city: FcCity = world.cities.get_by_id(team.city_id)
		var arena: FcArena = world.arenas.get_by_id(team.arena_id)
		var business: FcTeamBusiness = world.businesses.get_by_id(tid)
		if business == null:
			business = initial_business(team, scale, price_scale)
			world.businesses.add(business)
		var human := human_teams.has(tid)
		if not human:
			business.ticket_price = best_price(business, city, arena, price_scale)
			business.marketing_budget = roundi(float(k["default_marketing"]) * scale * market_factor(city))
		var rec := FcFinanceRecord.new(world.ids.next_id(FcWorld.KIND_FINANCE))
		rec.team_id = tid
		rec.year = year
		rec.wins = standings.records[tid]["w"]
		rec.losses = standings.records[tid]["l"]
		rec.playoff_rounds_won = int(rounds_won.get(tid, 0))
		rec.capacity = arena.capacity
		rec.ticket_price = business.ticket_price

		var home_games: int = int(regular_home.get(tid, k["home_games_per_season"]))
		var fans := attendance(business, city, arena, price_scale, float(business.ticket_price))
		rec.average_attendance = fans
		var m := market_factor(city)
		var fac_factor := 0.8 + 0.4 * business.facilities_level / 100.0
		var po_games: int = int(playoff_home.get(tid, 0))
		var success := float(rec.playoff_rounds_won) / maxf(1.0, po.rounds if po != null else 1.0)

		rec.revenue["tickets"] = fans * business.ticket_price * home_games
		rec.revenue["playoffs"] = roundi(fans * business.ticket_price * float(k["playoff_ticket_premium"]) * po_games \
			+ fans * float(k["concessions_per_head"]) * price_scale * fac_factor * po_games)
		rec.revenue["concessions"] = roundi(fans * float(k["concessions_per_head"]) * price_scale * fac_factor * home_games)
		rec.revenue["merchandise"] = roundi(float(k["merchandise_base"]) * scale * pow(business.brand / 50.0, 1.2) * m)
		var plan_factor := 1.0 + 0.15 * success
		if business.sponsor_plan == 1:
			plan_factor = float(k["sponsor_steady_multiplier"])
		elif business.sponsor_plan == 2:
			plan_factor = float(k["sponsor_performance_base"]) + float(k["sponsor_performance_win_weight"]) * standings.win_pct(tid) + float(k["sponsor_performance_playoff_weight"]) * success
		rec.revenue["sponsorship"] = roundi(float(k["sponsorship_base"]) * scale * (0.5 + business.brand / 100.0) * pow(m, 0.8) * plan_factor)
		rec.revenue["broadcasting"] = roundi(float(k["broadcasting_per_team"]) * scale)
		rec.revenue["arena_events"] = roundi(float(k["arena_events_base"]) * scale * city.economy_index / 100.0 * arena.capacity / float(k["reference_capacity"]) * (1.0 + float(load_arena_projects().get("suite_event_bonus", 0.2)) * business.suites_level))
		rec.revenue["tax_share"] = int(shared["payouts"].get(tid, 0))
		var transfer := roundi(float(k["revenue_sharing_amount"]) * scale * (market_mean - m) / market_mean)
		if transfer >= 0:
			rec.revenue["revenue_sharing"] = transfer
		else:
			rec.expenses["revenue_sharing"] = -transfer

		var tax := cap.luxury_tax(payrolls[tid], repeats[tid])
		rec.paid_tax = tax > 0
		var staff_pay := 0
		for sc in world.staff_contracts_of_team(tid):
			staff_pay += sc.salary_for(year)
		rec.expenses["payroll"] = payrolls[tid]
		rec.expenses["luxury_tax"] = tax
		rec.expenses["staff"] = staff_pay
		rec.expenses["arena_operations"] = roundi(float(k["arena_operations"]) * scale * arena.capacity / float(k["reference_capacity"]))
		rec.expenses["marketing"] = business.marketing_budget
		rec.expenses["travel"] = roundi(float(k["travel"]) * scale)
		rec.expenses["administration"] = roundi(float(k["administration"]) * scale)
		rec.expenses["facilities"] = roundi(business.facilities_level * float(k["facilities_cost_per_point"]) * scale / 3.0)
		rec.expenses["interest"] = roundi(business.debt * float(k["debt_interest"]))

		# cash, debt, then the slow-moving brand values
		var profit := rec.profit()
		business.cash += profit
		if business.cash < 0:
			business.debt += -business.cash
			business.cash = 0
		elif business.debt > 0:
			var repay := mini(business.debt, roundi(business.cash * 0.5))
			business.debt -= repay
			business.cash -= repay
		var win_pct := standings.win_pct(tid)
		var star := clampf((_best_overall(tid) - 50.0) / 40.0, 0.0, 1.0)
		var interest_target := 25.0 + 55.0 * pow(win_pct, 0.9) + 12.0 * success + 8.0 * star
		business.fan_interest = clampi(roundi(business.fan_interest + float(k["interest_catchup"]) * (interest_target - business.fan_interest)), 5, 100)
		var marketing_effect := clampf(float(business.marketing_budget) / (12000000.0 * scale), 0.0, 1.0)
		var brand_target := 15.0 + 0.55 * business.fan_interest + 20.0 * marketing_effect + (8.0 if season.champion_id == tid else 0.0)
		business.brand = clampi(roundi(business.brand + float(k["brand_catchup"]) * (brand_target - business.brand)), 5, 100)
		business.facilities_level = clampi(roundi(business.facilities_level - float(k["facilities_decay"])), 0, 100)
		business.valuation = maxi(0, roundi(rec.total_revenue() * (float(k["valuation_revenue_multiple"]) + float(k["valuation_brand_multiple"]) * business.brand / 100.0)) - business.debt)

		rec.fan_interest_end = business.fan_interest
		rec.brand_end = business.brand
		rec.cash_end = business.cash
		rec.debt_end = business.debt
		advance_projects(business, arena, tid, year)
		rec.valuation_end = business.valuation
		world.finances.add(rec)
		records.append(rec)
	return records


func record_of(team_id: int, year: int) -> FcFinanceRecord:
	for r in world.finances.all():
		if r.team_id == team_id and r.year == year:
			return r
	return null


func _tax_seasons_in_last_four(team_id: int, year: int) -> int:
	var n := 0
	for r in world.finances.all():
		if r.team_id == team_id and r.year < year and r.year >= year - 4 and r.paid_tax:
			n += 1
	return n


func _best_overall(team_id: int) -> float:
	var ratings := FcPlayerRatings.load_default()
	var team: FcTeam = world.teams.get_by_id(team_id)
	var best := 0.0
	for pid in team.roster.player_ids:
		best = maxf(best, ratings.overall(world.players.get_by_id(pid)))
	return best
