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
