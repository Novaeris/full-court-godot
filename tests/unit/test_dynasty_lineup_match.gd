extends FcTestCase
## Team building (13-player roster rules) and the mapping to the existing simulation.

var env: FcDynastyEnv


func before_each() -> void:
	env = FcDynastyEnv.make()


func after_each() -> void:
	FcDynastyEnv.cleanup()


func test_starter_collection_makes_a_valid_13_player_roster() -> void:
	assert_eq(env.profile().roster.filled_count(), 13, "13 slots filled")
	assert_eq(FcDynastyLineup.problems(env.profile(), env.catalog), [], "the automatic lineup is valid")
	for i in FcDynastyRoster.STARTERS:
		var v := env.catalog.view(env.profile().roster.slots[i])
		assert_true(FcDynastyLineup.eligible(v, i), "starter %d fits his position" % i)


func test_position_eligibility_uses_primary_and_secondary() -> void:
	var alpha := env.catalog.view(FcDynastyFixture.card_id(0))  # PG with SG secondary
	assert_true(FcDynastyLineup.eligible(alpha, 0) and FcDynastyLineup.eligible(alpha, 1), "PG/SG fits two starter slots")
	assert_true(not FcDynastyLineup.eligible(alpha, 4), "but not C")
	assert_true(FcDynastyLineup.eligible(alpha, 9), "bench takes anyone")


func test_invalid_assignments_are_refused() -> void:
	var p := env.profile()
	var center := FcDynastyFixture.card_id(14)  # a C with no secondary position
	var r1 := FcDynastyLineup.assign(p, env.catalog, 0, center)
	assert_eq(r1.code, "position", "a C cannot start at PG")
	assert_eq(FcDynastyLineup.assign(p, env.catalog, 5, FcDynastyFixture.card_id(29)).code, "not_owned", "an unowned card cannot be used")
	assert_eq(FcDynastyLineup.assign(p, env.catalog, 99, center).code, "bad_slot", "no such slot")


func test_two_editions_of_one_player_cannot_share_a_roster() -> void:
	env.give(FcDynastyFixture.card_id(3, "allstar"))
	var p := env.profile()
	var base := FcDynastyFixture.card_id(3)
	var star := FcDynastyFixture.card_id(3, "allstar")
	assert_true(p.roster.slot_of(base) >= 0, "the base edition is on the roster")
	var r := FcDynastyLineup.assign(p, env.catalog, 12, star)
	assert_eq(r.code, "same_player", "the other edition is refused")
	# replacing the base edition itself is fine
	var slot := p.roster.slot_of(base)
	assert_true(FcDynastyLineup.assign(p, env.catalog, slot, star).ok, "the edition can replace the other one in the same slot")
	assert_eq(FcDynastyLineup.problems(p, env.catalog), [], "roster stays valid")


func test_moving_a_card_swaps_or_clears() -> void:
	var p := env.profile()
	var a := str(p.roster.slots[5])
	var b := str(p.roster.slots[6])
	assert_true(FcDynastyLineup.assign(p, env.catalog, 5, b).ok, "move a bench card onto another bench slot")
	assert_eq(str(p.roster.slots[5]), b, "moved")
	assert_eq(str(p.roster.slots[6]), a, "the displaced card swapped into the old slot")
	FcDynastyLineup.clear_slot(p, 12)
	assert_true(not FcDynastyLineup.problems(p, env.catalog).is_empty(), "an empty slot makes the roster invalid")


func test_rotation_settings_persist_and_clamp() -> void:
	FcDynastyLineup.set_minutes(env.profile(), 7, 1)
	FcDynastyLineup.set_minutes(env.profile(), 8, -5)
	var r := env.session.commit(func() -> FcDynastyResult: return FcDynastyResult.success())
	assert_true(r.ok, "save")
	var back: FcDynastyProfile = env.store.load_slot("env").data["profile"]
	assert_eq(back.roster.minutes[7], 1, "more minutes kept")
	assert_eq(back.roster.minutes[8], -1, "clamped to -1")
	assert_eq(back.roster.slots, env.profile().roster.slots, "the lineup persists")


func test_team_overall_comes_from_the_roster() -> void:
	var p := env.profile()
	var overall := FcDynastyLineup.team_overall(p, env.catalog)
	var weights := env.catalog.config.team_weights()
	var manual := 0.0
	var wsum := 0.0
	for i in 13:
		manual += float(weights[i]) * env.catalog.overall_of(p.roster.slots[i])
		wsum += float(weights[i])
	assert_between(overall, manual / wsum - 0.001, manual / wsum + 0.001, "weighted average of the 13 slots")
	var worse := p.roster.slots.duplicate()
	worse[0] = FcDynastyFixture.card_id(0)
	assert_true(FcDynastyLineup.overall_of_cards(worse, env.catalog) != overall, "changing a starter changes the team overall")
	assert_eq(FcDynastyLineup.identity(p, env.catalog).size(), 2, "two identity traits")


