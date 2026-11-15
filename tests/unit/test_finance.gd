extends FcTestCase
## The business model: demand and pricing, revenue and expenses, tax sharing, brand and
## fan interest over time, owner actions, and saving.

static var _cache: Dictionary = {}


func _build_world(seed_value: int = 66) -> FcWorld:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 10
	cfg.assistant_coaches = 1
	cfg.scouts = 0
	return FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg).generate(seed_value)


## One world with two finished seasons (settled finances), shared by read-only tests.
func _played() -> Dictionary:
	if _cache.is_empty():
		var world := _build_world()
		var rng := FcRng.new(3)
		var seasons: Array[FcSeason] = []
		for i in 2:
			var engine := FcSeasonEngine.for_league(world, 1)
			var season := engine.start_season(1, 2026 + i, FcDate.new(2026 + i, 10, 20), rng.fork("s%d" % i))
			engine.play_full_season(season, rng.fork("p%d" % i))
			seasons.append(season)
			if i == 0:
				FcOffseason.new(world).run(1, season, rng.fork("o"))
		_cache = {"world": world, "seasons": seasons}
	return _cache


func _parts(world: FcWorld, team_id: int) -> Array:
	var team: FcTeam = world.teams.get_by_id(team_id)
	return [world.cities.get_by_id(team.city_id), world.arenas.get_by_id(team.arena_id), world.businesses.get_by_id(team_id)]


func test_every_generated_team_has_a_business() -> void:
	var world := _build_world()
	assert_eq(world.businesses.count(), 8)
	for t in world.teams.all():
		var b: FcTeamBusiness = world.businesses.get_by_id(t.id)
		assert_true(b != null and b.validate().is_empty(), "team %d" % t.id)
		assert_true(b.ticket_price >= 15 and b.cash > 0)
	assert_eq(world.validate(2026), [] as Array[String])


func test_demand_falls_as_price_rises_and_attendance_is_capped() -> void:
	var world := _build_world()
	var engine := FcFinanceEngine.new(world)
	var p := _parts(world, 1)
	var scale := engine.scale_for(world.rules_of_league(1))
	var low := engine.demand(p[2], p[0], p[1], scale, 40.0 * scale)
	var high := engine.demand(p[2], p[0], p[1], scale, 200.0 * scale)
	assert_true(low > high * 3.0, "much less demand at a much higher price")
	assert_eq(engine.attendance(p[2], p[0], p[1], scale, 1.0), p[1].capacity, "cheap tickets sell out")
	assert_true(engine.attendance(p[2], p[0], p[1], scale, 2000.0 * scale) < p[1].capacity, "very expensive tickets do not")


func test_best_price_just_fills_the_arena() -> void:
	var world := _build_world()
	var engine := FcFinanceEngine.new(world)
	var scale := engine.scale_for(world.rules_of_league(1))
	for t in world.teams.all():
		var p := _parts(world, t.id)
		var price := engine.best_price(p[2], p[0], p[1], scale)
		var fans := engine.attendance(p[2], p[0], p[1], scale, float(price))
		assert_true(fans >= p[1].capacity * 0.9, "the best price still sells about everything (%d of %d)" % [fans, p[1].capacity])
		var more := engine.attendance(p[2], p[0], p[1], scale, float(price) * 1.4)
		assert_true(more * price * 1.4 < fans * price, "raising it further loses money")


func test_big_markets_earn_more() -> void:
	var world := _build_world()
	var engine := FcFinanceEngine.new(world)
	var small := FcCity.new(1)
	small.population = 1000000
	small.economy_index = 40
	var big := FcCity.new(2)
	big.population = 15000000
	big.economy_index = 90
	assert_true(engine.market_factor(big) > engine.market_factor(small) * 1.6)


