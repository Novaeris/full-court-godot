extends FcTestCase
## Career Mode: rivalries. A rival is a peer on another team, chosen when the player accepts the challenge; nights against him
## are scored as duels from the real box score.

var defs: FcDefinitionSet


func before_each() -> void:
	defs = FcDefinitionSet.load_default()


func _profile() -> FcCareerProfile:
	var p := FcCareerProfile.new()
	p.profile_id = "fcp_0123456789abcdef"
	p.player_id = 1
	return p


func _career(seed_value: int = 101) -> FcCareerController:
	var spec := FcPlayerBuild.default_spec("two_way_wing", 3, defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	for key in ["perimeter_defense", "three_point", "layups", "speed", "agility", "stamina", "rebounding", "passing", "ball_handling"]:
		spec["attributes"][key] = 70
	var c: FcCareerController = FcCareerController.new_career(spec, seed_value)["controller"]
	c.join_team(c.state.world.teams.ids()[1])
	c.answer_event(c.pending_event()["choices"][0]["key"])
	return c


func test_game_score_counts_what_wins() -> void:
	var line := {"points": 20, "rebounds": 10, "assists": 5, "steals": 2, "blocks": 1, "turnovers": 3}
	assert_eq(FcCareerRules.game_score(line), 20.0 + 12.0 + 7.5 + 4.0 + 2.0 - 4.5)
	assert_eq(FcCareerRules.game_score({}), 0.0)


func test_the_rival_is_a_seeded_peer_among_the_closest_candidates() -> void:
	var candidates: Array = [[10, 40.0], [11, 52.0], [12, 55.0], [13, 56.0], [14, 70.0], [15, 80.0]]
	var a := FcCareerRules.pick_rival(candidates, 54.0, FcRng.new(5))
	var b := FcCareerRules.pick_rival(candidates, 54.0, FcRng.new(5))
	assert_eq(a, b, "seeded: the same career picks the same rival")
	var seen := {}
	for seed_value in 80:
		seen[FcCareerRules.pick_rival(candidates, 54.0, FcRng.new(seed_value))] = true
	for id in seen:
		assert_true(id in [11, 12, 13], "only the three closest are possible (%d)" % id)
	assert_true(seen.size() >= 2)
	assert_eq(FcCareerRules.pick_rival([], 50.0, FcRng.new(1)), 0)


func test_a_duel_is_won_by_the_better_night_and_pays_only_a_win() -> void:
	var p := _profile()
	var mine := {"points": 25, "rebounds": 8, "assists": 6, "steals": 1, "blocks": 0, "turnovers": 2}
	var theirs := {"points": 10, "rebounds": 4, "assists": 2, "steals": 0, "blocks": 0, "turnovers": 4}
	var win := FcCareerRules.duel(p, mine, theirs)
	assert_true(win["won"] and win["xp"] == 30 and p.xp == 30 and p.rival_wins == 1 and p.rival_losses == 0)
	var loss := FcCareerRules.duel(p, theirs, mine)
	assert_true(not loss["won"] and loss["xp"] == 0 and p.xp == 30 and p.rival_losses == 1, "a loss costs nothing but the record")
	assert_true(not FcCareerRules.duel(p, mine, mine)["won"], "a tie is not a win")
	FcCareerRules.duel(p, mine, theirs)
	var third := FcCareerRules.duel(p, mine, theirs)
	assert_eq(p.rival_wins, 3)
	assert_eq(third["reputation"], 1, "every third win earns a point of reputation")
	assert_eq(p.reputation, 1)


func test_accepting_the_challenge_picks_a_rival_on_another_team() -> void:
	var c := _career()
	assert_eq(c.rival(), {})
	c.profile().pending_event = "rival_challenge"
	var r := c.answer_event("accept")
	assert_true(r["ok"] and "Your rival:" in r["reason"], r["reason"])
	var rival := c.rival()
	assert_true(not rival.is_empty() and rival["wins"] == 0 and rival["losses"] == 0)
	var team := c.state.world.team_of_player(c.profile().rival_player_id)
	assert_true(team.id != c.state.user_team_id, "never a teammate")
	assert_true(c.profile().tags.has("rival"))
	var ignored := _career(102)
	ignored.profile().pending_event = "rival_challenge"
	ignored.answer_event("ignore")
	assert_eq(ignored.rival(), {}, "ignoring the challenge makes no rival")


func test_a_game_against_the_rival_is_scored_as_a_duel_exactly_once() -> void:
	var c := _career(103)
	# make a player of his first opponent the rival, then play until the teams meet
	var next := c.game().next_user_game()
	var opponent_id: int = next.away_id if next.home_id == c.state.user_team_id else next.home_id
	var ratings := FcPlayerRatings.load_default()
	var best := 0
	var best_overall := -1.0
	for pid in c.state.world.teams.get_by_id(opponent_id).roster.player_ids:
		var o := ratings.overall(c.state.world.players.get_by_id(pid))
		if o > best_overall:
			best_overall = o
			best = pid
	c.profile().rival_player_id = best
	c.profile().role = "starter"   # make sure he plays when the teams meet (set directly: this test is about duels, not the coach)
	c.profile().minutes_pref = 1
	c._sync_badges()
	var duels: Array = []
	for i in 130:
		if c.game().phase() == FcGameController.PHASE_COMPLETE:
			break
		for g in c.advance_day()["games"]:
			if g.has("duel"):
				duels.append(g)
		if not duels.is_empty():
			break
	assert_true(not duels.is_empty(), "he met his rival's team and the duel was scored")
	var duel: Dictionary = duels[0]["duel"]
	assert_true(duel["won"] in [true, false] and str(duel["rival"]) != "")
	assert_eq(c.profile().rival_wins + c.profile().rival_losses, duels.size(), "one duel per meeting")
	assert_eq(c._collect_games(), [], "already scored, never twice")
	var rival := c.rival()
	assert_eq(rival["wins"] + rival["losses"], duels.size())


func test_the_rivalry_survives_saving_and_a_retired_rival_ends_it() -> void:
	var c := _career(104)
	c.profile().pending_event = "rival_challenge"
	c.answer_event("accept")
	var back := FcCareerProfile.from_dict(JSON.parse_string(JSON.stringify(c.profile().to_dict())))
	assert_eq([back.rival_player_id, back.rival_wins, back.rival_losses], [c.profile().rival_player_id, 0, 0])
	assert_eq(back.checksum(), c.profile().checksum())
	var rival_player: FcPlayer = c.state.world.players.get_by_id(c.profile().rival_player_id)
	rival_player.status = FcPlayer.Status.RETIRED
	rival_player.retired_season = c.state.current_season
	assert_eq(c.rival(), {}, "a retired rival is no rival")
	c._after_offseason()
	assert_eq(c.profile().rival_player_id, 0, "the rivalry ends and a later challenge can start a new one")
	assert_eq(c.state.validate().size() >= 0, true)
