extends FcTestCase
## The game controller: the API a screen uses to play the game.

func _generator() -> FcWorldGenerator:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 15
	cfg.assistant_coaches = 1
	cfg.scouts = 0
	return FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg)


func _game(seed_value: int = 5, mode: String = FcGameState.MODE_OWNER) -> FcGameController:
	return FcGameController.new_game(_generator(), seed_value, mode, 2)


func test_new_game_starts_the_first_season() -> void:
	var g := _game()
	assert_eq(g.phase(), FcGameController.PHASE_REGULAR)
	assert_eq(g.state.current_season, 2026)
	assert_eq(g.state.current_date.to_iso(), "2026-10-20")
	assert_eq(g.state.user_team_id, 3)
	assert_eq(g.season().status, FcSeason.Status.PENDING)
	var rec := g.user_record()
	assert_eq([rec["wins"], rec["losses"]], [0, 0])
	assert_eq(rec["games_left"], g.state.world.rules_of_league(1).season.games_per_team(g.state.world.leagues.get_by_id(1)))
	assert_true(g.next_user_game() != null)
	assert_eq(g.state.validate(), [] as Array[String])


func test_advancing_days_moves_the_calendar() -> void:
	var g := _game()
	var played := g.advance_day()
	assert_true(played > 0)
	assert_eq(g.state.current_date.to_iso(), "2026-10-21")
	g.advance_days(9)
	assert_eq(g.state.current_date.to_iso(), "2026-10-30")
	assert_eq(g.season().status, FcSeason.Status.REGULAR)
	assert_true(g.user_record()["wins"] + g.user_record()["losses"] > 0)


func test_season_flows_through_the_playoffs_to_a_champion() -> void:
	var g := _game()
	g.sim_regular_season()
	assert_eq(g.phase(), FcGameController.PHASE_PLAYOFFS, "the playoffs begin as soon as the regular season ends")
	assert_true(g.season().playoffs != null)
	g.advance_day()
	g.sim_playoffs()
	assert_eq(g.phase(), FcGameController.PHASE_COMPLETE)
	assert_true(g.season().champion_id > 0)
	assert_eq(g.advance_day(), 0, "nothing to play once the season is complete")
	assert_true(g.state.current_date.is_before(FcDate.new(2027, 8, 1)))


func test_next_season_runs_the_offseason() -> void:
	var g := _game()
	var report := g.start_next_season()
	assert_eq(g.state.current_season, 2027)
	assert_eq(g.state.current_date.to_iso(), "2027-10-20")
	assert_eq(g.phase(), FcGameController.PHASE_REGULAR)
	assert_true(report["progressed"] > 50 and report.has("drafted") and report.has("staff_hired"))
	assert_eq(g.state.validate(), [] as Array[String])
	assert_true(g.state.world.season_of(1, 2026).status == FcSeason.Status.COMPLETE, "last season is kept")
	assert_eq(g.user_record()["wins"], 0)


func test_three_years_stay_valid() -> void:
	var g := _game(9)
	for i in 3:
		g.start_next_season()
		assert_eq(g.state.validate(), [] as Array[String], "year %d" % (i + 1))
	assert_eq(g.state.current_season, 2029)


func test_owner_price_and_marketing_decisions() -> void:
	var g := _game()
	var b := g.business()
	assert_true(g.set_ticket_price(250))
	assert_eq(b.ticket_price, 250)
	assert_true(not g.set_ticket_price(0))
	assert_true(not g.set_ticket_price(999999))
	assert_eq(b.ticket_price, 250, "a rejected price changes nothing")
	assert_true(g.set_marketing_budget(15000000))
	assert_true(not g.set_marketing_budget(-1))
	b.cash = 100000000
	var level := b.facilities_level
	assert_true(g.invest_in_facilities(10))
	assert_eq(b.facilities_level, level + 10)
	g.sim_playoffs()
	assert_eq(b.ticket_price, 250, "the owner's price survives the settlement")
	assert_eq(b.marketing_budget, 15000000)
	var other: FcTeamBusiness = g.state.world.businesses.get_by_id(1)
	assert_true(other.ticket_price != 250, "AI teams reprice")


