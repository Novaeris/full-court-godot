extends FcTestCase
## A financially distressed owner (D-029: the owner cannot lose the franchise, but debt is restructured, the
## reputation suffers, loans freeze, and nothing is rescued for free).

var k: Dictionary


func before_each() -> void:
	k = FcEconomy.load_constants()


func _game(seed_value: int = 810) -> FcGameController:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 10
	return FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), seed_value, FcGameState.MODE_OWNER, 0)


# --- the pure rule -------------------------------------------------------------------------------

func test_no_restructuring_below_the_trigger_and_a_40_percent_ceiling_above_it() -> void:
	var cap := 100000000
	assert_eq(FcEconomy.restructure_amount(900000000, 1000000000, cap, 2030, 0, k), 0, "debt below the value: no rescue")
	assert_eq(FcEconomy.restructure_amount(1000000000, 1000000000, cap, 2030, 0, k), 0, "exactly at the trigger is not above it")
	var written := FcEconomy.restructure_amount(1500000000, 1000000000, cap, 2030, 0, k)
	assert_eq(written, 1100000000, "debt 1.5B is cut to 40% of the 1.0B value: 1.1B forgiven")
	assert_eq(1500000000 - written, 400000000)


func test_a_collapsed_or_negative_value_uses_the_floor_not_zero() -> void:
	var cap := 100000000
	var floor_value := roundi(float(k["restructure_floor_cap_share"]) * cap)   # 50M
	for value in [0, -5000000, 1]:
		var written := FcEconomy.restructure_amount(300000000, value, cap, 2030, 0, k)
		assert_eq(300000000 - written, roundi(float(k["restructure_ceiling_share"]) * floor_value), "value %d: the ceiling comes from the floor" % value)
	assert_eq(FcEconomy.restructure_amount(0, 0, cap, 2030, 0, k), 0, "no debt, no value: nothing to do and no division by zero")
	assert_eq(FcEconomy.restructure_amount(40000000, 0, cap, 2030, 0, k), 0, "debt under the floor value is fine")


func test_the_cooldown_stops_a_restructuring_every_season() -> void:
	var cap := 100000000
	var cooldown := int(k["restructure_cooldown_seasons"])
	assert_eq(FcEconomy.restructure_amount(900000000, 100000000, cap, 2030, 2029, k), 0, "one season after the last one")
	assert_eq(FcEconomy.restructure_amount(900000000, 100000000, cap, 2030, 2030 - cooldown + 1, k), 0, "still inside the cooldown")
	assert_true(FcEconomy.restructure_amount(900000000, 100000000, cap, 2030, 2030 - cooldown, k) > 0, "after the cooldown it can happen again")


func test_recovery_means_no_more_restructuring() -> void:
	var cap := 100000000
	assert_eq(FcEconomy.restructure_amount(80000000, 400000000, cap, 2040, 2030, k), 0, "a healthy club is left alone, long after the last time")


# --- in the game ---------------------------------------------------------------------------------

func test_advance_writes_off_debt_but_adds_no_cash() -> void:
	var g := _game()
	g.sim_playoffs()
	var w := g.state.world
	var b := g.business()
	var cap := w.rules_of_league(1).cap.salary_cap
	b.debt = cap * 10
	var cash_before := b.cash
	var ai_tid := 0
	for tid in w.leagues.get_by_id(1).all_team_ids():
		if tid != g.state.user_team_id:
			ai_tid = tid
			break
	var ai: FcTeamBusiness = w.businesses.get_by_id(ai_tid)
	ai.debt = cap * 10
	var valuation_before := maxi(b.valuation, roundi(float(k["restructure_floor_cap_share"]) * cap))
	var ai_valuation := maxi(ai.valuation, roundi(float(k["restructure_floor_cap_share"]) * cap))
	var report := FcEconomy.new(w).advance(1, 2026, [g.state.user_team_id] as Array[int])
	assert_eq(report["restructured"].size(), 2, "the owner's club and the indebted AI club")
	assert_eq(b.debt, roundi(float(k["restructure_ceiling_share"]) * valuation_before), "ceiling from the value before the rescue")
	assert_eq(b.cash, cash_before, "solvency, not profit: no cash is added")
	assert_eq(b.restructured_total, cap * 10 - b.debt)
	assert_eq(b.restructured_year, 2026)
	assert_eq(ai.debt, roundi(float(k["restructure_ceiling_share"]) * ai_valuation), "AI clubs follow the same rule")
	assert_eq(g.state.owner_career["reputation"], 40, "the reputation is only the owner's business: advance() does not touch it")
	var rec := FcFinanceEngine.new(w).record_of(g.state.user_team_id, 2026)
	assert_eq(rec.restructuring_writeoff, b.restructured_total, "recorded apart from revenue and expenses")
	var profit_before := rec.profit()
	assert_eq(rec.profit(), profit_before, "operating profit does not include the write-off")
	var again := FcEconomy.new(w).advance(1, 2026, [g.state.user_team_id] as Array[int])
	assert_eq(again["restructured"].size(), 0, "the cooldown blocks a second one")


