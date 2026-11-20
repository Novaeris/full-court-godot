class_name FcDynastyTournament
extends RefCounted
## The eight-team single-elimination tournament: quarterfinals, semifinals, final. Every match, yours and the computer's, is
## played by the existing simulator. The run is stored in the profile (`profile.tournament["active"]`), so it survives saving
## and reloading; all seeds derive from the profile seed and run number, so a run is reproducible.
##
## Run record: {run_id, tournament_id, name, seed, status ("active"|"champion"|"eliminated"), round (0-2),
## teams: [{name, abbreviation, user, slots}] (8, in bracket order), rounds: [[match...]] where
## match = {a, b, winner (-1 until played), score_a, score_b}, placement, reward_txn}.

const ROUND_NAMES := ["Quarterfinals", "Semifinals", "Final"]
const PLACEMENT_BY_ROUND := ["quarterfinal", "semifinal", "finalist"]


static func find_definition(catalog: FcDynastyCatalog, tournament_id: String) -> Dictionary:
	for sid in catalog.seasons():
		for t in catalog.season(str(sid)).get("tournaments", []):
			if str(t["tournament_id"]) == tournament_id:
				return t
	return {}


static func has_active(profile: FcDynastyProfile) -> bool:
	return not profile.tournament.get("active", {}).is_empty()


static func active(profile: FcDynastyProfile) -> Dictionary:
	return profile.tournament.get("active", {})


## Pays the entry fee, seeds the bracket and starts a run. The user's team sits at a seeded position.
static func enter(profile: FcDynastyProfile, catalog: FcDynastyCatalog, tournament_id: String) -> FcDynastyResult:
	if has_active(profile):
		return FcDynastyResult.failure("already_entered", "You are already in a tournament.")
	var def := find_definition(catalog, tournament_id)
	if def.is_empty():
		return FcDynastyResult.failure("unknown_tournament", "That tournament is not in the current content release.")
	var problems := FcDynastyLineup.problems(profile, catalog)
	if not problems.is_empty():
		return FcDynastyResult.failure("invalid_roster", "Your lineup is not ready: %s" % problems[0])
	var run_number := int(profile.tournament.get("run_counter", 0)) + 1
	var run_id := "tr_%06d" % run_number
	var fee: Dictionary = def.get("entry_fee", {})
	var cost := {}
	if not fee.is_empty() and int(fee["amount"]) > 0:
		cost[str(fee["currency"])] = int(fee["amount"])
	var paid := FcDynastyEconomy.spend(profile, "tournament_entry", tournament_id, cost, [], "enter:%s" % run_id)
	if not paid.ok:
		return paid
	if bool(paid.data.get("replayed", false)):
		return FcDynastyResult.failure("duplicate_request", "This tournament entry was already processed.")
	var seed_value := hash("%d:tournament:%d" % [profile.rng_seed, run_number])
	var rng := FcRng.new(seed_value)
	var teams: Array = [{"name": profile.team_name, "abbreviation": profile.abbreviation, "user": true, "slots": []}]
	for i in def["teams"].size():
		var t := FcDynastyOpponents.tournament_team(catalog, def["teams"][i], hash("%d:team:%d" % [seed_value, i]))
		teams.append({"name": t["name"], "abbreviation": t["abbreviation"], "user": false, "slots": t["slots"]})
	# seeded shuffle of bracket positions
	for i in range(teams.size() - 1, 0, -1):
		var j := rng.range_int(0, i)
		var tmp = teams[i]
		teams[i] = teams[j]
		teams[j] = tmp
	var first: Array = []
	for m in 4:
		first.append({"a": 2 * m, "b": 2 * m + 1, "winner": -1, "score_a": 0, "score_b": 0})
	profile.tournament["run_counter"] = run_number
	profile.tournament["active"] = {"run_id": run_id, "tournament_id": tournament_id, "name": str(def["name"]), "seed": str(seed_value),
		"status": "active", "round": 0, "teams": teams, "rounds": [first], "placement": "", "reward_txn": ""}
	return FcDynastyResult.success({"run": profile.tournament["active"]})


static func user_index(run: Dictionary) -> int:
	for i in run["teams"].size():
		if bool(run["teams"][i]["user"]):
			return i
	return -1