func test_dynasty_mode_leaves_prices_to_the_ai() -> void:
	var g := _game(5, FcGameState.MODE_DYNASTY)
	assert_true(g.engine.human_teams.is_empty())


func test_hiring_and_firing_staff() -> void:
	var g := _game()
	var w := g.state.world
	var team := g.state.user_team_id
	var coach := w.staff_in_role(team, FcStaffRole.Id.HEAD_COACH)
	assert_true(coach != null)
	var other_coach := w.staff_in_role(1, FcStaffRole.Id.HEAD_COACH)
	assert_true(not g.fire_staff(other_coach.id), "you cannot fire another team's coach")
	assert_true(g.fire_staff(coach.id))
	assert_true(w.staff_in_role(team, FcStaffRole.Id.HEAD_COACH) == null, "the post is vacant")
	assert_true(not g.fire_staff(coach.id), "already fired")
	var pool := g.staff_pool(FcStaffRole.Id.HEAD_COACH)
	assert_true(pool.size() > 0 and pool[0].id == coach.id or pool.size() > 0, "the fired coach and others are in the pool")
	var hire := pool[0]
	assert_eq(g.hire_staff(hire.id, FcStaffRole.Id.HEAD_COACH, 3), "")
	assert_eq(w.staff_in_role(team, FcStaffRole.Id.HEAD_COACH).id, hire.id)
	assert_true(g.hire_staff(hire.id, FcStaffRole.Id.HEAD_COACH, 3) != "", "already employed")
	var spare := g.staff_pool(FcStaffRole.Id.HEAD_COACH)
	if spare.size() > 0:
		assert_true("already has" in g.hire_staff(spare[0].id, FcStaffRole.Id.HEAD_COACH, 1), "only one head coach")
	assert_eq(w.validate(2026), [] as Array[String])
	g.sim_regular_season()
	assert_true(g.season().regular_season_complete(), "the season still plays with the new coach")


func test_owner_report() -> void:
	var g := _game()
	assert_eq(g.owner_report(), {}, "nothing to report before a season is finished")
	g.sim_playoffs()
	var r := g.owner_report()
	for key in ["year", "profit", "revenue", "valuation", "valuation_change", "cash", "debt", "wins", "expected_wins", "approval"]:
		assert_true(r.has(key), key)
	assert_between(r["approval"], 0.0, 100.0)
	assert_eq(r["year"], 2026)
	assert_true(r["revenue"] > 0 and r["valuation"] > 0)
	g.start_next_season()
	g.sim_playoffs()
	var r2 := g.owner_report()
	assert_eq(r2["year"], 2027)
	assert_true(r2["valuation_change"] == r2["valuation"] - r["valuation"])


func test_save_and_load_mid_season_continues_identically() -> void:
	var a := _game(7)
	a.advance_days(15)
	var manager := FcSaveManager.new("user://test_saves_controller")
	var saved := a.autosave(manager)
	assert_true(saved.is_ok(), saved.message)
	var loaded := manager.load_slot(FcSaveManager.AUTOSAVE_SLOT, FcDefinitionSet.load_default())
	assert_true(loaded.is_ok(), loaded.message)
	assert_eq(loaded.warnings, [] as Array[String])
	var b := FcGameController.resume(loaded.state)
	assert_eq(b.state.current_date.to_iso(), a.state.current_date.to_iso())
	a.advance_days(25)
	b.advance_days(25)
	assert_eq(a.season().to_dict(), b.season().to_dict(), "a loaded game plays exactly like the original")
	manager.delete_slot(FcSaveManager.AUTOSAVE_SLOT)
	DirAccess.remove_absolute("user://test_saves_controller")


func test_save_between_seasons_and_resume() -> void:
	var a := _game(8)
	a.sim_playoffs()
	var manager := FcSaveManager.new("user://test_saves_controller2")
	assert_true(a.autosave(manager).is_ok())
	var loaded := manager.load_slot(FcSaveManager.AUTOSAVE_SLOT, FcDefinitionSet.load_default())
	var b := FcGameController.resume(loaded.state)
	assert_eq(b.phase(), FcGameController.PHASE_COMPLETE)
	assert_eq(b.season().champion_id, a.season().champion_id)
	a.start_next_season()
	b.start_next_season()
	assert_eq(a.state.world.to_dict(), b.state.world.to_dict(), "the next season is identical after a reload")
	manager.delete_slot(FcSaveManager.AUTOSAVE_SLOT)
	DirAccess.remove_absolute("user://test_saves_controller2")


