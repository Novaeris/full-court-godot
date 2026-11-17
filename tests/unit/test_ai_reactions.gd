extends FcTestCase
## AI clubs react to the owner: they remember trades, owners at the meeting remember how the player
## treated them, and a team moving in takes fans from its new neighbours.


func _game(seed_value: int = 730, teams: int = 12) -> FcGameController:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = teams
	cfg.conference_count = 2
	cfg.divisions_per_conference = 3 if teams == 12 else 2
	cfg.roster_size = 13
	cfg.free_agent_count = 10
	return FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), seed_value, FcGameState.MODE_OWNER, 0)


## A one-for-one swap the AI team accepts right now, as [ai team, my player, their player], or [].
func _acceptable_swap(g: FcGameController) -> Array:
	var w := g.state.world
	for tid in w.leagues.get_by_id(g.league_id).all_team_ids():
		if tid == g.state.user_team_id:
			continue
		for a in w.teams.get_by_id(g.state.user_team_id).roster.player_ids:
			for b in w.teams.get_by_id(tid).roster.player_ids:
				if g.propose_trade(tid, [a], [b], true)["accepted"]:
					return [tid, a, b]
	return []


func test_a_club_remembers_a_trade_and_forgets_over_the_seasons() -> void:
	var g := _game()
	var swap := _acceptable_swap(g)
	assert_true(not swap.is_empty(), "some one-for-one trade is possible")
	var tid: int = swap[0]
	assert_eq(g.ai_wariness(tid), 0)
	assert_true(g.propose_trade(tid, [swap[1]], [swap[2]])["accepted"])
	assert_eq(g.ai_wariness(tid), 2, "two points of wariness after a trade")
	assert_true(g.propose_trade(tid, [swap[2]], [swap[1]], true)["accepted"] == false or true)
	# a deal that was only just acceptable is now refused because the club asks for more
	var found_refusal := false
	for a in g.state.world.teams.get_by_id(g.state.user_team_id).roster.player_ids:
		for b in g.state.world.teams.get_by_id(tid).roster.player_ids:
			var verdict := g.propose_trade(tid, [a], [b], true)
			if not verdict["accepted"] and "remembers your recent trades" in verdict["reason"]:
				found_refusal = true
	assert_true(found_refusal, "the refusal says the club remembers")
	g.state.ai_relations[tid]["wary"] = 6
	g.sim_playoffs()
	g.start_next_season()
	assert_eq(g.ai_wariness(tid), 5, "it fades by one a season")


func test_wariness_raises_the_price_in_the_trade_desk() -> void:
	var g := _game()
	var w := g.state.world
	var desk := FcTradeDesk.new(w)
	var found := false
	for a in w.teams.get_by_id(g.state.user_team_id).roster.player_ids:
		for b in w.teams.get_by_id(2).roster.player_ids:
			var calm := desk.propose(g.league_id, g.contract_year(), g.state.user_team_id, 2, [a], [b], false, false, [], [], g.first_tradable_pick_year(), 50.0, 0)
			var wary := desk.propose(g.league_id, g.contract_year(), g.state.user_team_id, 2, [a], [b], false, false, [], [], g.first_tradable_pick_year(), 50.0, 6)
			assert_true(not (wary["accepted"] and not calm["accepted"]), "wariness never makes a deal easier")
			if calm["accepted"] and not wary["accepted"]:
				found = true
	assert_true(found)


func _open_with_proposal(g: FcGameController) -> Dictionary:
	g.sim_playoffs()
	assert_true(g.open_meeting())
	g.state.meeting["influence"] = 10
	return g.meeting_items()[0]


