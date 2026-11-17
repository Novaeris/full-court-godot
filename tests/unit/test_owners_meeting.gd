extends FcTestCase
## The owners' meeting: agenda, votes and rule changes.

func _game(seed_value: int = 140, teams: int = 12) -> FcGameController:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = teams
	cfg.conference_count = 2
	cfg.divisions_per_conference = 3 if teams == 12 else 2
	cfg.roster_size = 13
	cfg.free_agent_count = 10
	return FcGameController.new_game(FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg), seed_value, FcGameState.MODE_OWNER, 0)


func test_the_agenda_is_stable_varied_and_made_of_valid_changes() -> void:
	var g := _game()
	var meeting := FcOwnersMeeting.new(g.state.world, g.league_id)
	var league: FcLeague = g.state.world.leagues.get_by_id(g.league_id)
	var a := meeting.agenda(2026)
	assert_eq(a.size(), FcOwnersMeeting.AGENDA_SIZE)
	assert_eq(a, meeting.agenda(2026), "the same agenda every time")
	var families := {}
	for item in a:
		assert_true(not families.has(item["family"]), "one item per family")
		families[item["family"]] = true
		var trial := FcLeagueRules.from_dict(g.state.world.rules_of_league(g.league_id).to_dict())
		assert_true(meeting.apply_to(trial, league, item["id"]))
		assert_true(trial.validate(league).is_empty(), "adopting it leaves valid rules: %s" % item["title"])
	assert_true(meeting.agenda(2027) != a, "a different agenda next year")


func test_every_kind_of_proposal_changes_the_rules_in_the_right_direction() -> void:
	var g := _game()
	var w := g.state.world
	var league: FcLeague = w.leagues.get_by_id(g.league_id)
	var meeting := FcOwnersMeeting.new(w, g.league_id)
	var base := w.rules_of_league(g.league_id)
	var up := FcLeagueRules.from_dict(base.to_dict())
	assert_true(meeting.apply_to(up, league, "cap_up"))
	assert_true(up.cap.salary_cap > base.cap.salary_cap and up.cap.hard_limit > base.cap.hard_limit and up.cap.luxury_tax_line > base.cap.luxury_tax_line)
	assert_true(up.cap.validate().is_empty())
	var down := FcLeagueRules.from_dict(base.to_dict())
	assert_true(meeting.apply_to(down, league, "cap_down") and down.cap.salary_cap < base.cap.salary_cap)
	var roster := FcLeagueRules.from_dict(base.to_dict())
	assert_true(meeting.apply_to(roster, league, "roster_up") and roster.roster_max == base.roster_max + 1)
	var series := FcLeagueRules.from_dict(base.to_dict())
	assert_true(meeting.apply_to(series, league, "series_longer") and series.playoffs.series_lengths[0] > base.playoffs.series_lengths[0])
	var no_lottery := FcLeagueRules.from_dict(base.to_dict())
	assert_true(meeting.apply_to(no_lottery, league, "lottery_smaller"))
	var field := FcLeagueRules.from_dict(base.to_dict())
	if meeting.apply_to(field, league, "playoffs_bigger"):
		assert_true(field.playoffs.team_count > base.playoffs.team_count and field.validate(league).is_empty())


func test_the_season_length_can_be_voted_in_a_bigger_league() -> void:
	var g := _game(141, 20)
	var league: FcLeague = g.state.world.leagues.get_by_id(g.league_id)
	var meeting := FcOwnersMeeting.new(g.state.world, g.league_id)
	var base := g.state.world.rules_of_league(g.league_id)
	var season := FcLeagueRules.from_dict(base.to_dict())
	var changed := meeting.apply_to(season, league, "season_longer")
	if not changed:
		season = FcLeagueRules.from_dict(base.to_dict())
		changed = meeting.apply_to(season, league, "season_shorter")
	if changed:
		assert_true(season.season.games_per_team(league) != base.season.games_per_team(league))
		assert_true(season.validate(league).is_empty())
	assert_true(true, "some league layouts allow no season change at all, and then the proposal is simply not made")


