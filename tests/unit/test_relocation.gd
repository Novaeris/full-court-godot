extends FcTestCase
## A franchise moving to another city, decided at the owners' meeting.

func _game(seed_value: int = 170, teams: int = 12) -> FcGameController:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = teams
	cfg.conference_count = 2
	cfg.divisions_per_conference = 3 if teams == 12 else 2
	cfg.roster_size = 13
	cfg.free_agent_count = 10
	return FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), seed_value, FcGameState.MODE_OWNER, 0)


func _other_team(g: FcGameController) -> int:
	for tid in g.state.world.leagues.get_by_id(g.league_id).all_team_ids():
		if tid != g.state.user_team_id:
			return tid
	return 0


func test_the_plan_picks_a_bigger_unused_city_and_is_stable() -> void:
	var g := _game()
	var w := g.state.world
	var relocation := FcRelocation.new(w, g.league_id)
	var tid := 0
	var smallest := INF
	for t in w.teams.all():
		var pop: int = w.cities.get_by_id(t.city_id).population
		if pop < smallest:
			smallest = pop
			tid = t.id
	var plan := relocation.plan(tid, 2026)
	assert_true(not plan.is_empty(), "the smallest market can move somewhere bigger")
	assert_true(int(plan["city"]["population"]) > w.cities.get_by_id(w.teams.get_by_id(tid).city_id).population)
	var used := {}
	for t in w.teams.all():
		used[w.cities.get_by_id(t.city_id).name] = true
	assert_true(not used.has(str(plan["city"]["name"])), "an unused city")
	assert_eq(plan, relocation.plan(tid, 2026), "the same plan every time")


func test_moving_changes_the_city_the_arena_and_the_fan_base() -> void:
	var g := _game()
	g.sim_playoffs()
	var w := g.state.world
	var tid := _other_team(g)
	var team: FcTeam = w.teams.get_by_id(tid)
	var business: FcTeamBusiness = w.businesses.get_by_id(tid)
	business.valuation = 600000000
	var old_city: String = w.cities.get_by_id(team.city_id).name
	var old_arena := team.arena_id
	var interest := business.fan_interest
	var brand := business.brand
	business.projects = [{"key": "expand_seating", "seasons_left": 1}]
	var cash_before: Dictionary = {}
	for other in w.leagues.get_by_id(g.league_id).all_team_ids():
		cash_before[other] = w.businesses.get_by_id(other).cash
	var relocation := FcRelocation.new(w, g.league_id)
	var fees := relocation.fee_for(tid)
	var roster_before: Array = team.roster.player_ids.duplicate()
	var result := relocation.execute(tid, 2026)
	assert_true(not result.is_empty())
	assert_eq(result["from"], old_city)
	assert_true(w.cities.get_by_id(team.city_id).name != old_city and w.cities.get_by_id(team.city_id).name == result["to"])
	assert_true(team.arena_id != old_arena and w.arenas.get_by_id(team.arena_id).city_id == team.city_id, "a new arena in the new city")
	assert_eq(business.facilities_level, FcRelocation.NEW_ARENA_QUALITY)
	assert_true(business.brand < brand and business.projects.is_empty(), "less brand, and the old arena's projects are gone")
	assert_true(business.fan_interest != interest or interest < 10)
	assert_eq(team.roster.player_ids, roster_before, "the players move with the team")
	assert_eq(w.businesses.get_by_id(tid).cash, maxi(0, cash_before[tid] - fees["fee"]), "the team paid the fee (a shortfall becomes debt)")
	for other in cash_before:
		if other != tid:
			assert_eq(w.businesses.get_by_id(other).cash, cash_before[other] + fees["each"], "the other owners share it")
	assert_eq(w.rules_of_league(g.league_id).validate(w.leagues.get_by_id(g.league_id)), [] as Array[String])
	assert_eq(w.validate(2027), [] as Array[String])
	assert_true(w.news.any(func(n): return "move from" in n["text"]))
	var seen := 0
	for conference in w.leagues.get_by_id(g.league_id).conferences:
		for division in conference.divisions:
			if tid in division.team_ids:
				seen += 1
	assert_eq(seen, 1, "the team is in one division after the redraw")


func test_a_team_does_not_move_twice_within_the_gap() -> void:
	var g := _game()
	var relocation := FcRelocation.new(g.state.world, g.league_id)
	var tid := _other_team(g)
	var log := [[2026, tid, "A", "B"]]
	assert_true(not relocation.allowed(tid, 2030, log), "too soon")
	assert_true(relocation.allowed(tid, 2026 + FcRelocation.MIN_GAP_YEARS, log) or relocation.plan(tid, 2036).is_empty(), "allowed again after the gap (if a bigger city exists)")


