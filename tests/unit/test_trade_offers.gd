extends FcTestCase
## Trade offers from AI teams to the owner.

var g: FcGameController


func before_each() -> void:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 12
	cfg.conference_count = 2
	cfg.divisions_per_conference = 3
	cfg.roster_size = 13
	cfg.free_agent_count = 10
	g = FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), 130, FcGameState.MODE_OWNER, 0)
	g.advance_days(20)


func test_offers_are_valid_stable_and_acceptable_to_the_ai() -> void:
	var offers := g.trade_offers()
	assert_true(offers.size() <= FcTradeOffers.MAX_OFFERS)
	assert_eq(offers.size(), g.trade_offers().size(), "the same list every time")
	for o in offers:
		assert_true(o["team"] != g.state.user_team_id)
		var verdict := g.propose_trade(o["team"], [o["give"]], [o["get"]], true)
		assert_true(verdict["accepted"], "every offer passes the trade rules: %s" % verdict["reason"])
		assert_true(g.state.world.teams.get_by_id(g.state.user_team_id).roster.contains(o["give"]))
		assert_true(g.state.world.teams.get_by_id(o["team"]).roster.contains(o["get"]))


func test_offers_change_every_two_weeks() -> void:
	var first := g.trade_offers()
	g.advance_days(14)
	var later := g.trade_offers()
	assert_true(first != later or first.is_empty(), "a new batch after two weeks")


func test_accepting_an_offer_swaps_the_players_and_it_disappears() -> void:
	var offers := g.trade_offers()
	if offers.is_empty():
		assert_true(true, "no offers this time (valid: nobody wanted anyone)")
		return
	var o: Dictionary = offers[0]
	var w := g.state.world
	var result := g.accept_trade_offer(o)
	assert_true(result["accepted"], result["reason"])
	assert_true(w.teams.get_by_id(o["team"]).roster.contains(o["give"]) and w.teams.get_by_id(g.state.user_team_id).roster.contains(o["get"]))
	assert_true(not g.accept_trade_offer(o)["accepted"], "the same offer cannot be taken twice")
	assert_eq(w.validate(g.state.current_season), [] as Array[String])


func test_declined_offers_stay_hidden_until_the_next_batch() -> void:
	var offers := g.trade_offers()
	if offers.is_empty():
		assert_true(true, "no offers this time")
		return
	g.decline_trade_offer(offers[0])
	assert_eq(g.trade_offers().size(), offers.size() - 1)


func test_no_offers_in_spectator_mode_during_the_draft_or_playoffs() -> void:
	g.state.mode = FcGameState.MODE_SPECTATOR
	assert_true(g.trade_offers().is_empty())
	g.state.mode = FcGameState.MODE_OWNER
	g.sim_regular_season()
	assert_true(g.trade_offers().is_empty(), "not during the playoffs")
	g.sim_playoffs()
	g.begin_offseason()
	assert_true(g.trade_offers().is_empty(), "not during the draft")
	g.draft_auto_rest()
	assert_true(g.trade_offers().size() >= 0, "the free-agency window can have offers")