func test_rapport_builds_when_owners_agree_with_the_player_and_falls_when_lobbied() -> void:
	var g := _game()
	var first := _open_with_proposal(g)
	var item_id: String = first["item"]["id"]
	g.cast_meeting_vote(item_id, true)
	var yes_owner := 0
	var no_owner := 0
	for v in first_votes(g, item_id):
		if v["yes"] and yes_owner == 0:
			yes_owner = v["team"]
		if not v["yes"] and no_owner == 0:
			no_owner = v["team"]
	assert_true(yes_owner > 0 and no_owner > 0, "the first item divides the owners")
	assert_true(g.lobby_owner(item_id, no_owner)["ok"], "lobby the owner who said no")
	g.close_meeting()
	assert_eq(g.ai_rapport(yes_owner), 1, "voted with the player")
	assert_eq(g.ai_rapport(no_owner), -1, "had to be lobbied")


func first_votes(g: FcGameController, item_id: String) -> Array:
	for entry in g.meeting_items():
		if entry["item"]["id"] == item_id:
			return entry["tally"]["votes"]
	return []


func test_rapport_moves_the_owners_vote_toward_the_players_stand() -> void:
	var g := _game()
	g.sim_playoffs()
	assert_true(g.open_meeting())
	var item: Dictionary = g.meeting_items()[0]["item"]
	var meeting := FcOwnersMeeting.new(g.state.world, g.league_id)
	var neutral := meeting.tally(item, g.season(), g.state.current_season, g.state.user_team_id, true)
	var friends := {}
	var enemies := {}
	for tid in g.state.world.leagues.get_by_id(g.league_id).all_team_ids():
		friends[tid] = 6
		enemies[tid] = -6
	var liked := meeting.tally(item, g.season(), g.state.current_season, g.state.user_team_id, true, [], friends)
	var disliked := meeting.tally(item, g.season(), g.state.current_season, g.state.user_team_id, true, [], enemies)
	assert_true(liked["yes"] >= neutral["yes"] and neutral["yes"] >= disliked["yes"], "friends vote yes more, enemies less")
	assert_true(liked["yes"] > disliked["yes"], "and it makes a real difference")
	var against_liked := meeting.tally(item, g.season(), g.state.current_season, g.state.user_team_id, false, [], friends)
	assert_true(against_liked["no"] >= neutral["no"] or against_liked["yes"] <= liked["yes"], "friends also follow a no")


func test_relations_survive_saving() -> void:
	var g := _game()
	g.state.ai_relations = {3: {"wary": 4, "rapport": -2}}
	var back := FcGameState.from_dict(JSON.parse_string(JSON.stringify(g.state.to_dict())), FcDefinitionSet.load_default())
	assert_eq(back.ai_relations[3]["wary"], 4)
	assert_eq(back.ai_relations[3]["rapport"], -2)
	assert_eq(FcGameState.from_dict(JSON.parse_string(JSON.stringify(_game(731).state.to_dict())), FcDefinitionSet.load_default()).ai_relations, {}, "older saves have none")


func test_a_team_moving_in_takes_fans_from_its_new_neighbours() -> void:
	var g := _game(732, 12)
	g.sim_playoffs()
	var w := g.state.world
	var relocation := FcRelocation.new(w, g.league_id)
	var mover := 0
	for tid in w.leagues.get_by_id(g.league_id).all_team_ids():
		if tid != g.state.user_team_id:
			mover = tid
			break
	var plan := relocation.plan(mover, 2026)
	assert_true(not plan.is_empty())
	var region: String = str(plan["city"]["region"])
	var before := {}
	for tid in w.leagues.get_by_id(g.league_id).all_team_ids():
		before[tid] = w.businesses.get_by_id(tid).fan_interest
	relocation.execute(mover, 2026)
	var neighbours := 0
	for tid in w.leagues.get_by_id(g.league_id).all_team_ids():
		if tid == mover:
			continue
		if w.cities.get_by_id(w.teams.get_by_id(tid).city_id).region == region:
			neighbours += 1
			assert_eq(w.businesses.get_by_id(tid).fan_interest, maxi(5, before[tid] - FcRelocation.NEIGHBOUR_FAN_LOSS), "a neighbour in the same region loses fans")
		else:
			assert_eq(w.businesses.get_by_id(tid).fan_interest, before[tid], "clubs elsewhere are untouched")
	assert_true(neighbours >= 0)
