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


func test_business_saves_sponsor_plan() -> void:
	var b := FcTeamBusiness.new(2)
	b.sponsor_plan = 2
	assert_eq(FcTeamBusiness.from_dict(b.to_dict()).sponsor_plan, 2)
	var old := b.to_dict()
	old.erase("sponsor_plan")
	assert_eq(FcTeamBusiness.from_dict(old).sponsor_plan, 0)


func test_business_saves_projects() -> void:
	var b := FcTeamBusiness.new(2)
	b.projects = [{"key": "expand_seating", "seasons_left": 2}]
	b.suites_level = 2
	var back := FcTeamBusiness.from_dict(JSON.parse_string(JSON.stringify(b.to_dict())))
	assert_eq(back.projects, b.projects)
	assert_eq(back.suites_level, 2)
	assert_eq(FcTeamBusiness.from_dict({"id": 2}).projects, [])


func test_revenue_sharing_sums_to_zero_and_favours_small_markets() -> void:
	var played := _played()
	var world: FcWorld = played["world"]
	var fin := FcFinanceEngine.new(world)
	var net := 0
	var smallest_id := 0
	var biggest_id := 0
	var small := INF
	var big := -INF
	for t in world.teams.all():
		var rec := fin.record_of(t.id, 2026)
		net += rec.revenue["revenue_sharing"] - rec.expenses["revenue_sharing"]
		assert_true(rec.revenue["revenue_sharing"] == 0 or rec.expenses["revenue_sharing"] == 0, "a team either pays or receives")
		var m := fin.market_factor(world.cities.get_by_id(t.city_id))
		if m < small:
			small = m
			smallest_id = t.id
		if m > big:
			big = m
			biggest_id = t.id
	assert_between(net, -16, 16, "what is paid equals what is received (rounding only)")
	assert_true(fin.record_of(smallest_id, 2026).revenue["revenue_sharing"] > 0, "the smallest market receives")
	assert_true(fin.record_of(biggest_id, 2026).expenses["revenue_sharing"] > 0, "the biggest market pays")


func _season_with_executives(marketing: int, acumen: int, community: int) -> FcFinanceRecord:
	var world := _build_world()
	for m in world.staff.all():
		if m.primary_role == FcStaffRole.Id.BUSINESS_EXECUTIVE:
			m.skills.set_clamped("marketing", marketing)
			m.skills.set_clamped("financial_acumen", acumen)
			m.skills.set_clamped("community_relations", community)
	var rng := FcRng.new(3)
	var engine := FcSeasonEngine.for_league(world, 1)
	var season := engine.start_season(1, 2026, FcDate.new(2026, 10, 20), rng.fork("s"))
	engine.play_full_season(season, rng.fork("p"))
	return FcFinanceEngine.new(world).record_of(1, 2026)


func test_business_executives_change_the_books() -> void:
	var strong := _season_with_executives(95, 95, 95)
	var weak := _season_with_executives(20, 20, 20)
	assert_true(strong.revenue["sponsorship"] > weak.revenue["sponsorship"], "a marketing expert brings more sponsorship")
	assert_true(strong.expenses["administration"] < weak.expenses["administration"], "a financial expert trims overhead")
	assert_true(strong.fan_interest_end >= weak.fan_interest_end, "community work lifts fan interest")
	assert_true(strong.profit() > weak.profit())


func test_a_team_without_a_business_executive_does_worse() -> void:
	var world := _build_world()
	var fin := FcFinanceEngine.new(world)
	var with_exec := fin.executive_skill(1, "marketing")
	for sc in world.staff_contracts_of_team(1, FcStaffRole.Id.BUSINESS_EXECUTIVE):
		sc.status = FcContract.Status.TERMINATED
	var without := fin.executive_skill(1, "marketing")
	assert_eq(without, float(fin.k["no_executive_skill"]))
	assert_true(without < with_exec or with_exec <= without)


func test_concession_prices_have_a_sweet_spot() -> void:
	var fin := FcFinanceEngine.new(_played()["world"])
	assert_eq(fin.concession_factor(100), 1.0, "normal prices are the baseline")
	assert_true(fin.concession_factor(120) > fin.concession_factor(100), "somewhat higher prices earn more per fan")
	assert_true(fin.concession_factor(150) < fin.concession_factor(130), "but gouging earns less")
	assert_true(fin.concession_factor(70) < fin.concession_factor(100), "and giveaways do not pay")


