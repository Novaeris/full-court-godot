extends FcTestCase
## Staff chemistry (philosophy agreement, personality, roster fit, continuity) and the general manager's
## negotiation skill in the owner's deals.

var g: FcGameController


func before_each() -> void:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 20
	cfg.assistant_coaches = 2
	cfg.scouts = 1
	g = FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), 515, FcGameState.MODE_OWNER, 0)


func _set_all(m: FcStaffMember, philosophy: int, ego: int, professionalism: int, adaptability: int) -> void:
	for key in FcStaffChemistry.PHILOSOPHY_KEYS:
		m.philosophy.set_clamped(key, philosophy)
	m.personality.set_clamped("ego", ego)
	m.personality.set_clamped("professionalism", professionalism)
	m.personality.set_clamped("adaptability", adaptability)


func _part(result: Dictionary, key: String) -> float:
	for p in result["parts"]:
		if p["key"] == key:
			return p["value"]
	return -1.0


func test_chemistry_is_a_score_with_four_parts_and_a_label() -> void:
	var c := g.staff_chemistry()
	assert_between(c["score"], 0, 100)
	assert_eq(c["parts"].size(), 4)
	assert_true(c["label"] in ["Excellent", "Good", "Average", "Poor", "Toxic"])
	assert_eq(c["score"], g.staff_chemistry()["score"], "derived, so always the same")


func test_agreement_is_high_when_everyone_thinks_alike_and_low_when_opposed() -> void:
	var w := g.state.world
	var tid := g.state.user_team_id
	var gm := w.staff_in_role(tid, FcStaffRole.Id.GENERAL_MANAGER)
	var coach := w.staff_in_role(tid, FcStaffRole.Id.HEAD_COACH)
	for sc in w.staff_contracts_of_team(tid, FcStaffRole.Id.ASSISTANT_COACH):
		_set_all(w.staff.get_by_id(sc.staff_id), 50, 50, 50, 50)
	_set_all(gm, 50, 50, 50, 50)
	_set_all(coach, 50, 50, 50, 50)
	assert_eq(_part(g.staff_chemistry(), "agreement"), 100.0)
	_set_all(coach, 100, 50, 50, 50)
	_set_all(gm, 0, 50, 50, 50)
	assert_between(_part(g.staff_chemistry(), "agreement"), 0.0, 5.0, "opposite philosophies")


func test_big_egos_clash_and_professionals_get_along() -> void:
	var w := g.state.world
	var tid := g.state.user_team_id
	for sc in w.staff_contracts_of_team(tid):
		_set_all(w.staff.get_by_id(sc.staff_id), 50, 20, 90, 90)
	var calm := _part(g.staff_chemistry(), "personality")
	for sc in w.staff_contracts_of_team(tid):
		_set_all(w.staff.get_by_id(sc.staff_id), 50, 95, 50, 50)
	var clash := _part(g.staff_chemistry(), "personality")
	assert_true(calm > 80.0 and clash < 30.0, "calm %.0f vs clash %.0f" % [calm, clash])


func test_roster_fit_and_continuity() -> void:
	var w := g.state.world
	var tid := g.state.user_team_id
	var coach := w.staff_in_role(tid, FcStaffRole.Id.HEAD_COACH)
	var team: FcTeam = w.teams.get_by_id(tid)
	var avg := 0.0
	for pid in team.roster.player_ids:
		avg += w.players.get_by_id(pid).tendencies.get_value("three_point_tendency")
	avg /= team.roster.size()
	coach.philosophy.set_clamped("three_point_emphasis", roundi(avg))
	var matched := _part(g.staff_chemistry(), "roster_fit")
	coach.philosophy.set_clamped("three_point_emphasis", 0 if avg > 50 else 100)
	assert_true(_part(g.staff_chemistry(), "roster_fit") < matched, "a coach who dislikes what the roster does fits worse")
	var year := g.contract_year()
	var young := FcStaffChemistry.new(w).evaluate(tid, year)
	var old := FcStaffChemistry.new(w).evaluate(tid, year + 4)
	assert_true(_part(old, "continuity") > _part(young, "continuity"), "staff together for years know each other")