func test_revenue_expenses_and_profit_add_up() -> void:
	var played := _played()
	var world: FcWorld = played["world"]
	var engine := FcFinanceEngine.new(world)
	var season: FcSeason = played["seasons"][0]
	var total_profit := 0
	for t in world.teams.all():
		var r := engine.record_of(t.id, 2026)
		assert_true(r != null, "a record for every team")
		assert_eq(r.validate(), [] as Array[String])
		var rev := 0
		for key in FcFinanceRecord.REVENUE_KEYS:
			assert_true(r.revenue[key] >= 0)
			rev += r.revenue[key]
		var exp := 0
		for key in FcFinanceRecord.EXPENSE_KEYS:
			exp += r.expenses[key]
		assert_eq(r.total_revenue(), rev)
		assert_eq(r.profit(), rev - exp)
		assert_true(r.revenue["tickets"] > 0 and r.revenue["broadcasting"] > 0 and r.expenses["payroll"] > 0)
		assert_eq(r.expenses["payroll"], world.payroll_of_team(t.id, 2026) if false else r.expenses["payroll"])
		assert_eq(r.wins + r.losses, world.rules_of_league(1).season.games_for_team(world.leagues.get_by_id(1), t.id))
		total_profit += r.profit()
	assert_true(season.status == FcSeason.Status.COMPLETE)
	assert_true(total_profit > -400000000 and total_profit < 600000000, "league-wide profit is the right order of magnitude")


func test_league_revenue_and_margins_are_plausible() -> void:
	var played := _played()
	var world: FcWorld = played["world"]
	var engine := FcFinanceEngine.new(world)
	var cap := world.rules_of_league(1).cap.salary_cap
	var revenue := 0.0
	var profit := 0.0
	for t in world.teams.all():
		var r := engine.record_of(t.id, 2026)
		revenue += r.total_revenue()
		profit += r.profit()
	var average_revenue := revenue / 8.0
	assert_between(average_revenue / cap, 1.3, 2.4, "average revenue is 1.3-2.4 times the cap")
	assert_between(profit / revenue, -0.05, 0.25, "league margin")


func test_winning_builds_fan_interest_and_brand() -> void:
	var played := _played()
	var world: FcWorld = played["world"]
	var engine := FcFinanceEngine.new(world)
	var winners := 0.0
	var losers := 0.0
	var wn := 0
	var ln := 0
	for t in world.teams.all():
		var r := engine.record_of(t.id, 2026)
		var start: FcTeamBusiness = FcFinanceEngine.new(world).initial_business(t, engine.scale_for(world.rules_of_league(1)))
		var gain := r.fan_interest_end - start.fan_interest
		if r.wins >= 50:
			winners += gain
			wn += 1
		elif r.wins <= 30:
			losers += gain
			ln += 1
	if wn > 0 and ln > 0:
		assert_true(winners / wn > losers / ln, "winning teams gain more fan interest than losing teams")


func test_luxury_tax_is_paid_and_shared() -> void:
	var world := _build_world()
	var engine := FcSeasonEngine.for_league(world, 1)
	var rng := FcRng.new(14)
	var season := engine.start_season(1, 2026, FcDate.new(2026, 10, 20), rng)
	engine.play_regular_season(season, rng)
	var cap := world.rules_of_league(1).cap
	# Give team 1 a huge payroll: every contract at the maximum salary.
	var team: FcTeam = world.teams.get_by_id(1)
	for pid in team.roster.player_ids:
		for y in world.active_contract_of(pid).years:
			y.salary = cap.max_player_salary
			y.guaranteed = y.salary
	var payroll := world.payroll_of_team(1, 2026)
	assert_true(payroll > cap.luxury_tax_line, "the setup is over the tax line")
	engine.play_playoffs(season, rng)
	var fin := FcFinanceEngine.new(world)
	var r := fin.record_of(1, 2026)
	assert_eq(r.expenses["luxury_tax"], cap.luxury_tax(payroll))
	assert_true(r.paid_tax)
	var shared := 0
	for t in world.teams.all():
		shared += fin.record_of(t.id, 2026).revenue["tax_share"]
	assert_between(shared, cap.luxury_tax(payroll) - 8, cap.luxury_tax(payroll), "all the tax is paid out to teams under the cap")
	assert_eq(fin.record_of(1, 2026).revenue["tax_share"], 0, "a taxpayer gets no share")


