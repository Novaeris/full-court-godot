class_name FcDynastyPlay
extends RefCounted
## Plays one Dynasty game end to end: checks the lineup, builds both teams for the existing simulator, simulates, records the
## result and updates challenges and the season from the REAL outcome. Everything here runs inside FcDynastySession.commit.


static func opponent_level(catalog: FcDynastyCatalog, level_id: String) -> Dictionary:
	for lv in catalog.config.opponent_levels():
		if str(lv["id"]) == level_id:
			return lv
	var levels := catalog.config.opponent_levels()
	return levels[0] if not levels.is_empty() else {"id": "even", "name": "Even match", "offset": 0, "reward_percent": 100}


## Plays a quick game against a computer team of the chosen level. Data on success:
## {summary, reward, completed_challenges, completed_objectives, game_number}.
static func quick_game(profile: FcDynastyProfile, catalog: FcDynastyCatalog, level_id: String) -> FcDynastyResult:
	var problems := FcDynastyLineup.problems(profile, catalog)
	if not problems.is_empty():
		return FcDynastyResult.failure("invalid_roster", "Your lineup is not ready: %s" % problems[0])
	if not catalog.is_playable():
		return FcDynastyResult.failure("no_content", catalog.playable_problem())
	var level := opponent_level(catalog, level_id)
	var number := profile.game_counter + 1
	var target := roundi(FcDynastyLineup.team_overall(profile, catalog)) + int(level["offset"])
	var seed_value := hash("%d:game:%d" % [profile.rng_seed, number])
	var slots := FcDynastyOpponents.generate(catalog, clampi(target, 40, 99), seed_value)
	var opponent := {"name": "%s Squad" % str(level["name"]), "abbreviation": "CPU", "slots": slots}
	return play_against(profile, catalog, opponent, seed_value, "quick", int(level.get("reward_percent", 100)))


## Plays the user's roster against `opponent` ({name, abbreviation, slots}) and records everything.
static func play_against(profile: FcDynastyProfile, catalog: FcDynastyCatalog, opponent: Dictionary, seed_value: int,
		kind: String, reward_percent: int) -> FcDynastyResult:
	var user := FcDynastyMatch.build_team(profile.roster.slots, profile.roster.minutes, catalog, FcDynastyMatch.USER_TEAM_ID,
		profile.team_name, profile.abbreviation, 0)
	var other := FcDynastyMatch.build_team(opponent["slots"], [], catalog, FcDynastyMatch.OPPONENT_TEAM_ID,
		str(opponent["name"]), str(opponent.get("abbreviation", "CPU")), FcDynastyMatch.OPPONENT_ID_BASE)
	var played := FcDynastyMatch.simulate(user, other, seed_value, seed_value % 2 == 0)
	var summary := FcDynastyMatch.summarize(played)
	var recorded := FcDynastyProgress.record_game(profile, catalog, summary, kind, reward_percent)
	if not recorded.ok:
		return recorded
	var challenges := FcDynastyChallenges.on_game(profile, catalog, summary)
	var objectives := FcDynastySeason.on_game(profile, catalog, summary)
	return FcDynastyResult.success({
		"summary": summary, "reward": recorded.data["reward"], "game_number": recorded.data["game_number"],
		"completed_challenges": challenges, "completed_objectives": objectives,
		# read-only pass-through for the post-game screen (D-053): the simulation's own box score, never saved or used by any rule
		"box": (played["box"] as FcBoxScore).to_dict(), "user_side": played["user_side"], "cards": played["cards"]})