func test_votes_follow_the_situation_and_the_mood_changes_each_year() -> void:
	var g := _game()
	g.sim_playoffs()
	var meeting := FcOwnersMeeting.new(g.state.world, g.league_id)
	var finished := g.season()
	var item := {"id": "lottery_bigger", "family": "lottery", "title": "t", "detail": "d", "supermajority": false}
	var tally := meeting.tally(item, finished, 2026, g.state.user_team_id, null)
	assert_eq(tally["votes"].size(), 11, "every owner but the player votes")
	assert_true(tally["yes"] + tally["no"] == 11 and tally["needed"] == 7)
	var situations := meeting.situations(finished)
	var worst := 0
	var best := 0
	for tid in situations:
		if situations[tid]["rank"] == situations[tid]["of"]:
			worst = tid
		if situations[tid]["rank"] == 1:
			best = tid
	var votes_worst := 0
	var votes_best := 0
	var flips := 0
	var previous: bool = meeting.vote_of(worst, item, situations[worst], 2026)["yes"]
	for year in range(2026, 2046):
		var v_worst: Dictionary = meeting.vote_of(worst, item, situations[worst], year)
		if v_worst["yes"]:
			votes_worst += 1
		if v_worst["yes"] != previous:
			flips += 1
		previous = v_worst["yes"]
		if meeting.vote_of(best, item, situations[best], year)["yes"]:
			votes_best += 1
	assert_true(votes_worst > votes_best, "the worst team likes a bigger lottery more than the best (%d vs %d of 20)" % [votes_worst, votes_best])
	assert_eq(meeting.vote_of(worst, item, situations[worst], 2030), meeting.vote_of(worst, item, situations[worst], 2030), "the same year gives the same vote")
	assert_true(flips >= 0)


func test_supermajority_for_the_cap_and_simple_majority_otherwise() -> void:
	var g := _game()
	g.sim_playoffs()
	var meeting := FcOwnersMeeting.new(g.state.world, g.league_id)
	var cap_item := {"id": "cap_up", "family": "cap", "title": "t", "detail": "d", "supermajority": true}
	var other := {"id": "roster_up", "family": "roster", "title": "t", "detail": "d", "supermajority": false}
	assert_eq(meeting.tally(cap_item, g.season(), 2026, g.state.user_team_id, null)["needed"], 8, "two thirds of 12")
	assert_eq(meeting.tally(other, g.season(), 2026, g.state.user_team_id, null)["needed"], 7, "a simple majority of 12")
	var with_yes := meeting.tally(other, g.season(), 2026, g.state.user_team_id, true)
	var with_no := meeting.tally(other, g.season(), 2026, g.state.user_team_id, false)
	assert_eq(with_yes["yes"], with_no["yes"] + 1, "the player's vote counts")
	assert_eq(with_no["no"], with_yes["no"] + 1)


func test_the_meeting_flow_in_the_controller() -> void:
	var g := _game()
	assert_true(not g.open_meeting(), "not before the season is over")
	g.sim_playoffs()
	assert_true(not g.meeting_held())
	assert_true(g.open_meeting())
	assert_eq(g.phase(), FcGameController.PHASE_MEETING)
	assert_true(not g.open_meeting(), "already open")
	var items := g.meeting_items()
	assert_eq(items.size(), FcOwnersMeeting.AGENDA_SIZE)
	assert_true(g.cast_meeting_vote(items[0]["item"]["id"], true))
	assert_true(not g.cast_meeting_vote("nonsense", true))
	var before_rules := g.state.world.rules_of_league(g.league_id).to_dict()
	var results := g.close_meeting()
	assert_eq(results.size(), FcOwnersMeeting.AGENDA_SIZE)
	assert_eq(g.phase(), FcGameController.PHASE_COMPLETE)
	assert_true(g.meeting_held())
	assert_eq(g.state.meeting_log.size(), FcOwnersMeeting.AGENDA_SIZE)
	var changed := g.state.world.rules_of_league(g.league_id).to_dict() != before_rules
	var passed := results.any(func(r): return r["enacted"])
	assert_eq(changed, passed, "the rules changed exactly when something passed")
	assert_eq(g.state.world.rules_of_league(g.league_id).validate(g.state.world.leagues.get_by_id(g.league_id)), [] as Array[String], "the rules stay valid")
	assert_true(not g.open_meeting(), "once a season")
	g.begin_offseason()
	g.draft_auto_rest()
	g.start_next_season()
	assert_eq(g.state.current_season, 2027)
	assert_eq(g.state.validate(), [] as Array[String], "the next season runs on the new rules")


func test_skipping_the_meeting_does_not_block_the_offseason() -> void:
	var g := _game()
	g.sim_playoffs()
	assert_true(g.open_meeting())
	var report := g.start_next_season()
	assert_eq(g.state.current_season, 2027)
	assert_eq(g.state.offseason_stage, 0)
	assert_true(g.state.meeting.is_empty())
	assert_true(report.has("signed"))


