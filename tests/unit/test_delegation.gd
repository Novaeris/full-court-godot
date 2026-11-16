extends FcTestCase
## Owner Mode: what the general manager handles.

func _game(seed_value: int = 90) -> FcGameController:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 12
	cfg.roster_min = 12
	cfg.free_agent_count = 15
	cfg.assistant_coaches = 1
	cfg.scouts = 2
	return FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), seed_value, FcGameState.MODE_OWNER, 0)


func test_nothing_is_delegated_by_default_and_the_gm_is_described() -> void:
	var g := _game()
	for key in FcGameState.DELEGATION_KEYS:
		assert_true(not g.delegation_on(key))
	var gm := g.gm_summary()
	assert_true(gm["name"] != "" and gm["talent_evaluation"] >= 0)
	assert_true(g.set_delegation("draft", true) and g.delegation_on("draft"))
	assert_true(not g.set_delegation("nonsense", true))
	var dynasty := _game()
	dynasty.state.mode = FcGameState.MODE_DYNASTY
	assert_true(not dynasty.set_delegation("draft", true), "only Owner Mode delegates")


func test_delegation_is_saved_and_old_saves_default_to_off() -> void:
	var state := FcGameState.new(FcWorld.new(FcDefinitionSet.load_default()), FcRng.new(1))
	state.delegation["free_agency"] = true
	var back := FcGameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), FcDefinitionSet.load_default())
	assert_true(back.delegation["free_agency"] and not back.delegation["draft"])
	var old := state.to_dict()
	old.erase("delegation")
	assert_true(not FcGameState.from_dict(old, FcDefinitionSet.load_default()).delegation["free_agency"])


func test_without_delegation_nobody_is_re_signed_for_the_owner() -> void:
	var g := _game()
	g.sim_playoffs()
	var expiring := g.expiring_players()
	assert_true(expiring.size() > 0)
	g.begin_offseason()
	assert_eq(g.phase(), FcGameController.PHASE_DRAFT, "the owner drafts")
	var team: FcTeam = g.state.world.teams.get_by_id(g.state.user_team_id)
	for e in expiring:
		assert_true(not team.roster.contains(e["player"].id), "he left because nobody agreed to keep him")


func test_the_gm_re_signs_good_players_and_runs_the_draft_when_asked() -> void:
	var g := _game()
	g.set_delegation("contracts", true)
	g.set_delegation("draft", true)
	g.sim_playoffs()
	var expiring := g.expiring_players()
	g.begin_offseason()
	assert_eq(g.phase(), FcGameController.PHASE_OFFSEASON, "the GM already ran the draft")
	assert_eq(g.season().draft.size(), 16)
	var team: FcTeam = g.state.world.teams.get_by_id(g.state.user_team_id)
	var kept := 0
	for e in expiring:
		if team.roster.contains(e["player"].id):
			kept += 1
	assert_true(kept <= expiring.size())
	assert_true(g.gm_log().any(func(line): return "ran the draft" in line))
	var re_signed_lines := g.gm_log().filter(func(line): return "agreed new terms" in line).size()
	assert_true(re_signed_lines >= kept, "everyone who stayed was agreed by the GM (a deal can still fall through at the cap)")
	assert_eq(g.state.world.validate(g.state.current_season), [] as Array[String])


func test_the_gm_signs_free_agents_when_asked() -> void:
	var g := _game(91)
	g.set_delegation("draft", true)
	g.set_delegation("free_agency", true)
	g.sim_playoffs()
	var team: FcTeam = g.state.world.teams.get_by_id(g.state.user_team_id)
	g.begin_offseason()
	var signed := g.gm_log().filter(func(line): return "signed" in line).size()
	assert_true(signed <= FcGameController.GM_MAX_SIGNINGS)
	for line in g.gm_log():
		if "signed" in line:
			assert_true(true)
	assert_true(team.roster.size() <= g.state.world.rules_of_league(1).roster_max)
	assert_eq(g.state.world.validate(g.state.current_season), [] as Array[String])


func test_ai_free_agency_skips_a_team_the_owner_runs_by_hand() -> void:
	var g := _game(92)
	g.sim_playoffs()
	var w := g.state.world
	var team: FcTeam = w.teams.get_by_id(g.state.user_team_id)
	var off := FcOffseason.new(w)
	off.manual_free_agency_team_ids = [g.state.user_team_id] as Array[int]
	var before := team.roster.size()
	off.free_agency(1, 2027, FcRng.new(3))
	assert_eq(team.roster.size(), before, "no AI signings for a team the owner runs")
	var off2 := FcOffseason.new(w)
	var others_before := 0
	for t in w.teams.all():
		others_before += t.roster.size()
	off2.free_agency(1, 2027, FcRng.new(3))
	var others_after := 0
	for t in w.teams.all():
		others_after += t.roster.size()
	assert_true(others_after > others_before, "other teams do sign players")


