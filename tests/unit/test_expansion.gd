extends FcTestCase
## League expansion decided at the owners' meeting.

func _game(seed_value: int = 150, teams: int = 12) -> FcGameController:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = teams
	cfg.conference_count = 2
	cfg.divisions_per_conference = 3 if teams == 12 else 2
	cfg.roster_size = 13
	cfg.free_agent_count = 10
	if teams > 40:
		cfg.areas = [] as Array[String]   # every area, so there are enough cities
	return FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), seed_value, FcGameState.MODE_OWNER, 0)


func test_the_plan_names_a_valid_size_and_unused_cities() -> void:
	var g := _game()
	var w := g.state.world
	var plan := FcExpansion.new(w, g.league_id).plan(2026)
	assert_true(not plan.is_empty())
	assert_true(plan["size"] >= 14 and plan["size"] <= FcLeagueStructure.MAX_TEAMS_IN_SAVE)
	assert_true(not FcLeagueStructure.valid_structures(plan["size"]).is_empty(), "the new size can be split into equal divisions")
	assert_eq(plan["delta"], plan["cities"].size())
	var used := {}
	for c in w.cities.all():
		used[c.name] = true
	for entry in plan["cities"]:
		assert_true(not used.has(str(entry["name"])), "%s is a new city" % entry["name"])
	assert_eq(plan, FcExpansion.new(w, g.league_id).plan(2026), "the same plan every time")


func test_expanding_adds_complete_teams_and_a_valid_league() -> void:
	var g := _game()
	g.sim_playoffs()
	var w := g.state.world
	var league: FcLeague = w.leagues.get_by_id(g.league_id)
	var before_teams := league.team_count()
	var cash_before: Dictionary = {}
	for tid in league.all_team_ids():
		cash_before[tid] = w.businesses.get_by_id(tid).cash
	var result := FcExpansion.new(w, g.league_id).execute(2026)
	assert_true(not result.is_empty())
	assert_eq(league.team_count(), result["size"])
	assert_eq(league.team_count(), before_teams + result["teams"].size())
	var rules := w.rules_of_league(g.league_id)
	assert_eq(rules.validate(league), [] as Array[String], "the rules fit the new league")
	assert_eq(w.validate(2027), [] as Array[String], "the world is consistent")
	for tid in result["teams"]:
		var team: FcTeam = w.teams.get_by_id(tid)
		assert_true(team.roster.size() >= rules.roster_min and team.roster.size() <= rules.roster_max, "a legal roster")
		assert_true(w.businesses.get_by_id(tid) != null, "a business")
		assert_true(w.staff_in_role(tid, FcStaffRole.Id.GENERAL_MANAGER) != null and w.staff_in_role(tid, FcStaffRole.Id.HEAD_COACH) != null, "a front office")
		for pid in team.roster.player_ids:
			var c := w.active_contract_of(pid)
			assert_true(c != null and c.is_in_force_in(2027), "contracts cover the new season")
	for tid in cash_before:
		assert_eq(w.businesses.get_by_id(tid).cash, cash_before[tid] + result["fee_each"], "every existing owner receives the fee")
	assert_true(result["fee_each"] > 0)
	assert_true(w.news.any(func(n): return "expands to" in n["text"]))
	for team_id in league.all_team_ids():
		var seen := 0
		for conference in league.conferences:
			for division in conference.divisions:
				if team_id in division.team_ids:
					seen += 1
		assert_eq(seen, 1, "every team is in exactly one division")


func test_the_expanded_league_plays_a_season_and_an_offseason() -> void:
	var g := _game(151)
	g.sim_playoffs()
	assert_true(not FcExpansion.new(g.state.world, g.league_id).execute(2026).is_empty())
	g.begin_offseason()
	g.draft_auto_rest()
	var size: int = g.state.world.leagues.get_by_id(g.league_id).team_count()
	assert_eq(g.season().draft.size(), size * FcOffseason.DRAFT_ROUNDS, "the new teams take part in the draft")
	g.start_next_season()
	assert_eq(g.state.current_season, 2027)
	g.sim_playoffs()
	assert_eq(g.state.validate(), [] as Array[String])
	assert_eq(g.standings().records.size(), size, "every team plays")
	assert_eq(g.league_finances().size(), size, "the books show every team after the new season")


func test_expansion_never_goes_past_64_teams_or_without_cities() -> void:
	var g := _game(152, 60)
	var w := g.state.world
	var plan := FcExpansion.new(w, g.league_id).plan(2026)
	assert_true(plan.is_empty() or plan["size"] <= 64)
	assert_eq(FcLeagueStructure.MAX_TEAMS_IN_SAVE, 64)
	var small := _game(153)
	var plan_small := FcExpansion.new(small.state.world, small.league_id).plan(2026)
	assert_true(plan_small["size"] <= 64)


func test_expansion_is_a_meeting_item_with_a_three_quarter_vote_and_a_gap() -> void:
	var g := _game(154)
	g.sim_playoffs()
	var meeting := FcOwnersMeeting.new(g.state.world, g.league_id)
	var proposals := meeting.proposable(2026, [], 0)
	var expansion := {}
	for p in proposals:
		if p["id"] == "expansion":
			expansion = p
	assert_true(not expansion.is_empty(), "the owner can propose an expansion")
	assert_true("three quarters" in expansion["detail"])
	assert_eq(meeting.tally(expansion, g.season(), 2026, g.state.user_team_id, null)["needed"], 9, "three quarters of 12")
	var recent := meeting.proposable(2027, [], 2026)
	assert_true(not recent.any(func(p): return p["id"] == "expansion"), "not again so soon after one")
	assert_true(meeting.proposable(2029, [], 2026).any(func(p): return p["id"] == "expansion"), "after the gap it can come back")


func test_a_passed_expansion_is_enacted_by_the_meeting_and_remembered() -> void:
	var g := _game(155)
	g.sim_playoffs()
	assert_true(g.open_meeting())
	g.state.meeting["influence"] = 10
	var options := g.proposable_items()
	assert_true(options.any(func(p): return p["id"] == "expansion"))
	assert_true(g.propose_item("expansion")["ok"])
	var before: int = g.state.world.leagues.get_by_id(g.league_id).team_count()
	# make it pass: the player and every owner vote yes
	g.cast_meeting_vote("expansion", true)
	for entry in g.meeting_items():
		if entry["item"]["id"] == "expansion":
			for v in entry["tally"]["votes"]:
				if not v["yes"] and not v["flipped"]:
					g.state.meeting["lobbied"]["expansion"] = g.state.meeting["lobbied"].get("expansion", []) + [v["team"]]
	var results := g.close_meeting()
	var expanded := results.any(func(r): return r["title"].begins_with("Expand") and r["enacted"])
	assert_true(expanded, "with every owner in favour the expansion passes")
	assert_true(g.state.world.leagues.get_by_id(g.league_id).team_count() > before)
	assert_eq(g.state.last_expansion_year, 2026)
	assert_eq(g.state.world.rules_of_league(g.league_id).validate(g.state.world.leagues.get_by_id(g.league_id)), [] as Array[String])
	var back := FcGameState.from_dict(JSON.parse_string(JSON.stringify(g.state.to_dict())), FcDefinitionSet.load_default())
	assert_eq(back.last_expansion_year, 2026, "saved")
	assert_eq(back.validate(), [] as Array[String], "and the saved expanded league loads")
