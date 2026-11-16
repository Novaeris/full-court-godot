extends FcTestCase
## Hiring and keeping staff with salary and years.

var g: FcGameController


func before_each() -> void:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 12
	cfg.roster_min = 12
	cfg.free_agent_count = 10
	cfg.assistant_coaches = 1
	cfg.scouts = 2
	g = FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), 110, FcGameState.MODE_OWNER, 0)


func _unemployed_scout() -> FcStaffMember:
	var pool := g.staff_pool(FcStaffRole.Id.SCOUT)
	assert_true(pool.size() > 0, "there is a scout to hire")
	return pool[0]


func test_staff_accept_a_little_less_for_longer_deals_and_their_own_team() -> void:
	var m := _unemployed_scout()
	var ask := g.asking_salary(m.id)
	var normal := g.staff_minimum_acceptable(m.id, 3)
	assert_true(normal < ask and normal > 0, "a small discount")
	assert_true(g.staff_minimum_acceptable(m.id, 5) <= normal, "longer security = a lower price")
	assert_true(g.staff_minimum_acceptable(m.id, 1) >= normal, "shorter = a higher price")
	assert_true(g.staff_minimum_acceptable(m.id, 3, true) < normal, "re-signing with his team is cheaper")


func test_hiring_with_terms() -> void:
	var w := g.state.world
	var m := _unemployed_scout()
	var refused := g.hire_staff(m.id, FcStaffRole.Id.SCOUT, 3, 1000)
	assert_true("at least" in refused, refused)
	assert_true(w.active_staff_contract_of(m.id) == null, "nothing happened")
	var ask := g.asking_salary(m.id)
	assert_eq(g.hire_staff(m.id, FcStaffRole.Id.SCOUT, 4, ask), "")
	var c := w.active_staff_contract_of(m.id)
	assert_eq(c.team_id, g.state.user_team_id)
	assert_eq(c.years.size(), 4, "the offered length")
	assert_true(absi(c.years[0].salary - ask) <= 10000, "and the offered salary")
	var m2 := g.staff_pool(FcStaffRole.Id.SCOUT)[0]
	assert_eq(g.hire_staff(m2.id, FcStaffRole.Id.SCOUT, 3), "", "no terms = the asking salary")


func test_the_owner_can_keep_a_staff_member_or_let_him_go() -> void:
	var w := g.state.world
	var team_id := g.state.user_team_id
	var scouts := w.staff_contracts_of_team(team_id, FcStaffRole.Id.SCOUT)
	var keep := scouts[0]
	var go := scouts[1]
	for sc in [keep, go]:
		for y in sc.years:
			y.season = 2026   # both contracts end this season
	g.sim_playoffs()
	var expiring := g.expiring_staff()
	assert_true(expiring.any(func(e): return e["member"].id == keep.staff_id))
	var low := g.extend_staff(keep.staff_id, 1000, 3)
	assert_true(not low["ok"] and low["required"] > 1000, "a silly offer is refused")
	var ask := g.asking_salary(keep.staff_id)
	var r := g.extend_staff(keep.staff_id, ask, 2)
	assert_true(r["ok"], r["reason"])
	assert_true(not g.extend_staff(keep.staff_id)["ok"], "no need to agree twice")
	g.start_next_season()
	var kept_contract := w.active_staff_contract_of(keep.staff_id)
	assert_true(kept_contract != null and kept_contract.team_id == team_id, "he stayed")
	assert_eq(kept_contract.years.size(), 2)
	assert_true(absi(kept_contract.years[0].salary - ask) <= 10000)
	var left := w.active_staff_contract_of(go.staff_id)
	assert_true(left == null or left.team_id != team_id, "the other one left")
	assert_eq(w.staff_contracts_of_team(team_id, FcStaffRole.Id.SCOUT).size(), 2, "and the vacancy was filled")
	assert_true(g.state.agreed_staff_terms.is_empty(), "agreements are cleared")


func test_the_gm_keeps_good_staff_when_contracts_are_delegated() -> void:
	g.set_delegation("contracts", true)
	var w := g.state.world
	var scouts := w.staff_contracts_of_team(g.state.user_team_id, FcStaffRole.Id.SCOUT)
	for y in scouts[0].years:
		y.season = 2026
	w.staff.get_by_id(scouts[0].staff_id).reputation = 70
	g.sim_playoffs()
	g._gm_log = []
	g._gm_re_sign_players()
	assert_true(g.gm_log().any(func(line): return "kept" in line), "he kept the good scout")
	assert_true(g.state.agreed_staff_terms.has(scouts[0].staff_id))


func test_agreed_staff_terms_are_saved() -> void:
	var state := FcGameState.new(FcWorld.new(FcDefinitionSet.load_default()), FcRng.new(1))
	state.agreed_staff_terms = {12: [900000, 3]}
	var back := FcGameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), FcDefinitionSet.load_default())
	assert_eq(back.agreed_staff_terms, {12: [900000, 3]})
	var old := state.to_dict()
	old.erase("agreed_staff_terms")
	assert_true(FcGameState.from_dict(old, FcDefinitionSet.load_default()).agreed_staff_terms.is_empty())
	assert_eq(back.agreed_terms, {}, "player terms are separate")
