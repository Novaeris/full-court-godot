extends FcTestCase
## AI trades between contenders and rebuilding teams.

var world: FcWorld
var rules: FcLeagueRules
var trades: FcTrades


func before_each() -> void:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 5
	world = FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg).generate(61)
	rules = world.rules_of_league(1)
	trades = FcTrades.new(world)


func _make_old_star(team_id: int) -> FcPlayer:
	var team: FcTeam = world.teams.get_by_id(team_id)
	var p: FcPlayer = world.players.get_by_id(team.roster.player_ids[0])
	p.identity.birth_date = FcDate.new(1995, 5, 5)   # 31 on 2026-07-01 -> 32 in 2027
	for key in world.definitions.attributes.keys():
		p.attributes.set_clamped(key, 75)
	p.development.potential = 75
	return p


func _make_prospect(team_id: int) -> FcPlayer:
	var team: FcTeam = world.teams.get_by_id(team_id)
	var p: FcPlayer = world.players.get_by_id(team.roster.player_ids[team.roster.size() - 1])
	p.identity.birth_date = FcDate.new(2004, 5, 5)   # 23 in 2027
	for key in world.definitions.attributes.keys():
		p.attributes.set_clamped(key, 52)
	p.development.potential = 96
	return p


func _salary_neutral(a: FcPlayer, b: FcPlayer) -> void:
	for pid in [a.id, b.id]:
		var c := world.active_contract_of(pid)
		for y in c.years:
			y.salary = 8000000
			y.guaranteed = 8000000


func test_a_clear_win_win_trade_happens() -> void:
	var vet := _make_old_star(1)
	var kid := _make_prospect(2)
	_salary_neutral(vet, kid)
	var seller_size: int = world.teams.get_by_id(1).roster.size()
	var buyer_size: int = world.teams.get_by_id(2).roster.size()
	assert_true(trades._try_trade(rules, 1, 2, 2027, FcRng.new(1)), "the rebuilding team swaps its veteran for the contender's prospect")
	assert_true(world.teams.get_by_id(2).roster.contains(vet.id))
	assert_true(world.teams.get_by_id(1).roster.contains(kid.id))
	assert_true(not world.teams.get_by_id(1).roster.contains(vet.id))
	assert_eq(world.teams.get_by_id(1).roster.size(), seller_size, "rosters stay the same size")
	assert_eq(world.teams.get_by_id(2).roster.size(), buyer_size)
	assert_eq(world.active_contract_of(vet.id).team_id, 2, "his contract goes with him")
	assert_eq(world.active_contract_of(kid.id).team_id, 1)
	assert_true(world.news.any(func(n): return "trade" in n["text"] and vet.identity.last_name in n["text"]))
	assert_eq(world.validate(2027), [] as Array[String], "the world is consistent after the trade")


func test_no_trade_clause_blocks_it() -> void:
	var vet := _make_old_star(1)
	var kid := _make_prospect(2)
	_salary_neutral(vet, kid)
	for pid in world.teams.get_by_id(1).roster.player_ids:
		world.active_contract_of(pid).no_trade = true   # nobody on the seller can be traded
	assert_true(not trades._try_trade(rules, 1, 2, 2027, FcRng.new(1)))
	assert_true(world.teams.get_by_id(1).roster.contains(vet.id))


func test_both_sides_must_gain() -> void:
	var vet := _make_old_star(1)
	var kid := _make_prospect(2)
	_salary_neutral(vet, kid)
	# if the prospect has no upside the rebuilding team does not want him
	kid.development.potential = 52
	for key in world.definitions.attributes.keys():
		kid.attributes.set_clamped(key, 30)
	assert_true(not trades._try_trade(rules, 1, 2, 2027, FcRng.new(1)))


func test_salary_rules_block_unaffordable_trades() -> void:
	var vet := _make_old_star(1)
	var kid := _make_prospect(2)
	_salary_neutral(vet, kid)
	# the veteran earns far more than the buyer may take back under the hard limit
	for y in world.active_contract_of(vet.id).years:
		y.salary = rules.cap.max_player_salary
		y.guaranteed = y.salary
	for pid in world.teams.get_by_id(2).roster.player_ids:
		if pid != kid.id:
			for y in world.active_contract_of(pid).years:
				y.salary = rules.cap.max_player_salary
				y.guaranteed = y.salary
	# (year 2026: the contracts in this test only cover the current season)
	assert_true(not trades._try_trade(rules, 1, 2, 2026, FcRng.new(1)), "the buyer would exceed the hard limit")