## Plays the user's next match (and the computer's matches in the same round). Data: {summary, run, finished}.
static func play_next(profile: FcDynastyProfile, catalog: FcDynastyCatalog) -> FcDynastyResult:
	if not has_active(profile):
		return FcDynastyResult.failure("not_entered", "You are not in a tournament.")
	var run: Dictionary = profile.tournament["active"]
	var problems := FcDynastyLineup.problems(profile, catalog)
	if not problems.is_empty():
		return FcDynastyResult.failure("invalid_roster", "Your lineup is not ready: %s" % problems[0])
	var rd: int = run["round"]
	var me := user_index(run)
	var matches: Array = run["rounds"][rd]
	var seed_value := int(str(run["seed"]))
	var summary: Dictionary = {}
	var shown: Dictionary = {}   # the user's own match, for the post-game screen only
	for m_index in matches.size():
		var m: Dictionary = matches[m_index]
		if int(m["a"]) == me or int(m["b"]) == me:
			var other_index: int = int(m["b"]) if int(m["a"]) == me else int(m["a"])
			var opp: Dictionary = run["teams"][other_index]
			var played := FcDynastyPlay.play_against(profile, catalog, opp, hash("%d:r%d:m%d" % [seed_value, rd, m_index]), "tournament", 0)
			if not played.ok:
				return played
			summary = played.data["summary"]
			shown = {"box": played.data["box"], "user_side": played.data["user_side"], "cards": played.data["cards"]}
			var won: bool = bool(summary["won"])
			m["winner"] = me if won else other_index
			var me_is_a: bool = int(m["a"]) == me
			m["score_a"] = int(summary["score_for"]) if me_is_a else int(summary["score_against"])
			m["score_b"] = int(summary["score_against"]) if me_is_a else int(summary["score_for"])
		else:
			_simulate_cpu_match(catalog, run, m, hash("%d:r%d:m%d" % [seed_value, rd, m_index]))
	var user_won := _winner_of_user(run, rd) == me
	if not user_won:
		run["status"] = "eliminated"
		run["placement"] = PLACEMENT_BY_ROUND[rd]
		_finish_cpu_rounds(catalog, run, seed_value)
	elif rd == 2:
		run["status"] = "champion"
		run["placement"] = "champion"
	else:
		_advance(run)
	var finished: bool = run["status"] != "active"
	if finished:
		var def := find_definition(catalog, str(run["tournament_id"]))
		var rewards: Dictionary = def.get("rewards", {}).get(str(run["placement"]), {})
		var granted := FcDynastyRewards.grant(profile, catalog, rewards, "tournament_reward", "%s/%s" % [run["run_id"], run["placement"]], "reward:%s" % run["run_id"])
		if not granted.ok:
			return granted
		run["reward_txn"] = granted.data["txn"]["txn_id"]
		profile.tournament["history"].append({"run_id": run["run_id"], "tournament_id": run["tournament_id"], "name": run["name"],
			"placement": run["placement"], "reward_txn": run["reward_txn"], "rewards": FcDynastyProfile.normalize(rewards)})
		profile.tournament["active"] = {}
		return FcDynastyResult.success({"summary": summary, "run": run, "finished": true, "rewards": rewards, "shown": shown})
	return FcDynastyResult.success({"summary": summary, "run": run, "finished": false, "rewards": {}, "shown": shown})


static func _winner_of_user(run: Dictionary, rd: int) -> int:
	var me := user_index(run)
	for m in run["rounds"][rd]:
		if int(m["a"]) == me or int(m["b"]) == me:
			return int(m["winner"])
	return -1


static func _advance(run: Dictionary) -> void:
	var winners: Array = []
	for m in run["rounds"][run["round"]]:
		winners.append(int(m["winner"]))
	var next: Array = []
	for i in range(0, winners.size(), 2):
		next.append({"a": winners[i], "b": winners[i + 1], "winner": -1, "score_a": 0, "score_b": 0})
	run["rounds"].append(next)
	run["round"] += 1


static func _finish_cpu_rounds(catalog: FcDynastyCatalog, run: Dictionary, seed_value: int) -> void:
	while run["round"] < 2:
		_advance(run)
		for m_index in run["rounds"][run["round"]].size():
			_simulate_cpu_match(catalog, run, run["rounds"][run["round"]][m_index], hash("%d:r%d:m%d" % [seed_value, run["round"], m_index]))


static func _simulate_cpu_match(catalog: FcDynastyCatalog, run: Dictionary, m: Dictionary, seed_value: int) -> void:
	var ta: Dictionary = run["teams"][int(m["a"])]
	var tb: Dictionary = run["teams"][int(m["b"])]
	var a := FcDynastyMatch.build_team(ta["slots"], [], catalog, FcDynastyMatch.USER_TEAM_ID, str(ta["name"]), str(ta["abbreviation"]), 0)
	var b := FcDynastyMatch.build_team(tb["slots"], [], catalog, FcDynastyMatch.OPPONENT_TEAM_ID, str(tb["name"]), str(tb["abbreviation"]), FcDynastyMatch.OPPONENT_ID_BASE)
	var box := FcGameSimulator.new().simulate(a["team"], b["team"], FcRng.new(seed_value))
	m["score_a"] = box.scores[0]
	m["score_b"] = box.scores[1]
	m["winner"] = int(m["a"]) if box.scores[0] > box.scores[1] else int(m["b"])


## Lines describing the bracket for the screen: [{round_name, matches: [{a, b, score, winner_name, you}]}]
static func bracket_view(run: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var me := user_index(run)
	for r in run["rounds"].size():
		var rows: Array = []
		for m in run["rounds"][r]:
			var a: Dictionary = run["teams"][int(m["a"])]
			var b: Dictionary = run["teams"][int(m["b"])]
			var played: bool = int(m["winner"]) >= 0
			rows.append({"a": str(a["name"]), "b": str(b["name"]), "played": played,
				"score": "%d - %d" % [int(m["score_a"]), int(m["score_b"])] if played else "vs",
				"winner": str(run["teams"][int(m["winner"])]["name"]) if played else "",
				"you": int(m["a"]) == me or int(m["b"]) == me})
		out.append({"round_name": ROUND_NAMES[r], "matches": rows})
	return out