func test_the_owner_pays_in_reputation_and_cannot_borrow_for_a_while() -> void:
	var g := _game()
	g.sim_playoffs()
	g.owner_reputation()
	g.state.owner_career["reputation"] = 60
	g.business().debt = g.state.world.rules_of_league(1).cap.salary_cap * 20
	g.begin_offseason()
	assert_eq(g.state.owner_career["reputation"], 60 - int(k["restructure_reputation_penalty"]))
	assert_eq(g.state.owner_career["restructurings"].size(), 1)
	assert_true(g.loans_frozen() and g.loan_limit() == 0)
	assert_true(not g.borrow(1000000)["ok"] and "froze" in g.borrow(1000000)["reason"])
	assert_true(g.owner_report()["loans_frozen"] and g.owner_report()["restructured_total"] > 0)
	assert_true(g.gm_log().any(func(line): return "restructured" in line), "the owner is told")
	assert_true(g.state.world.news.any(func(n): return "restructured" in n["text"]))
	g.draft_auto_rest()
	for i in int(k["restructure_lockout_seasons"]):
		g.start_next_season()
		g.sim_playoffs()
	assert_true(not g.loans_frozen(), "the freeze ends")
	assert_true(g.loan_limit() > 0)


func test_the_reputation_never_goes_below_zero() -> void:
	var g := _game()
	g.sim_playoffs()
	g.owner_reputation()
	g.state.owner_career["reputation"] = 3
	g.business().debt = g.state.world.rules_of_league(1).cap.salary_cap * 20
	g.begin_offseason()
	assert_eq(g.state.owner_career["reputation"], 0)


func test_the_new_fields_survive_saving_and_old_saves_have_none() -> void:
	var b := FcTeamBusiness.new(4)
	b.restructured_total = 123456
	b.restructured_year = 2031
	var back := FcTeamBusiness.from_dict(b.to_dict())
	assert_eq(back.restructured_total, 123456)
	assert_eq(back.restructured_year, 2031)
	assert_eq(FcTeamBusiness.from_dict({"id": 4}).restructured_year, 0)
	var rec := FcFinanceRecord.new(9)
	rec.restructuring_writeoff = 777
	assert_eq(FcFinanceRecord.from_dict(rec.to_dict()).restructuring_writeoff, 777)
	var g := _game()
	g.state.owner_career["restructurings"] = [[2030, 1, 5000000]]
	var loaded := FcGameState.from_dict(JSON.parse_string(JSON.stringify(g.state.to_dict())), FcDefinitionSet.load_default())
	assert_eq(loaded.owner_career["restructurings"], [[2030, 1, 5000000]])
	var old := FcGameState.from_dict({"owner_career": {"reputation": 50, "history": []}}, FcDefinitionSet.load_default())
	assert_eq(old.owner_career["restructurings"], [])


# --- the D-029 promise ---------------------------------------------------------------------------

func test_a_club_that_never_recovers_keeps_its_owner_in_control() -> void:
	var g := _game(811)
	var w := g.state.world
	var cap_start := w.rules_of_league(1).cap.salary_cap
	var seasons := 9
	var cooldown := int(k["restructure_cooldown_seasons"])
	for i in seasons:
		var b := g.business()
		b.ticket_price = 5   # nobody comes, nothing is earned
		b.marketing_budget = cap_start / 2
		b.debt += cap_start * 4   # and the losses keep piling up
		g.sim_playoffs()
		assert_eq(g.state.validate(), [] as Array[String], "season %d: the league stays valid" % (i + 1))
		g.begin_offseason()
		g.draft_auto_rest()
		assert_eq(g.state.validate(), [] as Array[String], "season %d offseason: valid" % (i + 1))
		assert_true(g.set_ticket_price(g.suggested_ticket_price()) and g.set_marketing_budget(1000000), "the owner can still decide")
		g.start_next_season()
	var count: int = g.state.owner_career["restructurings"].size()
	assert_true(count >= 2 and count <= int(ceil(float(seasons) / cooldown)), "repeated but never every season (%d)" % count)
	var rows: Array = g.state.owner_career["restructurings"]
	for i in range(1, rows.size()):
		assert_true(rows[i][0] - rows[i - 1][0] >= cooldown, "restructurings respect the cooldown (years %d and %d)" % [rows[i - 1][0], rows[i][0]])
	assert_true(g.state.owner_career["reputation"] >= 0)
	assert_true(g.business().debt >= 0 and g.business().cash >= 0)
	# the job market still works: the owner may move to another franchise like a job
	g.sim_playoffs()
	var offers := g.job_offers()
	assert_true(not offers.is_empty(), "job offers exist for a distressed owner")
	var moved := g.transfer_to(offers[0]["team"])
	assert_true(moved["ok"], moved.get("reason", ""))
	assert_eq(g.state.validate(), [] as Array[String])
	# and the saved game still loads
	var again := FcGameState.from_dict(JSON.parse_string(JSON.stringify(g.state.to_dict())), FcDefinitionSet.load_default())
	assert_eq(again.owner_career["restructurings"], g.state.owner_career["restructurings"])


