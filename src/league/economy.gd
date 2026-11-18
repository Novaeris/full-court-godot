class_name FcEconomy
extends RefCounted
## The long-run economy of a league (milestone M2). Without it a fixed cap and rising fan interest let
## profit and cash grow without limit over 50 seasons. Every offseason:
##   1. INFLATION: the league's money (ticket prices, sponsors, TV, costs) grows by a yearly rate
##      (about 3% with some seeded variation and the odd flat "recession" year).
##   2. THE CAP FOLLOWS THE BUSINESS: the salary cap is the economy times a "players' share" that moves
##      with league profit. Clubs earning more than the target margin push the share (so salaries) up;
##      clubs earning less slow it down. That is a simple version of how real leagues share revenue
##      with players, and it keeps the typical club's profit near the target forever.
##   3. CASH HAS PLACES TO GO: AI clubs spend cash above a reserve on arena projects (practice facility,
##      medical center, suites, seats, and a whole new arena when the old one has aged) and pay what is
##      left above a ceiling out to their owner as a dividend. The human owner does the same by choice.
## All numbers are in data/simulation/economy.json. Everything is seeded by league and year.

var world: FcWorld
var k: Dictionary = {}


func _init(game_world: FcWorld) -> void:
	world = game_world
	k = load_constants()


static func load_constants() -> Dictionary:
	var file := FileAccess.open("res://data/simulation/economy.json", FileAccess.READ)
	var parsed = FcChecks.parse_json(file.get_as_text()) if file != null else null
	return parsed if parsed is Dictionary else {}


## The inflation rate for the offseason after `finished_year` (the same every time for the same league and year).
func growth_rate(league_id: int, finished_year: int) -> float:
	var rng := FcRng.new(hash("economy:%d:%d" % [league_id, finished_year]))
	if rng.chance(float(k["recession_chance"])):
		return 0.0
	return maxf(0.0, float(k["base_growth"]) + rng.range_float(-float(k["growth_noise"]), float(k["growth_noise"])))


## The average profit margin (profit / revenue) of the teams' books for a season, or `fallback` if there are none.
func league_margin(league_id: int, year: int, fallback: float) -> float:
	var league: FcLeague = world.leagues.get_by_id(league_id)
	var in_league := {}
	for tid in league.all_team_ids():
		in_league[tid] = true
	var revenue := 0.0
	var profit := 0.0
	for r in world.finances.all():
		if r.year == year and in_league.has(r.team_id):
			revenue += r.total_revenue()
			profit += r.profit()
	return profit / revenue if revenue > 0.0 else fallback


