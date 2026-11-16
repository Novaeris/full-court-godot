extends FcTestCase
## The human owner signing free agents.

var g: FcGameController


func before_each() -> void:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.roster_min = 12
	cfg.free_agent_count = 15
	g = FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), 44, FcGameState.MODE_OWNER, 0)


func test_market_lists_free_agents_best_first() -> void:
	var m := g.free_agent_market(10)
	assert_eq(m.size(), 10)
	for i in range(1, m.size()):
		assert_true(m[i - 1]["value"] >= m[i]["value"])
	assert_true(g.state.world.team_of_player(m[0]["player"].id) == null)


func test_signing_adds_player_and_contract() -> void:
	var w := g.state.world
	var team: FcTeam = w.teams.get_by_id(g.state.user_team_id)
	# the weakest free agent asks about the minimum, which is always signable
	var m := g.free_agent_market(100)
	var target: FcPlayer = m[m.size() - 1]["player"]
	var size := team.roster.size()
	var r := g.sign_free_agent(target.id)
	assert_true(r["signed"], r["reason"])
	assert_eq(team.roster.size(), size + 1)
	assert_eq(w.active_contract_of(target.id).team_id, team.id)
	assert_eq(w.validate(g.state.current_season), [] as Array[String])
	assert_true(not g.sign_free_agent(target.id)["signed"], "cannot sign him twice")


func test_full_roster_blocks_signing() -> void:
	var w := g.state.world
	var team: FcTeam = w.teams.get_by_id(g.state.user_team_id)
	var rules := w.rules_of_league(g.league_id)
	var target: FcPlayer = g.free_agent_market(5)[0]["player"]
	var spare := g.free_agent_market(30)
	var i := 1
	while team.roster.size() < rules.roster_max and i < spare.size():
		var q: FcPlayer = spare[i]["player"]
		team.roster.add(q.id)
		i += 1
	var r := g.sign_free_agent(target.id)
	assert_true(not r["signed"] and "roster" in r["reason"].to_lower(), r["reason"])


func test_mid_level_exception_only_once_a_season() -> void:
	var w := g.state.world
	g.business().mid_level_used_season = g.state.current_season
	var rules := w.rules_of_league(g.league_id)
	# put the team far over the cap so only exceptions could work
	var team: FcTeam = w.teams.get_by_id(g.state.user_team_id)
	for c in w.contracts.all():
		if c.team_id == team.id and c.status == FcContract.Status.ACTIVE:
			for y in c.years:
				y.salary = int(rules.cap.salary_cap * 0.16)
	var star: FcPlayer = g.free_agent_market(1)[0]["player"]
	var r := g.sign_free_agent(star.id)
	assert_true(not r["signed"], r["reason"])


func test_business_saves_mid_level_flag() -> void:
	var b := FcTeamBusiness.new(3)
	b.mid_level_used_season = 2027
	assert_eq(FcTeamBusiness.from_dict(b.to_dict()).mid_level_used_season, 2027)
	var old := b.to_dict()
	old.erase("mid_level_used_season")
	assert_eq(FcTeamBusiness.from_dict(old).mid_level_used_season, 0)


func test_release_pays_a_buyout_and_frees_a_roster_spot() -> void:
	var w := g.state.world
	var team: FcTeam = w.teams.get_by_id(g.state.user_team_id)
	var pid: int = team.roster.player_ids[0]
	var salary := w.active_contract_of(pid).salary_for(g.state.current_season)
	var cash := g.business().cash
	var debt := g.business().debt
	var size := team.roster.size()
	var r := g.release_player(pid)
	assert_true(r["released"], r["reason"])
	assert_eq(team.roster.size(), size - 1)
	assert_true(w.active_contract_of(pid) == null)
	assert_eq((cash - g.business().cash) + (g.business().debt - debt), salary / 2)
	assert_true(w.team_of_player(pid) == null, "he is a free agent now")
	assert_true(not g.release_player(pid)["released"], "cannot release him twice")
	assert_eq(w.validate(g.state.current_season), [] as Array[String])
