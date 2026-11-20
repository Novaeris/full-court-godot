extends FcTestCase
## Challenges (progress from real results, one-time claims), the season, the tournament and persistence of all of it.

var env: FcDynastyEnv


func before_each() -> void:
	env = FcDynastyEnv.make()


func after_each() -> void:
	FcDynastyEnv.cleanup()


## A synthetic game summary in the exact shape the simulation's summarizer produces.
func _summary(won: bool, points: int, threes: int = 0, assists: int = 0, steals: int = 0, best_rebounds: int = 0, starters: Array = []) -> Dictionary:
	var lines: Array = []
	for i in 5:
		var card: String = starters[i] if i < starters.size() else str(env.profile().roster.slots[i])
		lines.append({"card_id": card, "name": "x", "started": true, "seconds": 1800, "points": points / 5, "rebounds": best_rebounds if i == 0 else 3,
			"assists": assists / 5, "steals": steals / 5, "blocks": 0, "threes": threes / 5, "free_throws": 0})
	return {"won": won, "score_for": points, "score_against": points - 5 if won else points + 5, "margin": 5 if won else -5, "overtimes": 0,
		"opponent": "CPU", "home": true,
		"team": {"points": points, "rebounds": 40, "assists": assists, "steals": steals, "blocks": 2, "threes": threes, "free_throws": 10},
		"players": lines}


func _on_game(summary: Dictionary) -> Array[String]:
	var out: Array[String] = []
	env.session.commit(func() -> FcDynastyResult:
		out.append_array(FcDynastyChallenges.on_game(env.session.profile, env.catalog, summary))
		return FcDynastyResult.success())
	return out


func test_challenge_progress_comes_from_game_results() -> void:
	assert_eq(_on_game(_summary(true, 90, 8)), ["underdogs"], "a win with low-rarity starters completes 'underdogs'; 90 points is not 100")
	var done := _on_game(_summary(true, 104, 11, 0, 0, 12))
	assert_true(done.has("score_100") and done.has("triples") and done.has("glass"), "scoring, shooting and rebounding challenges complete from one game: %s" % str(done))
	var s := FcDynastyChallenges.state_of(env.profile(), "win_three")
	assert_eq(s["progress"], 2, "wins accumulate over games")
	assert_true(not s["done"], "not finished")
	_on_game(_summary(false, 80))
	assert_eq(FcDynastyChallenges.state_of(env.profile(), "win_three")["progress"], 2, "a loss adds nothing")
	_on_game(_summary(true, 85))
	assert_true(FcDynastyChallenges.state_of(env.profile(), "win_three")["done"], "three wins complete it")
	# cumulative stats add up across games
	_on_game(_summary(false, 80, 0, 25))
	_on_game(_summary(false, 80, 0, 20))
	assert_true(FcDynastyChallenges.state_of(env.profile(), "dimes")["done"], "40 assists over several games")


func test_roster_restrictions_gate_progress() -> void:
	# put a legendary (above 'rare') starter on the roster: 'underdogs' (max rarity rare) must not progress
	env.give(FcDynastyFixture.card_id(29))
	FcDynastyLineup.assign(env.profile(), env.catalog, 4, FcDynastyFixture.card_id(29))
	assert_eq(_on_game(_summary(true, 90)), [], "a legendary starter breaks the restriction")
	assert_eq(FcDynastyChallenges.state_of(env.profile(), "underdogs")["progress"], 0, "no progress")


func test_a_reward_can_be_claimed_only_once() -> void:
	_on_game(_summary(true, 104))
	var before := env.profile().balance("credits")
	var claim := func() -> FcDynastyResult: return FcDynastyChallenges.claim(env.session.profile, env.catalog, "score_100")
	var first := env.session.commit(claim)
	assert_true(first.ok, "claimed")
	assert_eq(env.profile().balance("credits"), before + 300, "reward from the published definition")
	var second := env.session.commit(claim)
	assert_eq(second.code, "already_claimed", "no second claim")
	assert_eq(env.profile().balance("credits"), before + 300, "no second payment")
	assert_eq(env.session.commit(func() -> FcDynastyResult: return FcDynastyChallenges.claim(env.session.profile, env.catalog, "triples")).code, "not_complete", "an unfinished challenge cannot be claimed")
	var saved: FcDynastyProfile = env.store.load_slot("env").data["profile"]
	assert_true(FcDynastyChallenges.state_of(saved, "score_100")["claimed"], "the claim survives a reload")


