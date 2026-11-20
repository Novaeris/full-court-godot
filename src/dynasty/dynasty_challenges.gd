class_name FcDynastyChallenges
extends RefCounted
## Challenge progress and reward claims. Progress is evaluated from real game summaries (and the collection for collection
## objectives); a completed challenge's reward is claimable exactly once (the claim is recorded and repeated requests are
## answered from the ledger).


static func state_of(profile: FcDynastyProfile, challenge_id: String) -> Dictionary:
	var s: Dictionary = profile.challenges.get(challenge_id, {})
	return {"progress": int(s.get("progress", 0)), "done": bool(s.get("completed", false)),
		"claimed": bool(s.get("claimed", false)), "claim_txn": str(s.get("claim_txn", ""))}


static func _store(profile: FcDynastyProfile, challenge_id: String, state: Dictionary) -> void:
	var old: Dictionary = profile.challenges.get(challenge_id, {})
	profile.challenges[challenge_id] = {"progress": int(state["progress"]), "completed": bool(state["done"]),
		"claimed": bool(old.get("claimed", false)), "claim_txn": str(old.get("claim_txn", ""))}


## Whether the lineup that played satisfies the challenge's roster restrictions.
static func restrictions_met(def: Dictionary, starter_card_ids: Array, catalog: FcDynastyCatalog) -> bool:
	var r: Dictionary = def.get("restrictions", {})
	if r.is_empty():
		return true
	for id in starter_card_ids:
		var v := catalog.view(str(id))
		if v.is_empty():
			return false
		if r.has("max_rarity") and FcDynastyContentRules.rarity_rank(str(v["rarity"])) > FcDynastyContentRules.rarity_rank(str(r["max_rarity"])):
			return false
		if r.has("max_overall") and int(v["overall"]) > int(r["max_overall"]):
			return false
		if r.has("min_overall") and int(v["overall"]) < int(r["min_overall"]):
			return false
	return true


## Folds a finished game into every unfinished challenge. Returns the ids completed by this game.
static func on_game(profile: FcDynastyProfile, catalog: FcDynastyCatalog, summary: Dictionary) -> Array[String]:
	var done: Array[String] = []
	var starters: Array = []
	for line in summary["players"]:
		if bool(line["started"]):
			starters.append(str(line["card_id"]))
	for id in catalog.challenges():
		var def: Dictionary = catalog.challenges()[id]
		var state := state_of(profile, str(id))
		if state["done"] or str(def["objective"]["type"]) == "collection":
			continue
		if not restrictions_met(def, starters, catalog):
			continue
		FcDynastyObjective.update_game(state, def["objective"], summary)
		_store(profile, str(id), state)
		if state["done"]:
			done.append(str(id))
	return done


## Re-evaluates collection challenges (call after anything that changes the collection). Returns newly completed ids.
static func refresh_collection(profile: FcDynastyProfile, catalog: FcDynastyCatalog) -> Array[String]:
	var done: Array[String] = []
	for id in catalog.challenges():
		var def: Dictionary = catalog.challenges()[id]
		if str(def["objective"]["type"]) != "collection":
			continue
		var state := state_of(profile, str(id))
		if state["done"]:
			continue
		FcDynastyObjective.update_collection(state, def["objective"], profile, catalog)
		_store(profile, str(id), state)
		if state["done"]:
			done.append(str(id))
	return done


## Claims the reward of a completed challenge. Works once; a second claim (or a repeated request) grants nothing.
static func claim(profile: FcDynastyProfile, catalog: FcDynastyCatalog, challenge_id: String) -> FcDynastyResult:
	var def: Dictionary = catalog.challenges().get(challenge_id, {})
	if def.is_empty():
		return FcDynastyResult.failure("unknown_challenge", "That challenge is not in the current content release.")
	var state := state_of(profile, challenge_id)
	if state["claimed"]:
		return FcDynastyResult.failure("already_claimed", "You already claimed this reward.")
	if not state["done"]:
		return FcDynastyResult.failure("not_complete", "This challenge is not complete yet.")
	var granted := FcDynastyRewards.grant(profile, catalog, def.get("rewards", {}), "challenge_reward", challenge_id, "claim:challenge:%s" % challenge_id)
	if not granted.ok:
		return granted
	profile.challenges[challenge_id]["claimed"] = true
	profile.challenges[challenge_id]["claim_txn"] = granted.data["txn"]["txn_id"]
	FcDynastyChallenges.refresh_collection(profile, catalog)
	return granted


## Rows for the challenge hub, grouped by category order then title.
static func listing(profile: FcDynastyProfile, catalog: FcDynastyCatalog) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in catalog.challenges():
		var def: Dictionary = catalog.challenges()[id]
		var s := state_of(profile, str(id))
		out.append({"id": str(id), "title": str(def.get("title", id)), "description": str(def.get("description", "")),
			"category": str(def["category"]), "target": FcDynastyObjective.target_of(def["objective"]),
			"progress": s["progress"], "completed": s["done"], "claimed": s["claimed"],
			"rewards": def.get("rewards", {}), "restrictions": def.get("restrictions", {}), "season_points": int(def.get("season_points", 0))})
	var order := FcDynastyContentRules.CHALLENGE_CATEGORIES
	out.sort_custom(func(a, b): return [order.find(a["category"]), a["title"]] < [order.find(b["category"]), b["title"]])
	return out


## Plain-language rewards and restrictions for display.
static func rewards_text(rewards: Dictionary) -> String:
	var parts: Array[String] = []
	for c in FcDynastyConfig.CURRENCIES:
		if int(rewards.get(c, 0)) > 0:
			parts.append("%d %s" % [int(rewards[c]), c])
	if not rewards.get("card_ids", []).is_empty():
		parts.append("%d card(s)" % rewards["card_ids"].size())
	if not rewards.get("pack_ids", []).is_empty():
		parts.append("%d pack(s)" % rewards["pack_ids"].size())
	return ", ".join(parts) if not parts.is_empty() else "no reward"


static func restrictions_text(r: Dictionary) -> String:
	var parts: Array[String] = []
	if r.has("max_rarity"):
		parts.append("starters no higher than %s" % str(r["max_rarity"]))
	if r.has("max_overall"):
		parts.append("starters at most %d overall" % int(r["max_overall"]))
	if r.has("min_overall"):
		parts.append("starters at least %d overall" % int(r["min_overall"]))
	return ", ".join(parts)