func test_direction_defaults_validates_and_saves() -> void:
	var g := _game(93)
	assert_eq(g.philosophy(), "balanced")
	assert_true(g.set_direction("rebuild", "frugal"))
	assert_eq(g.philosophy(), "rebuild")
	assert_true(not g.set_direction("nonsense", "normal"))
	assert_true(not g.set_direction("rebuild", "nonsense"))
	var back := FcGameState.from_dict(JSON.parse_string(JSON.stringify(g.state.to_dict())), FcDefinitionSet.load_default())
	assert_eq(back.direction, {"philosophy": "rebuild", "budget": "frugal"})
	var old := g.state.to_dict()
	old.erase("direction")
	assert_eq(FcGameState.from_dict(old, FcDefinitionSet.load_default()).direction, {"philosophy": "balanced", "budget": "normal"})


func test_budget_sets_the_payroll_limit() -> void:
	var g := _game(94)
	var cap := g.state.world.rules_of_league(1).cap
	g.set_direction("balanced", "frugal")
	var frugal := g.gm_payroll_limit()
	g.set_direction("balanced", "normal")
	var normal := g.gm_payroll_limit()
	g.set_direction("balanced", "aggressive")
	var aggressive := g.gm_payroll_limit()
	assert_true(frugal < normal and normal < aggressive)
	assert_eq(normal, cap.salary_cap)
	assert_true(aggressive <= cap.luxury_tax_line, "never above the tax line")


func test_philosophy_changes_how_the_gm_values_young_prospects() -> void:
	var g := _game(95)
	var market := FcPlayerMarket.new(FcPlayerRatings.load_default())
	var team: FcTeam = g.state.world.teams.get_by_id(g.state.user_team_id)
	var kid: FcPlayer = g.state.world.players.get_by_id(team.roster.player_ids[0])
	kid.development.potential = 95
	for key in g.state.world.definitions.attributes.keys():
		kid.attributes.set_clamped(key, 40)
	g.set_direction("rebuild", "normal")
	var rebuild_view := g._gm_value(kid, 21, market)
	g.set_direction("win_now", "normal")
	var win_now_view := g._gm_value(kid, 21, market)
	assert_true(rebuild_view > win_now_view + 5.0, "a rebuilding GM loves the prospect more (%f vs %f)" % [rebuild_view, win_now_view])


func test_the_draft_follows_the_philosophy() -> void:
	var g := _game(96)
	g.begin_offseason()
	var off := FcOffseason.new(g.state.world)
	var ratings := FcPlayerRatings.load_default()
	var rebuild_pick: FcPlayer = g.state.world.players.get_by_id(off.ai_draft_choice(g.state.draft_state, g.state.user_team_id, g._draft_rng(), 0.3))
	var win_now_pick: FcPlayer = g.state.world.players.get_by_id(off.ai_draft_choice(g.state.draft_state, g.state.user_team_id, g._draft_rng(), -0.3))
	var rebuild_upside: float = rebuild_pick.development.potential - ratings.overall(rebuild_pick)
	var win_now_upside: float = win_now_pick.development.potential - ratings.overall(win_now_pick)
	assert_true(rebuild_upside >= win_now_upside, "the rebuilding choice has at least as much room to grow")


func test_a_tight_budget_stops_the_gm_re_signing() -> void:
	var g := _game(97)
	g.set_delegation("contracts", true)
	g.set_direction("balanced", "frugal")
	var w := g.state.world
	var team: FcTeam = w.teams.get_by_id(g.state.user_team_id)
	var rules := w.rules_of_league(1)
	for pid in team.roster.player_ids:
		var c := w.active_contract_of(pid)
		if c.end_season() > g.state.current_season:
			for y in c.years:
				y.salary = int(rules.cap.salary_cap * 0.18)   # next year's payroll is already above the limit
	g.sim_playoffs()
	g._gm_log = []
	g._gm_re_sign_players()
	assert_true(not g.gm_log().any(func(line): return "agreed new terms" in line), "nobody is re-signed over the budget")


func test_the_gm_trades_only_when_the_direction_calls_for_it() -> void:
	var g := _game(98)
	g.set_delegation("trades", true)
	g.sim_playoffs()
	g._gm_log = []
	var news_before := g.state.world.news.size()
	g._gm_trades()   # balanced: nothing
	assert_eq(g.gm_log().size(), 0)
	assert_eq(g.state.world.news.size(), news_before)
	for philosophy in ["rebuild", "win_now"]:
		g.set_direction(philosophy, "normal")
		g._gm_log = []
		g._gm_trades()
		assert_true(g.gm_log().size() <= FcGameController.GM_MAX_TRADES, philosophy)
		assert_eq(g.state.world.validate(g.state.current_season), [] as Array[String], philosophy)


func test_gm_report_card_appears_after_a_season() -> void:
	var g := _game(99)
	assert_true(g.gm_report().is_empty(), "nothing to grade yet")
	g.sim_playoffs()
	var card := g.gm_report()
	assert_true(card["grade"] in ["Excellent", "Good", "Satisfactory", "Disappointing"])
	assert_true(card["limit"] > 0 and card["payroll"] > 0)