func test_real_games_feed_challenges() -> void:
	var finished := false
	for i in 6:
		var r := env.session.commit(func() -> FcDynastyResult: return FcDynastyPlay.quick_game(env.session.profile, env.catalog, "easy"))
		assert_true(r.ok, "game %d" % i)
		if FcDynastyChallenges.state_of(env.profile(), "underdogs")["done"]:
			finished = true
	assert_true(finished, "winning easy games with a low-rarity lineup completes 'underdogs' from actual simulation results")
	assert_true(env.profile().record["wins"] >= 1, "the starter lineup beats easy opposition at least once")


func test_season_points_milestones_and_objectives() -> void:
	var o := FcDynastySeason.overview(env.profile(), env.catalog)
	assert_eq(o["season_id"], "season_one", "active season")
	assert_eq(o["points"], 0, "nothing yet")
	_on_game(_summary(true, 104, 11))  # completes score_100 and triples: 10 points each
	var after := FcDynastySeason.points(env.profile(), env.catalog, "season_one")
	assert_eq(after, 20, "season points are the sum of completed seasonal challenges")
	var claim := func() -> FcDynastyResult: return FcDynastySeason.claim_milestone(env.session.profile, env.catalog, "season_one", "m1")
	var credits := env.profile().balance("credits")
	assert_true(env.session.commit(claim).ok, "milestone m1 (10 points) reached and claimed")
	assert_eq(env.profile().balance("credits"), credits + 200, "milestone reward")
	assert_eq(env.session.commit(claim).code, "already_claimed", "once only")
	assert_eq(env.session.commit(func() -> FcDynastyResult: return FcDynastySeason.claim_milestone(env.session.profile, env.catalog, "season_one", "m2")).code, "not_reached", "m2 needs 30")
	# a season objective from real wins
	for i in 5:
		env.session.commit(func() -> FcDynastyResult:
			FcDynastySeason.on_game(env.session.profile, env.catalog, _summary(true, 99))
			return FcDynastyResult.success())
	assert_true(FcDynastySeason.objective_state(env.profile(), "season_one", "wins5")["done"], "the season objective completes after 5 wins")
	assert_true(FcDynastySeason.points(env.profile(), env.catalog, "season_one") >= 40, "and adds its points")


func test_a_new_release_season_keeps_the_collection() -> void:
	var cards_before := env.profile().unique_owned()
	var later := FcDynastyFixture.catalog(2, "fcr_2123456789abcdef")
	later.content.seasonal["season_two"] = {"season_id": "season_two", "name": "Season Two", "active": true, "milestones": [], "objectives": []}
	later.content.seasonal["season_one"]["active"] = false
	assert_eq(later.active_season_id(), "season_two", "the new release's season is active")
	FcDynastyOnboarding.sync_release(env.profile(), later)
	assert_eq(env.profile().unique_owned(), cards_before, "a new season never removes owned cards")
	assert_eq(FcDynastySeason.overview(env.profile(), later)["points"], 0, "fresh season progress")


func _enter(tid: String) -> FcDynastyResult:
	return env.session.commit(func() -> FcDynastyResult: return FcDynastyTournament.enter(env.session.profile, env.catalog, tid))


func _next() -> FcDynastyResult:
	return env.session.commit(func() -> FcDynastyResult: return FcDynastyTournament.play_next(env.session.profile, env.catalog))