func test_hiring_preview_replaces_the_unique_role_and_adds_the_rest() -> void:
	var w := g.state.world
	var pool := g.staff_pool(FcStaffRole.Id.HEAD_COACH)
	assert_true(pool.size() > 0)
	var candidate: FcStaffMember = pool[0]
	var coach := w.staff_in_role(g.state.user_team_id, FcStaffRole.Id.HEAD_COACH)
	var gm := w.staff_in_role(g.state.user_team_id, FcStaffRole.Id.GENERAL_MANAGER)
	for key in FcStaffChemistry.PHILOSOPHY_KEYS:
		gm.philosophy.set_clamped(key, 50)
		candidate.philosophy.set_clamped(key, 50)
		coach.philosophy.set_clamped(key, 0)
	var with_candidate := g.staff_chemistry(candidate.id, FcStaffRole.Id.HEAD_COACH)
	assert_true(_part(with_candidate, "agreement") > _part(g.staff_chemistry(), "agreement"), "a head coach who thinks like the GM raises agreement")
	assert_eq(w.staff_in_role(g.state.user_team_id, FcStaffRole.Id.HEAD_COACH).id, coach.id, "a preview changes nothing")


func test_chemistry_moves_player_development() -> void:
	assert_true(FcStaffChemistry.development_bonus(90) > 0.0)
	assert_true(FcStaffChemistry.development_bonus(30) < 0.0)
	assert_eq(FcStaffChemistry.development_bonus(60), 0.0)
	var off := FcOffseason.new(g.state.world)
	var tid := g.state.user_team_id
	var year := g.contract_year() + 1
	var base := off._coach_development(tid)
	var with_chemistry := off._coach_development(tid, year)
	var bonus: float = FcStaffChemistry.new(g.state.world).evaluate(tid, year)["development_bonus"]
	assert_true(absf(with_chemistry - clampf(base + bonus, 0.0, 100.0)) < 0.001, "development = coaching + chemistry")


func test_a_better_negotiating_general_manager_gets_cheaper_deals() -> void:
	var w := g.state.world
	var gm := w.staff_in_role(g.state.user_team_id, FcStaffRole.Id.GENERAL_MANAGER)
	var market := FcPlayerMarket.new(FcPlayerRatings.load_default())
	var rules := w.rules_of_league(g.league_id)
	var p: FcPlayer = w.players.get_by_id(w.teams.get_by_id(2).roster.player_ids[0])
	var poor := market.minimum_acceptable(p, 27, rules.cap, 3, false, 0.0)
	var average := market.minimum_acceptable(p, 27, rules.cap, 3, false, 50.0)
	var great := market.minimum_acceptable(p, 27, rules.cap, 3, false, 100.0)
	assert_true(poor >= average and average >= great and poor > great, "%d >= %d >= %d" % [poor, average, great])
	gm.skills.set_clamped("negotiation", 100)
	assert_eq(g.gm_negotiation(), 100.0)
	gm.skills.set_clamped("negotiation", 10)
	assert_eq(g.gm_negotiation(), 10.0)


func test_the_negotiation_skill_lowers_the_ai_price_in_trades() -> void:
	var w := g.state.world
	var desk := FcTradeDesk.new(w)
	var found := false
	for a in w.teams.get_by_id(g.state.user_team_id).roster.player_ids:
		for b in w.teams.get_by_id(2).roster.player_ids:
			var poor := desk.propose(g.league_id, g.contract_year(), g.state.user_team_id, 2, [a], [b], false, false, [], [], g.first_tradable_pick_year(), 0.0)
			var great := desk.propose(g.league_id, g.contract_year(), g.state.user_team_id, 2, [a], [b], false, false, [], [], g.first_tradable_pick_year(), 100.0)
			assert_true(not (poor["accepted"] and not great["accepted"]), "a better negotiator never does worse")
			if great["accepted"] and not poor["accepted"]:
				found = true
	assert_true(found, "some deal needs the better negotiator")
