extends FcTestCase
## Trades proposed by the human owner.

var g: FcGameController
var user_id: int
var ai_id: int


func before_each() -> void:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 5
	g = FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), 33, FcGameState.MODE_OWNER, 0)
	user_id = g.state.user_team_id
	ai_id = 1 if user_id != 1 else 2


func _best(team_id: int) -> int:
	var ratings := FcPlayerRatings.load_default()
	var team: FcTeam = g.state.world.teams.get_by_id(team_id)
	var best := 0
	var top := -1.0
	for pid in team.roster.player_ids:
		var o := ratings.overall(g.state.world.players.get_by_id(pid))
		if o > top:
			top = o
			best = pid
	return best


func _worst(team_id: int) -> int:
	var ratings := FcPlayerRatings.load_default()
	var team: FcTeam = g.state.world.teams.get_by_id(team_id)
	var worst := 0
	var low := 1000.0
	for pid in team.roster.player_ids:
		var o := ratings.overall(g.state.world.players.get_by_id(pid))
		if o < low:
			low = o
			worst = pid
	return worst


func test_asking_for_a_star_with_a_scrub_is_refused() -> void:
	var r := g.propose_trade(ai_id, [_worst(user_id)], [_best(ai_id)])
	assert_true(not r["accepted"], r["reason"])
	assert_true(g.state.world.teams.get_by_id(ai_id).roster.contains(_best(ai_id)), "nothing moved")


func test_a_generous_offer_is_accepted_and_players_move() -> void:
	var star := _best(user_id)
	var scrub := _worst(ai_id)
	# equal salaries so the cap's matching rule does not decide this test
	var year := g.state.current_season
	g.state.world.active_contract_of(scrub).year_for(year).salary = g.state.world.active_contract_of(star).year_for(year).salary
	var preview := g.propose_trade(ai_id, [star], [scrub], true)
	assert_true(preview["accepted"], preview["reason"])
	assert_true(g.state.world.teams.get_by_id(user_id).roster.contains(star), "preview does not move anyone")
	var r := g.propose_trade(ai_id, [star], [scrub])
	assert_true(r["accepted"], r["reason"])
	var w := g.state.world
	assert_true(w.teams.get_by_id(ai_id).roster.contains(star) and w.teams.get_by_id(user_id).roster.contains(scrub))
	assert_eq(w.active_contract_of(star).team_id, ai_id)
	assert_eq(w.active_contract_of(scrub).team_id, user_id)
	assert_eq(w.validate(g.state.current_season), [] as Array[String])


func test_roster_limits_are_enforced() -> void:
	var w := g.state.world
	var big := _best(ai_id)
	var ids: Array = []
	for pid in w.teams.get_by_id(user_id).roster.player_ids.slice(0, 5):
		ids.append(pid)
	var r := g.propose_trade(ai_id, ids, [_worst(ai_id)], true)
	assert_true(not r["accepted"] and big > 0)
	assert_true("roster" in r["reason"].to_lower() or "payroll" in r["reason"].to_lower() or "cap" in r["reason"].to_lower() or "offer" in r["reason"].to_lower(), r["reason"])


func test_no_trade_clause_blocks_it() -> void:
	var w := g.state.world
	var star := _best(user_id)
	w.active_contract_of(star).no_trade = true
	var rules := w.rules_of_league(g.league_id)
	rules.cap.no_trade_clauses_allowed = true
	var r := g.propose_trade(ai_id, [star], [_worst(ai_id)], true)
	assert_true(not r["accepted"] and "no-trade" in r["reason"], r["reason"])


func test_bad_inputs_are_refused() -> void:
	assert_true(not g.propose_trade(user_id, [], [])["accepted"], "cannot trade with yourself")
	assert_true(not g.propose_trade(ai_id, [], [])["accepted"], "empty trade")
	assert_true(not g.propose_trade(ai_id, [_best(ai_id)], [_worst(ai_id)])["accepted"], "offering a player you do not own")