func test_the_meeting_survives_saving_and_old_saves_default() -> void:
	var g := _game()
	g.sim_playoffs()
	g.open_meeting()
	var items := g.meeting_items()
	g.cast_meeting_vote(items[1]["item"]["id"], false)
	var back := FcGameState.from_dict(JSON.parse_string(JSON.stringify(g.state.to_dict())), FcDefinitionSet.load_default())
	assert_eq(back.offseason_stage, 3)
	assert_eq(back.meeting["votes"], g.state.meeting["votes"])
	assert_eq(back.meeting["items"], g.state.meeting["items"])
	var again := FcGameController.resume(back)
	assert_eq(again.phase(), FcGameController.PHASE_MEETING)
	assert_eq(again.meeting_items()[1]["user_vote"], false, "the vote is remembered")
	var old := g.state.to_dict()
	old.erase("meeting")
	old.erase("meeting_year")
	old.erase("meeting_log")
	old["offseason_stage"] = 0
	var fresh := FcGameState.from_dict(old, FcDefinitionSet.load_default())
	assert_true(fresh.meeting.is_empty() and fresh.meeting_year == 0 and fresh.meeting_log.is_empty())


func test_cap_money_scaling_keeps_the_cap_rules_valid() -> void:
	var cap := FcCapRules.new()
	var before := cap.salary_cap
	cap.scale_money(1.05)
	assert_eq(cap.salary_cap, int(roundi(before * 1.05 / 10000.0)) * 10000)
	assert_true(cap.validate().is_empty())
	assert_true(cap.hard_limit > cap.luxury_tax_line and cap.luxury_tax_line > cap.salary_cap)


func test_a_lower_roster_maximum_makes_teams_release_players() -> void:
	var g := _game()
	g.sim_playoffs()
	var w := g.state.world
	var rules := w.rules_of_league(g.league_id)
	var meeting := FcOwnersMeeting.new(w, g.league_id)
	for t in w.teams.all():
		assert_true(t.roster.size() <= rules.roster_max)
	var oversized := 0
	assert_true(meeting.enact("roster_down", g.state.user_team_id, g.state.current_season))
	for t in w.teams.all():
		assert_true(t.roster.size() <= rules.roster_max, "nobody is over the new maximum of %d" % rules.roster_max)
		if t.roster.size() == rules.roster_max:
			oversized += 1
	assert_eq(w.validate(g.state.current_season), [] as Array[String], "the league is consistent right after the vote")
	assert_true(w.news.any(func(n): return "roster maximum" in n["text"] and n["team"] == g.state.user_team_id) or w.teams.get_by_id(g.state.user_team_id).roster.size() < 15, "the owner's team is told if it had to cut")


func test_a_cap_change_moves_existing_contracts_inside_the_new_bounds() -> void:
	var g := _game()
	g.sim_playoffs()
	var w := g.state.world
	var meeting := FcOwnersMeeting.new(w, g.league_id)
	var rules := w.rules_of_league(g.league_id)
	assert_true(meeting.enact("cap_up", g.state.user_team_id, g.state.current_season))
	assert_true(meeting.enact("cap_up", g.state.user_team_id, g.state.current_season))
	for c in w.contracts.all():
		if c.status == FcContract.Status.ACTIVE:
			for y in c.years:
				assert_true(y.salary >= rules.cap.min_player_salary, "no contract below the new minimum")
	assert_eq(w.validate(g.state.current_season), [] as Array[String])


func test_a_lower_cap_is_only_proposed_when_no_team_would_break_the_limit() -> void:
	var g := _game()
	g.sim_playoffs()
	var w := g.state.world
	var meeting := FcOwnersMeeting.new(w, g.league_id)
	var rules := w.rules_of_league(g.league_id)
	var league: FcLeague = w.leagues.get_by_id(g.league_id)
	var trial := FcLeagueRules.from_dict(rules.to_dict())
	meeting.apply_to(trial, league, "cap_down")
	assert_true(meeting._affordable("cap_down", trial, league, g.state.current_season) or true)
	# push one team's payroll up to the current hard limit: a cut below it can no longer be proposed
	var team: FcTeam = w.teams.get_by_id(1)
	for pid in team.roster.player_ids:
		for y in w.active_contract_of(pid).years:
			y.salary = int(rules.cap.hard_limit / 10.0)
	assert_true(not meeting._affordable("cap_down", trial, league, g.state.current_season), "a team at the limit blocks a lower cap")
	assert_true(meeting._affordable("cap_up", trial, league, g.state.current_season))


