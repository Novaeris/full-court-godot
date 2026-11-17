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
	assert_eq(g.phase(), FcGameController.PHASE_EXPANSION, "the expansion draft is next")
	assert_eq(g.state.world.leagues.get_by_id(g.league_id).team_count(), before, "no new team until the draft is run")
	var status := g.expansion_status()
	assert_eq(status["protected"].size(), FcExpansion.PROTECTED_PER_TEAM, "a default protected list is ready")
	var result := g.run_expansion_draft()
	assert_true(result["teams"].size() > 0)
	assert_eq(g.phase(), FcGameController.PHASE_COMPLETE, "back to the normal offseason")
	assert_true(g.state.world.leagues.get_by_id(g.league_id).team_count() > before)
	assert_eq(g.state.last_expansion_year, 2026)
	assert_eq(g.state.world.rules_of_league(g.league_id).validate(g.state.world.leagues.get_by_id(g.league_id)), [] as Array[String])
	var back := FcGameState.from_dict(JSON.parse_string(JSON.stringify(g.state.to_dict())), FcDefinitionSet.load_default())
	assert_eq(back.last_expansion_year, 2026, "saved")
	assert_eq(back.validate(), [] as Array[String], "and the saved expanded league loads")


func test_the_expansion_draft_takes_unprotected_players_one_per_team() -> void:
	var g := _game(160, 12)
	g.sim_playoffs()
	var w := g.state.world
	var league: FcLeague = w.leagues.get_by_id(g.league_id)
	var existing: Array = league.all_team_ids().duplicate()
	var rosters_before := {}
	for tid in existing:
		rosters_before[tid] = w.teams.get_by_id(tid).roster.player_ids.duplicate()
	var expansion := FcExpansion.new(w, g.league_id)
	var protected_by_default := {}
	for tid in existing:
		protected_by_default[tid] = expansion.default_protected(tid, 2026)
	var result := expansion.execute(2026)
	assert_true(result["picks"].size() > 0)
	var came_from := {}
	for pick in result["picks"]:
		var pid: int = pick[2]
		assert_true(w.teams.get_by_id(pick[1]).roster.contains(pid), "the new team has him")
		assert_true(not pid in protected_by_default[pick[3]], "protected players are never taken")
		assert_true(pid in rosters_before[pick[3]], "he really came from that team")
		assert_true(not came_from.has(pick[3]), "no team loses more than one player")
		came_from[pick[3]] = true
		assert_eq(w.active_contract_of(pid).team_id, pick[1], "his contract moved with him")
		assert_true(w.active_contract_of(pid).end_season() >= 2027, "never a contract that is about to run out")
	for tid in result["teams"]:
		var roster_size: int = w.teams.get_by_id(tid).roster.size()
		assert_true(roster_size >= w.rules_of_league(g.league_id).roster_min, "the draft plus generated players make a legal roster")
	assert_eq(result["picks"].size(), result["teams"].size() * expansion.picks_per_new_team(result["teams"].size(), existing.size()))
	assert_eq(w.validate(2027), [] as Array[String])


func test_the_owner_chooses_whom_to_protect_and_loses_someone_else() -> void:
	var g := _game(161, 12)
	g.sim_playoffs()
	var w := g.state.world
	var user: FcTeam = w.teams.get_by_id(g.state.user_team_id)
	g.state.offseason_stage = 4
	g.state.expansion = {"year": 2026, "protected": []}
	var too_many: Array = []
	for pid in user.roster.player_ids:
		too_many.append(pid)
	assert_true(not g.set_protected_players(too_many)["ok"], "at most the limit")
	assert_true(not g.set_protected_players([999999])["ok"], "only your own players")
	# protect the weakest eight: the stars become the likely picks
	var ratings := FcPlayerRatings.load_default()
	var sorted: Array = user.roster.player_ids.duplicate()
	sorted.sort_custom(func(a, b): return ratings.overall(w.players.get_by_id(a)) < ratings.overall(w.players.get_by_id(b)))
	var weakest: Array = sorted.slice(0, FcExpansion.PROTECTED_PER_TEAM)
	assert_true(g.set_protected_players(weakest)["ok"])
	var result := g.run_expansion_draft()
	for entry in result["lost"]:
		assert_true(not entry[0] in weakest, "a protected player was never taken")
	assert_true(result["lost"].size() <= 1, "at most one player lost")
	assert_eq(g.state.expansion_log.size(), result["picks"].size())
	if not result["lost"].is_empty():
		assert_true(w.news.any(func(n): return "expansion draft" in n["text"] and n["team"] == user.id), "the owner is told")


func test_skipping_the_protection_screen_uses_the_default_and_never_blocks() -> void:
	var g := _game(162, 12)
	g.sim_playoffs()
	g.state.offseason_stage = 4
	g.state.expansion = {"year": 2026, "protected": FcExpansion.new(g.state.world, g.league_id).default_protected(g.state.user_team_id, 2026)}
	var report := g.start_next_season()
	assert_eq(g.state.current_season, 2027)
	assert_eq(g.state.offseason_stage, 0)
	assert_true(g.state.world.leagues.get_by_id(g.league_id).team_count() > 12)
	assert_eq(g.state.validate(), [] as Array[String])
	assert_true(report.has("signed"))


func test_the_pending_expansion_draft_survives_saving() -> void:
	var g := _game(163, 12)
	g.sim_playoffs()
	g.state.offseason_stage = 4
	var mine: Array = g.state.world.teams.get_by_id(g.state.user_team_id).roster.player_ids.slice(0, 3)
	g.state.expansion = {"year": 2026, "protected": mine}
	var back := FcGameState.from_dict(JSON.parse_string(JSON.stringify(g.state.to_dict())), FcDefinitionSet.load_default())
	assert_eq(back.offseason_stage, 4)
	assert_eq(back.expansion["protected"], mine)
	var again := FcGameController.resume(back)
	assert_eq(again.phase(), FcGameController.PHASE_EXPANSION)
	assert_eq(again.expansion_status()["protected"], mine)
	g.state.expansion_log = [[2026, 1, 5, 9, 2]]
	var back2 := FcGameState.from_dict(JSON.parse_string(JSON.stringify(g.state.to_dict())), FcDefinitionSet.load_default())
	assert_eq(back2.expansion_log, [[2026, 1, 5, 9, 2]])