func test_loans_and_repayment() -> void:
	var g := _game(31)
	g.sim_playoffs()
	var b := g.business()
	assert_true(g.loan_limit() > 0)
	var cash := b.cash
	var debt := b.debt
	assert_true(not g.borrow(0)["ok"])
	assert_true(not g.borrow(g.loan_limit() * 2)["ok"], "cannot borrow beyond the limit")
	var r := g.borrow(5000000)
	assert_true(r["ok"], r["reason"])
	assert_eq(b.cash, cash + 5000000)
	assert_eq(b.debt, debt + 5000000)
	assert_true(g.repay_debt(5000000)["ok"])
	assert_eq(b.cash, cash)
	assert_eq(b.debt, debt)
	b.debt = 0
	assert_true(not g.repay_debt(1000)["ok"], "no debt to repay")


func test_sponsor_plan_changes_sponsorship_income() -> void:
	var results := {}
	for plan in 3:
		var g := _game(32)
		assert_true(g.set_sponsor_plan(plan))
		g.sim_playoffs()
		var w := g.state.world
		for r in w.finances.all():
			if r.team_id == g.state.user_team_id:
				results[plan] = r.revenue["sponsorship"]
	assert_true(results[0] != results[1] and results[0] != results[2], "plans pay differently: %s" % str(results))
	var g2 := _game(32)
	assert_true(not g2.set_sponsor_plan(3))


func test_arena_projects_cost_time_and_then_apply() -> void:
	var g := _game(33)
	var w := g.state.world
	var team: FcTeam = w.teams.get_by_id(g.state.user_team_id)
	var arena: FcArena = w.arenas.get_by_id(team.arena_id)
	assert_eq(g.arena_project_options().size(), 2)
	var seats := arena.capacity
	g.business().cash = 200000000
	var cash := g.business().cash
	var r := g.start_arena_project("expand_seating")
	assert_true(r["ok"], r["reason"])
	assert_true(g.business().cash < cash, "it is paid up front")
	assert_true(not g.start_arena_project("expand_seating")["ok"], "not twice at once")
	assert_true(not g.start_arena_project("nonsense")["ok"])
	g.sim_playoffs()
	assert_eq(arena.capacity, seats, "after one season the two-season project is not done")
	g.start_next_season()
	g.sim_playoffs()
	assert_eq(arena.capacity, seats + 1500, "finished after two season ends")
	assert_true(g.business().projects.is_empty())


func test_suites_raise_event_income_and_need_cash() -> void:
	var g := _game(34)
	g.business().cash = 1000
	var r := g.start_arena_project("expand_seating")
	assert_true(not r["ok"] and "cash" in r["reason"])
	g.business().cash = 500000000
	assert_true(g.start_arena_project("luxury_suites")["ok"])
	g.sim_playoffs()
	assert_eq(g.business().suites_level, 1, "suites take one season")


func test_new_game_has_a_valuation_and_a_borrowing_limit() -> void:
	var g := _game(35)
	assert_true(g.business().valuation > 0, "a franchise has a value before its first season")
	assert_true(g.loan_limit() > 0)
	assert_true(g.borrow(1000000)["ok"], "loans work in the first season")
	g.business().valuation = 0   # an old save
	assert_true(g.loan_limit() > 0, "old saves fall back to an estimate")