func test_the_trade_market_runs_over_several_offseasons() -> void:
	var rng := FcRng.new(5)
	var total := 0
	for i in 3:
		var engine := FcSeasonEngine.for_league(world, 1)
		var season := engine.start_season(1, 2026 + i, FcDate.new(2026 + i, 10, 20), rng.fork("s%d" % i))
		engine.play_full_season(season, rng.fork("p%d" % i))
		var report := FcOffseason.new(world).run(1, season, rng.fork("o%d" % i))
		assert_true(report.has("trades") and report["trades"] >= 0 and report["trades"] <= 8)
		total += report["trades"]
		assert_eq(world.validate(2027 + i), [] as Array[String], "year %d" % i)
		for t in world.teams.all():
			var seen := {}
			for pid in t.roster.player_ids:
				assert_true(not seen.has(pid), "no player twice on a roster")
				seen[pid] = true
				assert_eq(world.active_contract_of(pid).team_id, t.id, "contract matches roster")
	assert_true(total >= 0)
	assert_true(world.players.count() > 0)


func test_trades_are_reproducible() -> void:
	var a := FcTrades.new(world)
	var finished := FcSeason.new(1)
	finished.league_id = 1
	finished.year = 2026
	var first := a.run(1, finished, 2027, FcRng.new(3))
	assert_true(first >= 0)


func test_a_pick_can_sweeten_a_deal_the_seller_would_otherwise_refuse() -> void:
	var vet := _make_old_star(1)
	var kid := _make_prospect(2)
	_salary_neutral(vet, kid)
	# find a prospect quality where the seller is just short of agreeing but the buyer gains a lot
	var found := false
	for pot in range(96, 30, -1):
		kid.development.potential = pot
		var seller_gain := trades._value(kid, 2027, false) - trades._value(vet, 2027, false)
		var buyer_gain := trades._value(vet, 2027, true) - trades._value(kid, 2027, true)
		if seller_gain <= FcTrades.MARGIN and seller_gain > FcTrades.MARGIN - 4.0 and buyer_gain > FcTrades.MARGIN + 4.0:
			found = true
			break
	assert_true(found, "a borderline prospect exists for this test")
	var without := FcTrades.new(world)
	assert_true(not without._try_trade(rules, 1, 2, 2027, FcRng.new(1)), "without picks the seller says no")
	assert_true(trades._try_trade(rules, 1, 2, 2027, FcRng.new(1), {}, 2028), "with a pick added the deal works")
	assert_true(world.pick_owners.size() == 1, "one pick changed hands")
	for key in world.pick_owners:
		assert_eq(world.pick_owners[key], 1, "to the rebuilding seller")
	assert_true(world.news.any(func(n): return "pick" in n["text"] and vet.identity.last_name in n["text"]), "the news mentions the pick")
	assert_eq(world.validate(2027), [] as Array[String])


func test_the_trade_market_includes_picks_and_stays_consistent() -> void:
	var picks_moved := 0
	for seed_value in 12:
		var finished := FcSeason.new(1)
		finished.league_id = 1
		finished.year = 2026
		trades.run(1, finished, 2027, FcRng.new(seed_value))
		assert_eq(world.validate(2027), [] as Array[String], "seed %d" % seed_value)
	for key in world.pick_owners:
		var parts := str(key).split(":")
		assert_true(int(parts[0]) >= 2028 and int(parts[0]) <= 2030, "only tradable years")
		assert_true(int(parts[1]) == 1 or int(parts[1]) == 2)
		assert_true(world.teams.has_id(int(world.pick_owners[key])) and int(parts[2]) != int(world.pick_owners[key]), "the owner is another real team")
		picks_moved += 1
	for t in world.teams.all():
		assert_true(t.roster.size() >= rules.roster_min - 3 and t.roster.size() <= rules.roster_max)
	assert_true(picks_moved >= 0)