func test_struggling_ai_teams_are_found_and_the_player_team_never_is() -> void:
	var g := _game()
	g.sim_playoffs()
	var w := g.state.world
	var relocation := FcRelocation.new(w, g.league_id)
	var finance := FcFinanceEngine.new(w)
	var worst := 0
	var worst_profit := INF
	for tid in w.leagues.get_by_id(g.league_id).all_team_ids():
		var rec := finance.record_of(tid, 2026)
		if tid != g.state.user_team_id and rec.profit() < worst_profit:
			worst_profit = rec.profit()
			worst = tid
	w.businesses.get_by_id(worst).fan_interest = 20
	finance.record_of(worst, 2026).revenue["tickets"] = 0   # a bad year: it lost money
	assert_eq(relocation.struggling_team(2026, g.state.user_team_id, []), worst)
	assert_eq(relocation.struggling_team(2026, worst, []) != worst, true, "the team named as the user's is never chosen")
	assert_eq(relocation.struggling_team(2026, g.state.user_team_id, [[2026, worst, "A", "B"]]) != worst, true, "not right after a move")


func test_the_owner_can_propose_moving_their_own_team_and_the_vote_decides() -> void:
	var g := _game(171)
	g.sim_playoffs()
	assert_true(g.open_meeting())
	var options := g.proposable_items()
	var own := {}
	for p in options:
		if p["id"] == "relocate:%d" % g.state.user_team_id:
			own = p
	assert_true(not own.is_empty(), "the owner can propose a move for their own team")
	assert_true(own["title"].begins_with("Approve the move of the") and "two thirds" in own["detail"])
	g.state.meeting["influence"] = 10
	assert_true(g.propose_item(own["id"])["ok"])
	g.cast_meeting_vote(own["id"], true)
	# the player lobbies every owner who leans against it
	for entry in g.meeting_items():
		if entry["item"]["id"] == own["id"]:
			for v in entry["tally"]["votes"]:
				if not v["yes"]:
					g.state.meeting["lobbied"][own["id"]] = g.state.meeting["lobbied"].get(own["id"], []) + [v["team"]]
	var old_city: String = g.state.world.cities.get_by_id(g.state.world.teams.get_by_id(g.state.user_team_id).city_id).name
	var results := g.close_meeting()
	assert_true(results.any(func(r): return r["title"].begins_with("Approve the move") and r["enacted"]), "with everyone in favour it passes")
	var new_city: String = g.state.world.cities.get_by_id(g.state.world.teams.get_by_id(g.state.user_team_id).city_id).name
	assert_true(new_city != old_city)
	assert_eq(g.state.relocation_log, [[2026, g.state.user_team_id, old_city, new_city]])
	assert_eq(g.state.validate(), [] as Array[String])
	g.begin_offseason()
	g.draft_auto_rest()
	g.start_next_season()
	g.sim_playoffs()
	assert_eq(g.state.validate(), [] as Array[String], "the moved team plays a full season")
	assert_true(g.business().cash >= 0)


func test_the_moving_team_votes_yes_and_neighbours_vote_no() -> void:
	var g := _game(172)
	g.sim_playoffs()
	var w := g.state.world
	var meeting := FcOwnersMeeting.new(w, g.league_id)
	var mover := _other_team(g)
	var item := meeting.relocation_item(mover, 2026)
	if item.is_empty():
		assert_true(true, "this league has no bigger unused city for that team")
		return
	var situations := meeting.situations(g.season())
	assert_eq(meeting.vote_of(mover, item, situations[mover], 2026)["yes"], true, "the moving team wants it")
	var neighbour := 0
	for tid in w.leagues.get_by_id(g.league_id).all_team_ids():
		if tid != mover and w.cities.get_by_id(w.teams.get_by_id(tid).city_id).region == item["region"]:
			neighbour = tid
	if neighbour > 0:
		var no_votes := 0
		for year in range(2026, 2046):
			if not meeting.vote_of(neighbour, item, situations[neighbour], year)["yes"]:
				no_votes += 1
		assert_true(no_votes >= 12, "a team in the same region mostly votes no (%d of 20)" % no_votes)


func test_the_relocation_log_and_item_survive_saving() -> void:
	var g := _game(173)
	g.sim_playoffs()
	g.state.relocation_log = [[2026, 5, "Old Town", "New City"]]
	var meeting := FcOwnersMeeting.new(g.state.world, g.league_id)
	var item := meeting.relocation_item(_other_team(g), 2026)
	if not item.is_empty():
		g.state.offseason_stage = 3
		g.state.meeting = {"year": 2026, "items": [item], "votes": {}, "lobbied": {}, "influence": 4, "proposed": false}
	var back := FcGameState.from_dict(JSON.parse_string(JSON.stringify(g.state.to_dict())), FcDefinitionSet.load_default())
	assert_eq(back.relocation_log, [[2026, 5, "Old Town", "New City"]])
	if not item.is_empty():
		assert_eq(back.meeting["items"][0]["mover"], item["mover"])
		assert_eq(back.meeting["items"][0]["region"], item["region"])