## Grows the economy and moves the cap, then lets the AI clubs use their cash. Call once per offseason,
## after the season's books are settled and before contracts are renewed. Returns
## {"growth", "margin", "cap_before", "cap_after", "projects", "dividends"}.
func advance(league_id: int, finished_year: int, human_team_ids: Array[int] = []) -> Dictionary:
	var rules := world.rules_of_league(league_id)
	var finance := FcFinanceEngine.new(world)
	var reference_cap := float(finance.k["reference_cap"])
	var old_scale := finance.scale_for(rules)
	var cap_before := rules.cap.salary_cap
	var share_before := float(cap_before) / (old_scale * reference_cap)
	var growth := growth_rate(league_id, finished_year)
	var margin := league_margin(league_id, finished_year, float(k["margin_target"]))
	var step := clampf(float(k["margin_gain"]) * (margin - float(k["margin_target"])), float(k["cap_share_step_min"]), float(k["cap_share_step_max"]))
	var share := clampf(share_before * (1.0 + step), float(k["cap_share_min"]), float(k["cap_share_max"]))
	var new_scale := old_scale * (1.0 + growth)
	rules.money_scale_ppm = roundi(new_scale * 1000000.0)
	# the cap never falls in money terms (a club's existing contracts would break it); a weak year just holds it
	var wanted_cap := maxf(float(cap_before), new_scale * reference_cap * share)
	if wanted_cap / cap_before - 1.0 > 0.0005:
		rules.cap.scale_money(wanted_cap / cap_before)
		_lift_minimum_contracts(rules.cap.min_player_salary, rules.cap.max_annual_raise_percent, finished_year)
	# the owner's own prices and marketing budget keep their place as money inflates (they stay the owner's choice,
	# but a forgotten price would otherwise fall further behind the market every year: found by the 50-season playthrough)
	var ratio := finance.scale_for(rules) / old_scale
	for tid in human_team_ids:
		var own: FcTeamBusiness = world.businesses.get_by_id(tid)
		if own != null:
			own.ticket_price = clampi(roundi(own.ticket_price * ratio), 1, 5000)
			own.marketing_budget = roundi(own.marketing_budget * ratio)
	var spent := _clubs_use_cash(league_id, finished_year, finance.scale_for(rules), rules.cap.salary_cap, human_team_ids)
	var report := {"growth": growth, "margin": margin, "cap_before": cap_before, "cap_after": rules.cap.salary_cap,
		"projects": spent["projects"], "dividends": spent["dividends"]}
	world.add_news(FcDate.new(finished_year + 1, 6, 1), "staff", "The league economy grew %.1f%%. The salary cap moves from $%.1fM to $%.1fM." % [
		100.0 * growth, cap_before / 1e6, rules.cap.salary_cap / 1e6])
	return report


## When the league minimum salary rises, deals that pay less than it are raised to the new minimum
## (from the season just finished on: the owner's offseason is still validated against that season), as a real league's minimum applies to everyone.
func _lift_minimum_contracts(minimum: int, max_raise_percent: int, from_year: int) -> void:
	for c in world.contracts.all():
		if c.status != FcContract.Status.ACTIVE:
			continue
		var previous := 0
		for y in c.years:
			if not y.is_in_effect():
				continue
			var previous_counts: bool = previous > 0 and y.season - 1 >= from_year
			if y.season >= from_year:
				if y.salary > 0 and y.salary < minimum:
					y.salary = minimum
				var raise_limit := roundi(previous * (100.0 + max_raise_percent) / 100.0)
				if previous_counts and y.salary > raise_limit:
					y.salary = maxi(minimum, raise_limit)
			previous = y.salary


## AI clubs: cash above the reserve starts building projects (most useful first, at most a couple a year), and
## cash above the ceiling is paid out to the owner. Returns {"projects": int, "dividends": int}.
func _clubs_use_cash(league_id: int, finished_year: int, scale: float, cap: int, human_team_ids: Array[int]) -> Dictionary:
	var finance := FcFinanceEngine.new(world)
	var league: FcLeague = world.leagues.get_by_id(league_id)
	var reserve := roundi(float(k["reserve_cap_share"]) * cap)
	var ceiling := roundi(float(k["dividend_cap_share"]) * cap)
	var order := ["practice_facility", "medical_center", "luxury_suites", "new_arena", "expand_seating"]
	var projects := 0
	var dividends := 0
	for tid in league.all_team_ids():
		if human_team_ids.has(tid):
			continue
		var business: FcTeamBusiness = world.businesses.get_by_id(tid)
		if business == null or business.debt > 0:
			continue
		var arena: FcArena = world.arenas.get_by_id(world.teams.get_by_id(tid).arena_id)
		var started := 0
		for key in order:
			if started >= int(k["projects_per_year"]):
				break
			var def := FcFinanceEngine.project_def(key)
			if def.is_empty() or business.cash - roundi(float(def["cost"]) * scale) < reserve:
				continue
			if finance.start_project(business, arena, key, scale) == "":
				started += 1
				projects += 1
		if business.cash > ceiling:
			var payout := business.cash - ceiling
			business.cash -= payout
			business.distributions += payout
			dividends += payout
	return {"projects": projects, "dividends": dividends}