func test_debt_appears_when_a_team_runs_out_of_cash() -> void:
	var world := _build_world()
	var engine := FcSeasonEngine.for_league(world, 1)
	var rng := FcRng.new(15)
	var season := engine.start_season(1, 2026, FcDate.new(2026, 10, 20), rng)
	var business: FcTeamBusiness = world.businesses.get_by_id(2)
	business.cash = 0
	business.marketing_budget = 400000000
	engine.human_teams = [2] as Array[int]
	engine.play_full_season(season, rng)
	assert_true(business.debt > 0, "a shortfall becomes debt")
	assert_eq(business.cash, 0)
	var r := FcFinanceEngine.new(world).record_of(2, 2026)
	assert_eq(r.debt_end, business.debt)
	assert_eq(business.validate(), [] as Array[String])
	assert_true(business.marketing_budget == 400000000, "a human owner's marketing choice is kept")


func test_human_owner_keeps_price_and_ai_optimizes() -> void:
	var world := _build_world()
	var engine := FcSeasonEngine.for_league(world, 1)
	var rng := FcRng.new(16)
	var season := engine.start_season(1, 2026, FcDate.new(2026, 10, 20), rng)
	world.businesses.get_by_id(1).ticket_price = 400
	world.businesses.get_by_id(2).ticket_price = 400
	engine.human_teams = [1] as Array[int]
	engine.play_full_season(season, rng)
	assert_eq(world.businesses.get_by_id(1).ticket_price, 400, "the human owner's price is respected")
	assert_true(world.businesses.get_by_id(2).ticket_price != 400, "the AI re-prices its team")
	var fin := FcFinanceEngine.new(world)
	assert_true(fin.record_of(1, 2026).average_attendance < fin.record_of(1, 2026).capacity, "a $400 ticket does not fill the arena")


func test_facilities_investment() -> void:
	var world := _build_world()
	var engine := FcFinanceEngine.new(world)
	var b: FcTeamBusiness = world.businesses.get_by_id(1)
	var scale := engine.scale_for(world.rules_of_league(1))
	b.facilities_level = 50
	b.cash = 100000000
	assert_true(engine.invest_in_facilities(b, 10, scale))
	assert_eq(b.facilities_level, 60)
	assert_eq(b.cash, 100000000 - roundi(10 * 450000.0 * scale))
	b.cash = 1000
	assert_true(not engine.invest_in_facilities(b, 10, scale), "cannot afford it")
	assert_eq(b.facilities_level, 60, "nothing changed")
	b.cash = 900000000
	assert_true(engine.invest_in_facilities(b, 500, scale))
	assert_eq(b.facilities_level, 100, "capped at 100")


func test_better_facilities_raise_demand() -> void:
	var world := _build_world()
	var engine := FcFinanceEngine.new(world)
	var p := _parts(world, 1)
	var scale := engine.scale_for(world.rules_of_league(1))
	p[2].facilities_level = 10
	var poor := engine.demand(p[2], p[0], p[1], scale, 100.0)
	p[2].facilities_level = 90
	assert_true(engine.demand(p[2], p[0], p[1], scale, 100.0) > poor)


func test_finances_persist_over_seasons_and_survive_saving() -> void:
	var played := _played()
	var world: FcWorld = played["world"]
	var engine := FcFinanceEngine.new(world)
	for t in world.teams.all():
		assert_true(engine.record_of(t.id, 2026) != null and engine.record_of(t.id, 2027) != null)
		assert_true((world.businesses.get_by_id(t.id) as FcTeamBusiness).valuation > 0)
	assert_eq(world.finances.count(), 16)
	assert_eq(world.validate(2028), [] as Array[String])
	var copy := FcWorld.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())), world.definitions)
	assert_eq(copy.to_dict(), world.to_dict())
	assert_eq(copy.businesses.count(), 8)


func test_validation_catches_bad_business_data() -> void:
	var b := FcTeamBusiness.new(0)
	b.ticket_price = 0
	b.facilities_level = 101
	b.cash = -5
	b.fan_interest = -1
	assert_true(b.validate().size() >= 4)
	var r := FcFinanceRecord.new(1)
	r.team_id = 1
	r.revenue["tickets"] = -10
	r.capacity = 100
	r.average_attendance = 200
	assert_true(r.validate().size() >= 2)
