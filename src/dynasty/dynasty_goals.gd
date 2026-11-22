class_name FcDynastyGoals
extends RefCounted
## Dynasty collection goals (data/dynasty/goals.json): long-term targets about the collection and how far it has been mastered. Progress
## is DERIVED from the profile and the loaded release every time (never stored), so it cannot drift; the only stored part is which goals
## were claimed (`profile.goals["claimed"]`). A claim pays through FcDynastyEconomy with a request id, so a repeat never pays twice.
## Goals describe cards by filters (rarity, position, team...), never by id, so a new content release needs no change here.

static var _cache: Dictionary = {}


static func rules() -> Dictionary:
	if _cache.is_empty():
		var file := FileAccess.open("res://data/dynasty/goals.json", FileAccess.READ)
		var parsed = FcChecks.parse_json(file.get_as_text()) if file != null else null
		_cache = parsed if parsed is Dictionary else {}
	return _cache


static func definitions() -> Array:
	return rules().get("goals", [])


## Problems in the goal data (empty when sound): unique ids, a known type, a positive need, a reward of known currencies.
static func validate() -> Array:
	var problems: Array = []
	var ids := {}
	for g in definitions():
		var id := str(g.get("id", ""))
		if id == "" or ids.has(id):
			problems.append("goal id %s is missing or repeated" % id)
		ids[id] = true
		if not ["owned", "positions", "teams", "mastery_card", "mastery_total"].has(str(g.get("type", ""))):
			problems.append("%s: unknown type" % id)
		if int(g.get("need", 0)) < 1:
			problems.append("%s: need must be at least 1" % id)
		var reward: Dictionary = g.get("reward", {})
		if reward.is_empty():
			problems.append("%s: no reward" % id)
		for c in reward:
			if not FcDynastyConfig.CURRENCIES.has(str(c)) or int(reward[c]) < 1:
				problems.append("%s: bad reward %s" % [id, c])
	return problems


## How far the profile is toward one goal: {"have", "need", "done", "claimed"}.
static func progress(profile: FcDynastyProfile, catalog: FcDynastyCatalog, goal: Dictionary) -> Dictionary:
	var need := int(goal.get("need", 1))
	var have := 0
	match str(goal.get("type", "")):
		"owned":
			var filters: Dictionary = (goal.get("filter", {}) as Dictionary).duplicate()
			filters["ownership"] = "owned"
			have = FcCollectionQuery.rows(profile, catalog, filters).size()
		"positions":
			var seen := {}
			for id in profile.cards:
				var v := catalog.owned_view(str(id), profile.cards[id])
				if str(v["position"]) != "":
					seen[str(v["position"])] = true
			have = seen.size()
		"teams":
			var teams := {}
			for id in profile.cards:
				var v := catalog.owned_view(str(id), profile.cards[id])
				if str(v["team"]) != "":
					teams[str(v["team"])] = true
			have = teams.size()
		"mastery_card":
			for id in profile.cards:
				have = maxi(have, int(profile.cards[id].get("mastery", 0)))
		"mastery_total":
			for id in profile.cards:
				have += int(profile.cards[id].get("mastery", 0))
	return {"have": mini(have, need), "need": need, "done": have >= need, "claimed": (profile.goals.get("claimed", []) as Array).has(str(goal["id"]))}


## Every goal with its progress: [{id, name, text, reward, have, need, done, claimed}].
static func listing(profile: FcDynastyProfile, catalog: FcDynastyCatalog) -> Array:
	var out: Array = []
	for g in definitions():
		var p := progress(profile, catalog, g)
		out.append({"id": str(g["id"]), "name": str(g["name"]), "text": str(g.get("text", "")), "reward": (g["reward"] as Dictionary).duplicate(),
			"have": p["have"], "need": p["need"], "done": p["done"], "claimed": p["claimed"]})
	return out


## Claims a finished goal: pays its reward once. Failure codes: unknown_goal, not_done, already_claimed.
static func claim(profile: FcDynastyProfile, catalog: FcDynastyCatalog, goal_id: String) -> FcDynastyResult:
	var goal := {}
	for g in definitions():
		if str(g["id"]) == goal_id:
			goal = g
	if goal.is_empty():
		return FcDynastyResult.failure("unknown_goal", "That goal does not exist.")
	var p := progress(profile, catalog, goal)
	if bool(p["claimed"]):
		return FcDynastyResult.failure("already_claimed", "You already claimed this goal.")
	if not bool(p["done"]):
		return FcDynastyResult.failure("not_done", "This goal is not finished yet (%d of %d)." % [int(p["have"]), int(p["need"])])
	var paid := FcDynastyEconomy.apply(profile, "goal_reward", goal_id, (goal["reward"] as Dictionary).duplicate(), [], "goal:%s" % goal_id, str(goal["name"]))
	if not paid.ok:
		return paid
	(profile.goals["claimed"] as Array).append(goal_id)   # also when the payment was a replay: the goal is then marked, never paid twice
	return FcDynastyResult.success({"txn": paid.data["txn"], "reward": (goal["reward"] as Dictionary).duplicate()})