func test_recommendation_prefers_better_players() -> void:
	env.give(FcDynastyFixture.card_id(29))  # a legendary center? position of 29 is C (29 % 5 = 4)
	var rec := FcDynastyLineup.recommend(env.profile(), env.catalog)
	assert_eq(rec[4], FcDynastyFixture.card_id(29), "the best center starts")
	assert_true(not rec.has(""), "13 cards available, none empty")


func test_dynasty_team_maps_to_simulation_input() -> void:
	var p := env.profile()
	FcDynastyLineup.set_minutes(p, 6, 1)
	var built := FcDynastyMatch.build_team(p.roster.slots, p.roster.minutes, env.catalog, 1, "Test Kings", "TKG", 0)
	var team: FcGameTeam = built["team"]
	assert_eq(team.players.size(), 13, "13 simulated players")
	assert_eq(team.players[0].position, FcPosition.Id.PG, "slot order kept: PG first")
	assert_eq(built["cards"][1], p.roster.slots[0], "simulated player ids map back to cards")
	assert_true(team.players[0].role_bonus >= 1000.0 and team.players[8].role_bonus == 0.0, "starters are forced, bench is not")
	assert_eq(team.players[6].minutes_pref, 1.0, "rotation setting becomes minutes preference")
	assert_true(team.players[0].ratings["three"] >= env.catalog.ratings.compute(env.catalog.make_player(p.roster.slots[0], 9))["three"], "badge bonus applied to a composite")


func test_simulation_starts_the_chosen_five_and_is_reproducible() -> void:
	var p := env.profile()
	var user := FcDynastyMatch.build_team(p.roster.slots, p.roster.minutes, env.catalog, 1, "Test Kings", "TKG", 0)
	var slots := FcDynastyOpponents.generate(env.catalog, 60, 5)
	var opp := FcDynastyMatch.build_team(slots, [], env.catalog, 2, "CPU", "CPU", 100)
	var played := FcDynastyMatch.simulate(user, opp, 4242, true)
	var summary := FcDynastyMatch.summarize(played)
	var starters: Array = []
	for line in summary["players"]:
		if line["started"]:
			starters.append(line["card_id"])
	starters.sort()
	var expected: Array = p.roster.slots.slice(0, 5)
	expected.sort()
	assert_eq(starters, expected, "the simulator starts exactly the five starters")
	assert_true(summary["score_for"] > 40 and summary["score_against"] > 40, "a real basketball score")
	assert_true(summary["score_for"] != summary["score_against"], "someone won")
	var user2 := FcDynastyMatch.build_team(p.roster.slots, p.roster.minutes, env.catalog, 1, "Test Kings", "TKG", 0)
	var opp2 := FcDynastyMatch.build_team(slots, [], env.catalog, 2, "CPU", "CPU", 100)
	var again := FcDynastyMatch.summarize(FcDynastyMatch.simulate(user2, opp2, 4242, true))
	assert_eq(again["score_for"], summary["score_for"], "the same seed gives the same game")


func test_opponents_are_deterministic_valid_and_scaled() -> void:
	var a := FcDynastyOpponents.generate(env.catalog, 60, 9)
	var b := FcDynastyOpponents.generate(env.catalog, 60, 9)
	assert_eq(a, b, "same seed, same opponent")
	var weak := FcDynastyLineup.overall_of_cards(FcDynastyOpponents.generate(env.catalog, 55, 9), env.catalog)
	var strong := FcDynastyLineup.overall_of_cards(FcDynastyOpponents.generate(env.catalog, 80, 9), env.catalog)
	assert_true(strong > weak + 10.0, "a higher target gives a stronger team")
	var players := {}
	for id in a:
		players[env.catalog.view(id)["player_id"]] = true
	assert_eq(players.size(), 13, "13 different players")


func test_quick_game_updates_records_and_pays_rewards() -> void:
	var p := env.profile()
	var credits_before := p.balance("credits")
	var r := env.session.commit(func() -> FcDynastyResult: return FcDynastyPlay.quick_game(env.session.profile, env.catalog, "even"))
	assert_true(r.ok, "game played: %s" % r.message)
	p = env.profile()
	assert_eq(p.record["games"], 1, "game counted")
	assert_eq(p.record["wins"] + p.record["losses"], 1, "a win or a loss")
	var won: bool = r.data["summary"]["won"]
	assert_eq(p.balance("credits") - credits_before, env.catalog.config.game_reward(won), "reward matches the result")
	assert_eq(p.game_history.size(), 1, "history kept")
	assert_true(p.card_stats.size() >= 5, "player statistics recorded per card")
	var loaded: FcDynastyProfile = env.store.load_slot("env").data["profile"]
	assert_eq(loaded.record, p.record, "and saved")


func test_an_invalid_lineup_cannot_enter_a_game() -> void:
	FcDynastyLineup.clear_slot(env.profile(), 3)
	var r := env.session.commit(func() -> FcDynastyResult: return FcDynastyPlay.quick_game(env.session.profile, env.catalog, "even"))
	assert_eq(r.code, "invalid_roster", "refused")
	assert_eq(env.profile().record["games"], 0, "nothing was recorded")
