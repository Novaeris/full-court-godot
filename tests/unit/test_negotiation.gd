extends FcTestCase
## Contract negotiation with free agents and with the owner's own players.

var g: FcGameController


func before_each() -> void:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 12
	cfg.roster_min = 12
	cfg.free_agent_count = 15
	g = FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), 70, FcGameState.MODE_OWNER, 0)


func test_required_salary_falls_with_longer_contracts_and_loyalty() -> void:
	var market := FcPlayerMarket.new(FcPlayerRatings.load_default())
	var rules := g.state.world.rules_of_league(1)
	var p: FcPlayer = g.free_agent_market(1)[0]["player"]
	var age := 27
	var desired := market.desired_years(age, rules.cap)
	var base := market.minimum_acceptable(p, age, rules.cap, desired, false)
	var ask := market.asking_salary(p, age, rules.cap)
	assert_true(base < ask, "players accept a little less than they ask")
	assert_true(market.minimum_acceptable(p, age, rules.cap, mini(desired + 1, rules.cap.max_contract_years), false) <= base, "longer security = a lower price")
	assert_true(market.minimum_acceptable(p, age, rules.cap, maxi(desired - 1, 1), false) >= base, "shorter = a higher price")
	assert_true(market.minimum_acceptable(p, age, rules.cap, desired, true) < base, "own players give a discount")


func test_lowball_offers_are_refused_with_a_counter() -> void:
	var star: FcPlayer = g.free_agent_market(1)[0]["player"]
	var r := g.sign_free_agent(star.id, 1000000, 3)
	assert_true(not r["signed"] and r["required"] > 1000000, r["reason"])
	assert_true("at least" in r["reason"])
	assert_true(g.state.world.team_of_player(star.id) == null, "nothing happened")


func test_a_counter_offer_is_accepted_when_the_cap_allows() -> void:
	var w := g.state.world
	var rules := w.rules_of_league(1)
	var team: FcTeam = w.teams.get_by_id(g.state.user_team_id)
	# cheap free agent so the cap is no obstacle
	var target: FcPlayer = g.free_agent_market(100).back()["player"]
	var first := g.sign_free_agent(target.id, rules.cap.min_player_salary * 3, 2)
	assert_true(first["signed"], first["reason"])
	var c := w.active_contract_of(target.id)
	assert_eq(c.length(), 2, "the contract has the offered length")
	assert_true(c.years[0].salary >= rules.cap.min_player_salary * 3 - 10000, "and the offered salary")
	assert_true(team.roster.contains(target.id))


func test_extension_terms_are_used_in_the_new_contract() -> void:
	g.sim_playoffs()
	var w := g.state.world
	var entry: Dictionary = g.expiring_players()[0]
	var p: FcPlayer = entry["player"]
	var low := g.extend_contract(p.id, 100000, 2)
	assert_true(not low["ok"] and low["required"] > 100000, "a silly offer is refused")
	var salary: int = int(entry["ask"])
	var r := g.extend_contract(p.id, salary, 3)
	assert_true(r["ok"], r["reason"])
	assert_eq(g.state.agreed_terms[p.id], [salary, 3])
	g.start_next_season()
	var c := w.active_contract_of(p.id)
	assert_true(c != null, "he has a new contract")
	assert_eq(c.length(), 3)
	assert_true(absi(c.years[0].salary - salary) <= 10000)
	assert_true(g.state.agreed_terms.is_empty(), "terms are cleared once used")


func test_agreed_terms_are_saved() -> void:
	var state := FcGameState.new(FcWorld.new(FcDefinitionSet.load_default()), FcRng.new(1))
	state.agreed_terms = {7: [3500000, 4]}
	var back := FcGameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), FcDefinitionSet.load_default())
	assert_eq(back.agreed_terms, {7: [3500000, 4]})
	var old := state.to_dict()
	old.erase("agreed_terms")
	assert_true(FcGameState.from_dict(old, FcDefinitionSet.load_default()).agreed_terms.is_empty())
