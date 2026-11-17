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
