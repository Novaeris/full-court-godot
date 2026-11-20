class_name FcDynastyProgress
extends RefCounted
## Records a finished game into the profile: record, per-card statistics, history and the game's credit reward.


## `reward_percent` scales the configured win/loss credits (0 = no game reward, e.g. tournament games pay by placement).
static func record_game(profile: FcDynastyProfile, catalog: FcDynastyCatalog, summary: Dictionary, kind: String,
		reward_percent: int = 100) -> FcDynastyResult:
	profile.game_counter += 1
	var n := profile.game_counter
	var won := bool(summary["won"])
	var rec := profile.record
	rec["games"] += 1
	rec["wins"] += 1 if won else 0
	rec["losses"] += 0 if won else 1
	rec["points_for"] += int(summary["score_for"])
	rec["points_against"] += int(summary["score_against"])
	if won:
		rec["streak"] = rec["streak"] + 1 if rec["streak"] > 0 else 1
	else:
		rec["streak"] = rec["streak"] - 1 if rec["streak"] < 0 else -1
	for line in summary["players"]:
		var id := str(line["card_id"])
		if id == "" or int(line["seconds"]) <= 0:
			continue
		var s: Dictionary = profile.card_stats.get(id, {"games": 0, "points": 0, "rebounds": 0, "assists": 0, "steals": 0, "blocks": 0, "threes": 0})
		s["games"] += 1
		for key in ["points", "rebounds", "assists", "steals", "blocks", "threes"]:
			s[key] += int(line[key])
		profile.card_stats[id] = s
	profile.game_history.append({"n": n, "kind": kind, "won": won, "score_for": int(summary["score_for"]),
		"score_against": int(summary["score_against"]), "opponent": str(summary["opponent"])})
	var limit := catalog.config.get_int(["history_limit"], 25)
	while profile.game_history.size() > limit:
		profile.game_history.pop_front()
	var reward := catalog.config.game_reward(won) * reward_percent / 100
	var paid := FcDynastyEconomy.apply(profile, "game_reward", "game_%d" % n, {"credits": reward} if reward > 0 else {}, [], "game:%d" % n)
	if not paid.ok:
		return paid
	if bool(paid.data.get("replayed", false)):
		return FcDynastyResult.failure("duplicate_request", "This game was already recorded.")
	return FcDynastyResult.success({"reward": reward, "txn": paid.data["txn"], "game_number": n})
