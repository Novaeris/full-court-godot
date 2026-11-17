extends FcTestCase
## The long-run economy: inflation, the cap following league profit, cash sinks (AI building
## projects, dividends, the new arena) and the owner's dividend.


func _game(seed_value: int = 410) -> FcGameController:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 10
	return FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), seed_value, FcGameState.MODE_OWNER, 0)


func _settled_world() -> FcWorld:
	var g := _game()
	g.sim_playoffs()
	return g.state.world


func test_growth_is_seeded_and_inside_its_limits() -> void:
	var economy := FcEconomy.new(_settled_world())
	assert_eq(economy.growth_rate(1, 2030), economy.growth_rate(1, 2030), "same every time")
	var seen_recession := false
	for year in range(2000, 2200):
		var g := economy.growth_rate(1, year)
		assert_between(g, 0.0, 0.05, "year %d" % year)
		if g == 0.0:
			seen_recession = true
	assert_true(seen_recession, "some years are flat")


func test_advance_grows_the_money_scale_and_the_cap() -> void:
	var w := _settled_world()
	var rules := w.rules_of_league(1)
	var finance := FcFinanceEngine.new(w)
	assert_eq(rules.money_scale_ppm, 0, "legacy until the first offseason")
	var scale_before := finance.scale_for(rules)
	var report := FcEconomy.new(w).advance(1, 2026)
	assert_true(rules.money_scale_ppm > 0)
	assert_eq(report["cap_after"], rules.cap.salary_cap)
	assert_true(finance.scale_for(rules) >= scale_before, "money never shrinks")
	assert_true(rules.validate(w.leagues.get_by_id(1)).is_empty(), "rules stay valid: %s" % str(rules.validate(w.leagues.get_by_id(1))))


func test_cap_moves_faster_when_clubs_are_very_profitable() -> void:
	var rich := _settled_world()
	for r in rich.finances.all():
		r.revenue["tickets"] += 400000000   # every club made a fortune
	var poor := _settled_world()
	for r in poor.finances.all():
		r.expenses["administration"] += 400000000
	var rich_report := FcEconomy.new(rich).advance(1, 2026)
	var poor_report := FcEconomy.new(poor).advance(1, 2026)
	assert_true(rich_report["cap_after"] > poor_report["cap_after"], "profit lifts the players' share")


func test_the_money_scale_and_distributions_survive_saving() -> void:
	var w := _settled_world()
	FcEconomy.new(w).advance(1, 2026)
	var rules := FcLeagueRules.from_dict(w.rules_of_league(1).to_dict())
	assert_eq(rules.money_scale_ppm, w.rules_of_league(1).money_scale_ppm)
	var b: FcTeamBusiness = w.businesses.get_by_id(1)
	b.distributions = 12345
	assert_eq(FcTeamBusiness.from_dict(b.to_dict()).distributions, 12345)
	assert_eq(FcLeagueRules.from_dict({}).money_scale_ppm, 0, "old saves")


func test_ai_clubs_build_projects_and_pay_dividends_from_surplus_cash() -> void:
	var w := _settled_world()
	var rules := w.rules_of_league(1)
	var cap := rules.cap.salary_cap
	var ai: FcTeamBusiness = w.businesses.get_by_id(w.leagues.get_by_id(1).all_team_ids()[1])
	ai.debt = 0
	ai.cash = cap * 5
	ai.practice_level = 0
	var report := FcEconomy.new(w).advance(1, 2026, [] as Array[int])
	assert_true(report["projects"] > 0, "projects started")
	assert_true(report["dividends"] > 0)
	assert_true(ai.distributions > 0)
	assert_true(ai.cash <= int(rules.cap.salary_cap * 1.7), "cash is back under the ceiling")
	assert_true(ai.projects.size() > 0)


func test_the_owners_own_club_is_left_alone() -> void:
	var g := _game()
	g.sim_playoffs()
	var b := g.business()
	b.debt = 0
	b.cash = g.state.world.rules_of_league(1).cap.salary_cap * 5
	var before := b.cash
	FcEconomy.new(g.state.world).advance(1, 2026, [g.state.user_team_id] as Array[int])
	assert_eq(b.cash, before, "no automatic spending for the human owner")
	assert_eq(b.distributions, 0)


func test_the_new_arena_replaces_an_old_one_and_cannot_be_built_early() -> void:
	var g := _game()
	var w := g.state.world
	var team: FcTeam = w.teams.get_by_id(g.state.user_team_id)
	var arena: FcArena = w.arenas.get_by_id(team.arena_id)
	var b := g.business()
	var finance := FcFinanceEngine.new(w)
	var scale := finance.scale_for(w.rules_of_league(1))
	b.cash = 5000000000
	b.facilities_level = 90
	assert_true(finance.start_project(b, arena, "new_arena", scale) != "", "too new")
	b.facilities_level = 40
	var seats := arena.capacity
	assert_eq(finance.start_project(b, arena, "new_arena", scale), "")
	for i in 3:
		finance.advance_projects(b, arena, team.id, 2026 + i)
	assert_eq(b.facilities_level, 100)
	assert_eq(arena.capacity, seats + 2500)
	assert_eq(arena.year_built, 2029)


func test_the_owner_can_pay_themselves_only_from_surplus_and_without_debt() -> void:
	var g := _game()
	var b := g.business()
	var cap := g.state.world.rules_of_league(1).cap.salary_cap
	b.debt = 1000000
	b.cash = cap * 3
	assert_true(not g.take_dividend(1000000)["ok"], "not while in debt")
	b.debt = 0
	b.cash = 1000000
	assert_true(not g.take_dividend(500000)["ok"], "the reserve stays")
	b.cash = cap * 3
	var before := b.cash
	assert_true(g.take_dividend(10000000)["ok"])
	assert_eq(b.cash, before - 10000000)
	assert_eq(b.distributions, 10000000)
	assert_true(not g.take_dividend(cap * 10)["ok"], "cannot drain the club")