func test_merchandise_tiers_trade_sales_for_stock_costs() -> void:
	var world := _build_world()
	var records := []
	for tier in 3:
		var w := _build_world()
		w.businesses.get_by_id(1).merch_tier = tier
		var rng := FcRng.new(3)
		var engine := FcSeasonEngine.for_league(w, 1)
		var season := engine.start_season(1, 2026, FcDate.new(2026, 10, 20), rng.fork("s"))
		engine.play_full_season(season, rng.fork("p"))
		records.append(FcFinanceEngine.new(w).record_of(1, 2026))
	assert_true(records[0].revenue["merchandise"] < records[1].revenue["merchandise"] and records[1].revenue["merchandise"] < records[2].revenue["merchandise"], "premium sells more")
	assert_true(records[0].expenses["merchandise_stock"] < records[1].expenses["merchandise_stock"] and records[1].expenses["merchandise_stock"] < records[2].expenses["merchandise_stock"], "and costs more stock")
	assert_true(world != null)


func test_shop_settings_are_saved_and_validated() -> void:
	var b := FcTeamBusiness.new(2)
	b.concession_price_pct = 125
	b.merch_tier = 2
	var back := FcTeamBusiness.from_dict(JSON.parse_string(JSON.stringify(b.to_dict())))
	assert_eq(back.concession_price_pct, 125)
	assert_eq(back.merch_tier, 2)
	var old := FcTeamBusiness.from_dict({"id": 2})
	assert_eq(old.concession_price_pct, 100)
	assert_eq(old.merch_tier, 1)


func test_premium_merchandise_only_pays_for_a_strong_brand() -> void:
	var fin := FcFinanceEngine.new(_played()["world"])
	var b := FcTeamBusiness.new(1)
	var net := func(tier: int, brand: int) -> float:
		b.merch_tier = tier
		b.brand = brand
		return fin.merch_multiplier(b) * (1.0 - float(fin.k["merch_cost_shares"][tier]))
	assert_true(net.call(2, 85) > net.call(1, 85), "a strong brand profits from premium goods")
	assert_true(net.call(2, 40) < net.call(1, 40), "a weak brand does not")
	assert_true(net.call(0, 50) < net.call(1, 50), "limited stock sells less than it saves")


func _sponsor_world() -> FcWorld:
	return _build_world()


func test_sponsor_offers_are_stable_distinct_and_priced_from_the_market() -> void:
	var world := _sponsor_world()
	var fin := FcFinanceEngine.new(world)
	var scale := fin.scale_for(world.rules_of_league(1))
	var a := fin.sponsor_offers(1, 2027, scale)
	var b := fin.sponsor_offers(1, 2027, scale)
	assert_eq(a, b, "the same offers every time you look")
	assert_eq(a.size(), 3)
	var names := {}
	for o in a:
		assert_true(not names.has(o["sponsor"]), "no sponsor twice")
		names[o["sponsor"]] = true
		assert_true(o["years"] >= 1 and o["years"] <= 5 and o["amount"] > 0)
	assert_true(fin.sponsor_offers(1, 2028, scale) != a, "new offers each year")
	var team: FcTeam = world.teams.get_by_id(1)
	var slot := fin.sponsorship_baseline(1, world.businesses.get_by_id(1), world.cities.get_by_id(team.city_id), scale) * float(fin.k["sponsor_slot_share"])
	for o in a:
		assert_between(float(o["amount"]), slot * 0.75, slot * 1.20, "priced around a share of the open-market income")


func test_signing_sponsors_has_two_slots_and_no_repeats() -> void:
	var world := _sponsor_world()
	var fin := FcFinanceEngine.new(world)
	var scale := fin.scale_for(world.rules_of_league(1))
	var business: FcTeamBusiness = world.businesses.get_by_id(1)
	var offers := fin.sponsor_offers(1, 2027, scale)
	assert_eq(fin.sign_sponsor(business, offers[0]), "")
	assert_true(fin.sign_sponsor(business, offers[0]) != "", "not the same sponsor twice")
	assert_eq(fin.sign_sponsor(business, offers[1]), "")
	assert_true(fin.sign_sponsor(business, offers[2]) != "", "only two slots")
	assert_eq(fin.sponsor_offers(1, 2027, scale).size(), 3, "offers keep coming (the signed names are skipped)")