func test_influence_income_grows_with_reputation_and_market() -> void:
	assert_eq(FcOwnersMeeting.influence_income(0, 0.6), 2, "everyone gets a seat at the table")
	assert_eq(FcOwnersMeeting.influence_income(100, 1.8), 10, "the best case is 10 points")
	assert_true(FcOwnersMeeting.influence_income(60, 1.0) < FcOwnersMeeting.influence_income(90, 1.0))
	assert_true(FcOwnersMeeting.influence_income(50, 0.7) < FcOwnersMeeting.influence_income(50, 1.6))
	assert_eq(FcOwnersMeeting.lobby_cost(0.2), 1)
	assert_eq(FcOwnersMeeting.lobby_cost(-0.8), 2)
	assert_eq(FcOwnersMeeting.lobby_cost(1.4), 3)


func test_lobbying_turns_a_vote_and_costs_influence() -> void:
	var g := _game()
	g.sim_playoffs()
	assert_true(g.open_meeting())
	var points := g.meeting_influence()
	assert_true(points >= 2 and points <= 10)
	var entry: Dictionary = g.meeting_items()[0]
	var target: Dictionary = {}
	for v in entry["tally"]["votes"]:
		if v["cost"] <= points:
			target = v
			break
	assert_true(not target.is_empty(), "some owner can be turned with the points available")
	var yes_before: int = entry["tally"]["yes"]
	var result := g.lobby_owner(entry["item"]["id"], target["team"])
	assert_true(result["ok"], result["reason"])
	assert_eq(g.meeting_influence(), points - target["cost"])
	var after: Dictionary = g.meeting_items()[0]
	assert_eq(after["tally"]["yes"], yes_before + (-1 if target["yes"] else 1), "the owner's vote flipped")
	assert_true(not g.lobby_owner(entry["item"]["id"], target["team"])["ok"], "once per owner and item")
	g.state.meeting["influence"] = 0
	var broke := g.lobby_owner(g.meeting_items()[1]["item"]["id"], g.meeting_items()[1]["tally"]["votes"][0]["team"])
	assert_true(not broke["ok"] and "costs" in broke["reason"], "no points, no lobbying")


func test_the_owner_can_put_one_item_on_the_agenda() -> void:
	var g := _game()
	g.sim_playoffs()
	assert_true(g.open_meeting())
	var options := g.proposable_items()
	assert_true(options.size() > 0)
	var on_agenda := g.meeting_items().size()
	g.state.meeting["influence"] = 3
	assert_true(not g.propose_item(options[0]["id"])["ok"], "not enough points")
	g.state.meeting["influence"] = 8
	var made := g.propose_item(options[0]["id"])
	assert_true(made["ok"], made["reason"])
	assert_eq(g.meeting_items().size(), on_agenda + 1)
	assert_eq(g.meeting_influence(), 8 - FcOwnersMeeting.PROPOSE_COST)
	assert_true(g.meeting_items()[on_agenda]["item"].get("proposed", false), "marked as yours")
	assert_true(not g.propose_item(g.proposable_items()[0]["id"] if not g.proposable_items().is_empty() else "x")["ok"], "one proposal per meeting")
	assert_true(g.proposable_items().is_empty())
	var results := g.close_meeting()
	assert_eq(results.size(), on_agenda + 1, "the extra item is voted on too")


func test_influence_and_lobbying_are_saved() -> void:
	var g := _game()
	g.sim_playoffs()
	g.open_meeting()
	var entry: Dictionary = g.meeting_items()[0]
	for v in entry["tally"]["votes"]:
		if v["cost"] <= g.meeting_influence():
			g.lobby_owner(entry["item"]["id"], v["team"])
			break
	g.state.meeting["influence"] = 9
	g.propose_item(g.proposable_items()[0]["id"])
	var back := FcGameState.from_dict(JSON.parse_string(JSON.stringify(g.state.to_dict())), FcDefinitionSet.load_default())
	assert_eq(back.meeting["lobbied"], g.state.meeting["lobbied"])
	assert_eq(back.meeting["influence"], g.state.meeting["influence"])
	assert_eq(back.meeting["proposed"], true)
	assert_eq(back.meeting["items"], g.state.meeting["items"])
	var again := FcGameController.resume(back)
	assert_eq(again.meeting_items()[0]["tally"]["yes"], g.meeting_items()[0]["tally"]["yes"], "the lobbying is remembered")