func test_tournament_bracket_progresses_to_a_final_result() -> void:
	var credits := env.profile().balance("credits")
	var r := _enter("test_cup")
	assert_true(r.ok, "entered: %s" % r.message)
	assert_eq(env.profile().balance("credits"), credits - 100, "entry fee from the published definition")
	assert_eq(_enter("test_cup").code, "already_entered", "one run at a time")
	var run := FcDynastyTournament.active(env.profile())
	assert_eq(run["teams"].size(), 8, "eight teams")
	assert_eq(run["rounds"][0].size(), 4, "four quarterfinals")
	var finished := false
	var played := 0
	while not finished and played < 3:
		var step := _next()
		assert_true(step.ok, "match %d: %s" % [played, step.message])
		played += 1
		finished = step.data["finished"]
	assert_true(finished, "the run ends after at most three of your matches")
	assert_true(not FcDynastyTournament.has_active(env.profile()), "no active run afterwards")
	var hist: Array = env.profile().tournament["history"]
	assert_eq(hist.size(), 1, "history entry")
	assert_true(["champion", "finalist", "semifinal", "quarterfinal"].has(hist[0]["placement"]), "a placement")
	assert_true(env.profile().record["games"] == played, "tournament games count as real games")
	assert_true(env.profile().ledger.any(func(t): return t["kind"] == "tournament_reward"), "the placement reward was paid once")
	var rewards_paid := env.profile().ledger.filter(func(t): return t["kind"] == "tournament_reward").size()
	assert_eq(rewards_paid, 1, "exactly one reward transaction")
	assert_eq(_next().code, "not_entered", "no more matches to play")


func test_tournament_state_survives_saving_and_loading() -> void:
	_enter("test_cup")
	var first := _next()
	assert_true(first.ok, "first match")
	if first.data["finished"]:
		return  # lost round one: the run completed, nothing in progress to reload (covered by the other test)
	var snapshot := FcDynastyTournament.active(env.profile()).duplicate(true)
	var loaded: FcDynastyProfile = env.store.load_slot("env").data["profile"]
	assert_eq(FcDynastyTournament.active(loaded), snapshot, "the bracket reloads exactly")
	var session2 := FcDynastySession.new(loaded, env.store, "env")
	var cont := session2.commit(func() -> FcDynastyResult: return FcDynastyTournament.play_next(session2.profile, env.catalog))
	assert_true(cont.ok, "the reloaded run continues")


func test_tournament_runs_are_reproducible_from_the_seed() -> void:
	var a := FcDynastyEnv.make(4321)
	var b := FcDynastyEnv.make(4321)
	a.session.commit(func() -> FcDynastyResult: return FcDynastyTournament.enter(a.session.profile, a.catalog, "test_cup"))
	b.session.commit(func() -> FcDynastyResult: return FcDynastyTournament.enter(b.session.profile, b.catalog, "test_cup"))
	assert_eq(FcDynastyTournament.active(a.profile()), FcDynastyTournament.active(b.profile()), "same seed, same bracket")


func test_tournament_needs_a_valid_lineup_and_funds() -> void:
	FcDynastyLineup.clear_slot(env.profile(), 0)
	assert_eq(_enter("test_cup").code, "invalid_roster", "invalid lineup refused")
	FcDynastyLineup.auto_fill(env.profile(), env.catalog)
	env.session.commit(func() -> FcDynastyResult: return FcDynastyEconomy.spend(env.session.profile, "t", "t", {"credits": env.profile().balance("credits")}))
	assert_eq(_enter("test_cup").code, "insufficient_funds", "cannot pay the entry fee")
	assert_eq(_enter("nope").code, "unknown_tournament", "unknown tournament")


func test_whole_profile_survives_save_and_load() -> void:
	env.session.commit(func() -> FcDynastyResult: return FcDynastyPlay.quick_game(env.session.profile, env.catalog, "even"))
	env.session.commit(func() -> FcDynastyResult: return FcDynastyPacks.buy_and_open(env.session.profile, env.catalog, "bronze_pack", "rq"))
	_on_game(_summary(true, 104))
	var loaded: FcDynastyProfile = env.store.load_slot("env").data["profile"]
	assert_eq(loaded.to_dict(), env.profile().to_dict(), "everything (currency, cards, ledger, openings, lineup, challenges, record) is saved")
	assert_eq(loaded.validate(), [], "and valid")