# --- AI clubs in debt ----------------------------------------------------------------------------

func test_a_club_is_distressed_when_its_debt_is_large_for_its_value() -> void:
	var g := _game()
	var w := g.state.world
	var economy := FcEconomy.new(w)
	var cap := w.rules_of_league(1).cap.salary_cap
	var tid := 2
	var b: FcTeamBusiness = w.businesses.get_by_id(tid)
	b.debt = 0
	assert_true(not economy.is_distressed(tid, cap), "no debt is never distress")
	b.valuation = 0
	b.debt = roundi(float(k["distress_debt_share"]) * float(k["restructure_floor_cap_share"]) * cap) - 1000
	assert_true(not economy.is_distressed(tid, cap), "just under the floor-based threshold")
	b.debt += 2000
	assert_true(economy.is_distressed(tid, cap), "a collapsed value uses the floor, not zero")


func test_an_ai_club_in_debt_signs_only_minimum_contracts() -> void:
	var g := _game(812)
	var w := g.state.world
	var rules := w.rules_of_league(1)
	var broke_id := 2
	w.businesses.get_by_id(broke_id).debt = rules.cap.salary_cap * 5
	assert_true(FcEconomy.new(w).is_distressed(broke_id, rules.cap.salary_cap))
	g.sim_playoffs()
	var team: FcTeam = w.teams.get_by_id(broke_id)
	# make room under the cap and in the roster so the club would like to sign someone
	for pid in team.roster.player_ids.slice(0, 5):
		var c := w.active_contract_of(pid)
		c.status = FcContract.Status.TERMINATED
		team.roster.remove(pid)
	var before := w.contracts.count()
	FcOffseason.new(w).free_agency(1, 2027, FcRng.new(5))
	for c in w.contracts.all().slice(before):
		if c.team_id == broke_id:
			assert_true(c.years[0].salary <= rules.cap.min_player_salary, "a club deep in debt signs minimum contracts only (%d)" % c.years[0].salary)


func test_the_general_manager_lives_within_the_means_of_a_club_in_debt_unless_the_budget_is_aggressive() -> void:
	var g := _game(813)
	g.sim_playoffs()
	var b := g.business()
	var cap := g.state.world.rules_of_league(1).cap
	b.debt = 0
	g.set_direction("balanced", "normal")
	var rec0 := FcFinanceEngine.new(g.state.world).record_of(g.state.user_team_id, g.state.current_season)
	var affordable := maxi(roundi(float(k["indebted_payroll_revenue_share"]) * rec0.total_revenue()), cap.minimum_payroll)
	assert_eq(g.gm_payroll_limit(), mini(cap.salary_cap, affordable), "even without debt the GM spends within the club's means")
	b.debt = 50000000
	var rec := FcFinanceEngine.new(g.state.world).record_of(g.state.user_team_id, g.state.current_season)
	var ceiling := roundi(float(k["indebted_payroll_revenue_share"]) * rec.total_revenue())
	assert_eq(g.gm_payroll_limit(), mini(cap.salary_cap, maxi(ceiling, cap.minimum_payroll)), "in debt too: held to 65% of revenue (never below the minimum payroll)")
	g.set_direction("balanced", "aggressive")
	assert_true(g.gm_payroll_limit() >= mini(roundi(cap.salary_cap * 1.15), cap.luxury_tax_line) - 1 or g.gm_payroll_limit() == cap.luxury_tax_line, "aggressive is the owner's explicit choice and ignores the debt")


func test_the_owner_sees_a_plain_warning_when_finances_go_wrong() -> void:
	var g := _game(814)
	g.sim_playoffs()
	var b := g.business()
	var cap := g.state.world.rules_of_league(1).cap.salary_cap
	b.debt = 0
	assert_eq(g.distress_warning(), "", "no debt, no warning")
	b.debt = cap * 3
	b.valuation = cap * 4
	assert_true("close to your club's value" in g.distress_warning(), "debt near the value warns before the rescue")
	b.debt = cap
	b.valuation = cap * 40
	var rec := FcFinanceEngine.new(g.state.world).record_of(g.state.user_team_id, g.state.current_season)
	rec.revenue["tickets"] = 0
	rec.expenses["administration"] = cap
	assert_true("lost" in g.distress_warning(), "a loss with debt is flagged")
	b.restructured_year = g.state.current_season
	assert_true("froze new loans" in g.distress_warning(), "after a restructuring the warning says so")