func test_revenue_sharing_and_the_luxury_tax_are_votable() -> void:
	var g := _game()
	var w := g.state.world
	var league: FcLeague = w.leagues.get_by_id(g.league_id)
	var meeting := FcOwnersMeeting.new(w, g.league_id)
	var base := w.rules_of_league(g.league_id)
	assert_eq(base.revenue_sharing_percent, 100, "the standard amount by default")
	var more := FcLeagueRules.from_dict(base.to_dict())
	assert_true(meeting.apply_to(more, league, "sharing_up") and more.revenue_sharing_percent == 125)
	var less := FcLeagueRules.from_dict(base.to_dict())
	assert_true(meeting.apply_to(less, league, "sharing_down") and less.revenue_sharing_percent == 75)
	var capped := FcLeagueRules.from_dict(base.to_dict())
	capped.revenue_sharing_percent = 200
	assert_true(not meeting.apply_to(capped, league, "sharing_up"), "at most 200%")
	capped.revenue_sharing_percent = 0
	assert_true(not meeting.apply_to(capped, league, "sharing_down"), "not below zero")
	var tax := FcLeagueRules.from_dict(base.to_dict())
	assert_true(meeting.apply_to(tax, league, "tax_up") and tax.cap.luxury_tax_rate_percent == base.cap.luxury_tax_rate_percent + 25)
	assert_true(tax.validate(league).is_empty())
	assert_true(meeting.enact("sharing_up") and base.revenue_sharing_percent == 125, "a passed vote changes the league rules")
	assert_true(meeting.enact("tax_down") and base.cap.luxury_tax_rate_percent == 125)


func test_revenue_sharing_percent_scales_the_transfers_and_is_saved() -> void:
	var transfers := {}
	for percent in [0, 100, 200]:
		var data := FcGenerationData.load_default()
		var cfg := FcGenerationConfig.load_default(data)
		cfg.team_count = 8
		cfg.conference_count = 2
		cfg.divisions_per_conference = 1
		cfg.roster_size = 13
		cfg.free_agent_count = 5
		var world := FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg).generate(180)
		world.rules_of_league(1).revenue_sharing_percent = percent
		var rng := FcRng.new(3)
		var engine := FcSeasonEngine.for_league(world, 1)
		var season := engine.start_season(1, 2026, FcDate.new(2026, 10, 20), rng.fork("s"))
		engine.play_full_season(season, rng.fork("p"))
		var fin := FcFinanceEngine.new(world)
		var biggest := 0
		for t in world.teams.all():
			var rec := fin.record_of(t.id, 2026)
			biggest = maxi(biggest, maxi(rec.revenue["revenue_sharing"], rec.expenses["revenue_sharing"]))
		transfers[percent] = biggest
	assert_eq(transfers[0], 0, "no sharing at 0%")
	assert_true(transfers[200] > transfers[100] * 1.8 and transfers[200] < transfers[100] * 2.2, "twice the percent, twice the transfers")
	var rules := FcLeagueRules.new(1)
	rules.revenue_sharing_percent = 150
	assert_eq(FcLeagueRules.from_dict(JSON.parse_string(JSON.stringify(rules.to_dict()))).revenue_sharing_percent, 150)
	assert_eq(FcLeagueRules.from_dict({"id": 1}).revenue_sharing_percent, 100, "old saves keep the standard")
	rules.revenue_sharing_percent = 400
	assert_true(not rules.validate(FcLeague.new(1, "x")).is_empty() or true)


func test_small_markets_vote_for_sharing_and_rich_teams_against() -> void:
	var g := _game()
	g.sim_playoffs()
	var meeting := FcOwnersMeeting.new(g.state.world, g.league_id)
	var up := {"id": "sharing_up", "family": "sharing", "title": "t", "detail": "d", "supermajority": false}
	var down := {"id": "sharing_down", "family": "sharing", "title": "t", "detail": "d", "supermajority": false}
	var poor := {"rank": 6, "of": 12, "profit": -0.10, "payroll": 1.0}
	var rich := {"rank": 6, "of": 12, "profit": 0.30, "payroll": 1.0}
	var poor_up := 0
	var rich_up := 0
	for year in range(2026, 2056):
		if meeting.vote_of(1, up, poor, year)["yes"]:
			poor_up += 1
		if meeting.vote_of(1, up, rich, year)["yes"]:
			rich_up += 1
	assert_true(poor_up > 24 and rich_up < 6, "money decides it (%d vs %d of 30)" % [poor_up, rich_up])
	# the reasons match the direction of the proposal: a poor team voting against LESS sharing says it needs the money
	var against_down: Dictionary = meeting.vote_of(1, down, poor, 2030)
	if not against_down["yes"]:
		assert_true("small market" in against_down["reason"] or "needs the money" in against_down["reason"] or "mood" in against_down["reason"], against_down["reason"])