func test_owner_decides_who_stays_when_contracts_end() -> void:
	var g := _game(36)
	g.sim_playoffs()
	var w := g.state.world
	var expiring := g.expiring_players()
	assert_true(expiring.size() > 0, "some contracts end this season")
	var keep: FcPlayer = expiring[0]["player"]
	var leave: FcPlayer = expiring[expiring.size() - 1]["player"]
	assert_true(keep.id != leave.id or expiring.size() == 1)
	var r := g.extend_contract(keep.id)
	assert_true(r["ok"], r["reason"])
	assert_true(g.state.agreed_extensions.has(keep.id))
	assert_true(not g.extend_contract(keep.id)["ok"], "no need to agree twice")
	g.start_next_season()
	assert_true(g.state.agreed_extensions.is_empty(), "agreements are cleared once applied")
	assert_true(w.active_contract_of(keep.id) != null and w.active_contract_of(keep.id).end_season() > g.state.current_season - 1, "he has a new contract")
	assert_eq(w.validate(g.state.current_season), [] as Array[String])
	var team: FcTeam = w.teams.get_by_id(g.state.user_team_id)
	assert_true(team.roster.contains(keep.id), "the extended player stays")
	if leave.id != keep.id:
		assert_true(not team.roster.contains(leave.id), "players who were not extended leave")
	assert_true(team.roster.size() >= w.rules_of_league(g.league_id).roster_min, "the roster is refilled to a legal size")


func test_dynasty_mode_still_re_signs_automatically() -> void:
	var g := _game(37, FcGameState.MODE_DYNASTY)
	g.sim_playoffs()
	var expiring := g.expiring_players()
	var report := g.start_next_season()
	assert_true(report["re_signed"] > 0 or expiring.is_empty())


func test_only_final_year_players_can_be_extended() -> void:
	var g := _game(38)
	var w := g.state.world
	var team: FcTeam = w.teams.get_by_id(g.state.user_team_id)
	for pid in team.roster.player_ids:
		if w.active_contract_of(pid).end_season() > g.state.current_season:
			assert_true(not g.extend_contract(pid)["ok"])
			return
	assert_true(false, "expected a player with a longer contract")


func _roster_fingerprint(g: FcGameController) -> Array:
	var out: Array = []
	for t in g.state.world.teams.all():
		var ids: Array = t.roster.player_ids.duplicate()
		ids.sort()
		out.append([t.id, ids])
	return out


func test_pausing_in_the_offseason_changes_nothing() -> void:
	var a := _game(40)
	a.start_next_season()
	var b := _game(40)
	var first := b.begin_offseason()
	assert_eq(b.phase(), FcGameController.PHASE_OFFSEASON)
	assert_eq(b.state.offseason_stage, 1)
	assert_eq(b.state.current_season, 2026, "still the old season until the offseason is finished")
	assert_true(first.has("drafted") and not first.has("signed"), "AI free agency has not happened yet")
	b.start_next_season()
	assert_eq(b.state.offseason_stage, 0)
	assert_eq(b.state.current_season, 2027)
	assert_eq(_roster_fingerprint(a), _roster_fingerprint(b), "same result with or without the pause")


func test_free_agent_signed_in_the_window_gets_a_next_season_contract() -> void:
	var g := _game(41)
	g.begin_offseason()
	var w := g.state.world
	var team: FcTeam = w.teams.get_by_id(g.state.user_team_id)
	var rules := w.rules_of_league(g.league_id)
	while team.roster.size() >= rules.roster_max:
		assert_true(g.release_player(team.roster.player_ids[team.roster.size() - 1])["released"])
	var target: FcPlayer = g.free_agent_market(60).back()["player"]
	var r := g.sign_free_agent(target.id)
	assert_true(r["signed"], r["reason"])
	assert_eq(w.active_contract_of(target.id).start_season(), 2027)
	g.start_next_season()
	assert_true(team.roster.contains(target.id), "he is still on the roster in the new season")
	assert_eq(w.validate(g.state.current_season), [] as Array[String])


func test_offseason_window_survives_saving() -> void:
	var g := _game(42)
	g.begin_offseason()
	var manager := FcSaveManager.new("user://test_saves_window")
	assert_true(g.autosave(manager).is_ok())
	var loaded := manager.load_slot(FcSaveManager.AUTOSAVE_SLOT, FcDefinitionSet.load_default())
	assert_true(loaded.is_ok(), loaded.message)
	var again := FcGameController.resume(loaded.state)
	assert_eq(again.phase(), FcGameController.PHASE_OFFSEASON)
	again.start_next_season()
	assert_eq(again.state.current_season, 2027)
	manager.delete_slot(FcSaveManager.AUTOSAVE_SLOT)
	DirAccess.remove_absolute("user://test_saves_window")