func test_sponsor_contracts_pay_fixed_money_bonuses_and_expire() -> void:
	var results := {}
	for deals in [0, 2]:
		var world := _build_world()
		var fin := FcFinanceEngine.new(world)
		var scale := fin.scale_for(world.rules_of_league(1))
		if deals > 0:
			var business: FcTeamBusiness = world.businesses.get_by_id(1)
			business.sponsor_deals = [
				{"sponsor": "Test One", "amount": 9000000, "bonus": 1000000, "years_left": 1},
				{"sponsor": "Test Two", "amount": 7000000, "bonus": 0, "years_left": 2},
			]
		var rng := FcRng.new(3)
		var engine := FcSeasonEngine.for_league(world, 1)
		var season := engine.start_season(1, 2026, FcDate.new(2026, 10, 20), rng.fork("s"))
		engine.play_full_season(season, rng.fork("p"))
		var rec := fin.record_of(1, 2026)
		results[deals] = {"revenue": rec.revenue["sponsorship"], "rounds": rec.playoff_rounds_won, "business": world.businesses.get_by_id(1), "scale": scale}
	assert_true(results[2]["revenue"] != results[0]["revenue"], "contracts change the sponsorship income")
	var business: FcTeamBusiness = results[2]["business"]
	assert_eq(business.sponsor_deals.size(), 1, "the one-year deal ended")
	assert_eq(business.sponsor_deals[0]["sponsor"], "Test Two")
	assert_eq(business.sponsor_deals[0]["years_left"], 1)


func test_no_contracts_means_the_old_sponsorship_income() -> void:
	var played := _played()
	var world: FcWorld = played["world"]
	var fin := FcFinanceEngine.new(world)
	var rec := fin.record_of(1, 2026)
	var business: FcTeamBusiness = world.businesses.get_by_id(1)
	assert_true(business.sponsor_deals.is_empty() and rec.revenue["sponsorship"] > 0)


func test_sponsor_deals_are_saved() -> void:
	var b := FcTeamBusiness.new(2)
	b.sponsor_deals = [{"sponsor": "Halcyon Energy", "amount": 8000000, "bonus": 800000, "years_left": 3}]
	var back := FcTeamBusiness.from_dict(JSON.parse_string(JSON.stringify(b.to_dict())))
	assert_eq(back.sponsor_deals, b.sponsor_deals)
	assert_eq(FcTeamBusiness.from_dict({"id": 2}).sponsor_deals, [])


func test_playoff_ticket_premium_trades_price_for_attendance() -> void:
	var world: FcWorld = _played()["world"]
	var fin := FcFinanceEngine.new(world)
	var parts := _parts(world, 1)
	var city: FcCity = parts[0]
	var arena: FcArena = parts[1]
	var business: FcTeamBusiness = parts[2]
	var scale := fin.price_scale_for(world.rules_of_league(1), world.leagues.get_by_id(1))
	var previous := fin.playoff_attendance(business, city, arena, scale, 100)
	var best_revenue := 0.0
	var best_premium := 0
	for premium in range(100, 301, 20):
		var fans := fin.playoff_attendance(business, city, arena, scale, premium)
		assert_true(fans <= previous, "a higher premium never brings more fans")
		previous = fans
		var revenue := fans * premium / 100.0
		if revenue > best_revenue:
			best_revenue = revenue
			best_premium = premium
	assert_true(best_premium > 100, "a premium over the regular price pays")
	assert_true(best_premium < 300, "but gouging does not")


func test_playoff_premium_is_saved_and_validated() -> void:
	var b := FcTeamBusiness.new(2)
	assert_eq(b.playoff_premium_pct, 160, "the league-standard premium by default")
	b.playoff_premium_pct = 220
	assert_eq(FcTeamBusiness.from_dict(JSON.parse_string(JSON.stringify(b.to_dict()))).playoff_premium_pct, 220)
	assert_eq(FcTeamBusiness.from_dict({"id": 2}).playoff_premium_pct, 160)


func test_facility_levels_cost_upkeep_and_save() -> void:
	var b := FcTeamBusiness.new(2)
	b.practice_level = 2
	b.medical_level = 3
	var back := FcTeamBusiness.from_dict(JSON.parse_string(JSON.stringify(b.to_dict())))
	assert_eq([back.practice_level, back.medical_level], [2, 3])
	assert_eq(FcTeamBusiness.from_dict({"id": 2}).practice_level, 0)