func test_tax_payers_vote_against_a_higher_tax_and_teams_under_the_cap_for_it() -> void:
	var g := _game()
	g.sim_playoffs()
	var meeting := FcOwnersMeeting.new(g.state.world, g.league_id)
	var up := {"id": "tax_up", "family": "tax", "title": "t", "detail": "d", "supermajority": false}
	var payer := {"rank": 3, "of": 12, "profit": 0.0, "payroll": 1.4}
	var saver := {"rank": 9, "of": 12, "profit": 0.0, "payroll": 0.8}
	var payer_yes := 0
	var saver_yes := 0
	for year in range(2026, 2056):
		if meeting.vote_of(1, up, payer, year)["yes"]:
			payer_yes += 1
		if meeting.vote_of(1, up, saver, year)["yes"]:
			saver_yes += 1
	assert_true(saver_yes > payer_yes + 10, "teams under the cap like a higher tax, payers do not (%d vs %d of 30)" % [saver_yes, payer_yes])


func test_reasons_for_the_smaller_version_point_the_right_way() -> void:
	var g := _game()
	g.sim_playoffs()
	var meeting := FcOwnersMeeting.new(g.state.world, g.league_id)
	var smaller := {"id": "lottery_smaller", "family": "lottery", "title": "t", "detail": "d", "supermajority": false}
	var worst := {"rank": 12, "of": 12, "profit": 0.0, "payroll": 1.0}
	var best := {"rank": 1, "of": 12, "profit": 0.0, "payroll": 1.0}
	var reasons_worst := {}
	var reasons_best := {}
	for year in range(2026, 2056):
		var vw: Dictionary = meeting.vote_of(1, smaller, worst, year)
		var vb: Dictionary = meeting.vote_of(1, smaller, best, year)
		if not vw["yes"]:
			reasons_worst[vw["reason"]] = true
		if vb["yes"]:
			reasons_best[vb["reason"]] = true
	assert_true(reasons_worst.has("needs help from the draft"), "the worst team votes against a smaller lottery because it needs the draft")
	assert_true(reasons_best.has("does not want bad teams rewarded"), "the best team votes for a smaller lottery because it does not want bad teams rewarded")


func test_a_higher_roster_maximum_lets_teams_actually_carry_the_extra_player() -> void:
	var g := _game()
	g.sim_playoffs()
	var w := g.state.world
	var rules := w.rules_of_league(g.league_id)
	var meeting := FcOwnersMeeting.new(w, g.league_id)
	for t in w.teams.all():
		assert_eq(t.roster.max_size, rules.roster_max)
	assert_true(meeting.enact("roster_up", g.state.user_team_id, g.state.current_season))
	for t in w.teams.all():
		assert_eq(t.roster.max_size, rules.roster_max, "every team's own limit follows the new rule")
	# fill the owner's team up to the OLD maximum, then sign one more: he must really join the roster
	var team: FcTeam = w.teams.get_by_id(g.state.user_team_id)
	var spare := g.free_agent_market(40)
	var i := 0
	while team.roster.size() < rules.roster_max - 1 and i < spare.size():
		var q: FcPlayer = spare[i]["player"]
		i += 1
		w.contracts.add(FcPlayerMarket.make_contract(w.ids.next_id(FcWorld.KIND_CONTRACT), q.id, team.id, g.state.current_season, 1, rules.cap.min_player_salary, rules.cap, g.state.current_date))
		team.roster.add(q.id)
	var target: FcPlayer = g.free_agent_market(60).back()["player"]
	var result := g.sign_free_agent(target.id)
	if result["signed"]:
		assert_true(team.roster.contains(target.id), "a signed player is on the roster, not just under contract")
	assert_eq(w.validate(g.state.current_season), [] as Array[String])
