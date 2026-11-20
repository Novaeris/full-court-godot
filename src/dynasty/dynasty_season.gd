class_name FcDynastySeason
extends RefCounted
## Season progress for the release's active season (configuration comes from Creator Studio). Season points are DERIVED, never
## stored: points = the season points of completed seasonal challenges + the points of completed season objectives. So
## progress cannot drift from what the player actually did. Claimed milestones are the only stored part.
##
## A new season (a new release's active season) starts with fresh points but never touches the collection.


static func _state(profile: FcDynastyProfile, season_id: String) -> Dictionary:
	if not profile.seasons.has(season_id):
		profile.seasons[season_id] = {"claimed_milestones": [], "objectives": {}}
	return profile.seasons[season_id]


static func objective_state(profile: FcDynastyProfile, season_id: String, objective_id: String) -> Dictionary:
	var s: Dictionary = profile.seasons.get(season_id, {}).get("objectives", {}).get(objective_id, {})
	return {"progress": int(s.get("progress", 0)), "done": bool(s.get("done", false))}


## Season points earned so far.
static func points(profile: FcDynastyProfile, catalog: FcDynastyCatalog, season_id: String) -> int:
	var def := catalog.season(season_id)
	var total := 0
	for cid in def.get("challenge_ids", []):
		if FcDynastyChallenges.state_of(profile, str(cid))["done"]:
			total += int(catalog.challenges().get(str(cid), {}).get("season_points", 0))
	for o in def.get("objectives", []):
		if objective_state(profile, season_id, str(o["id"]))["done"]:
			total += int(o["points"])
	return total


## Folds a finished game into the active season's objectives. Returns ids of objectives completed by it.
static func on_game(profile: FcDynastyProfile, catalog: FcDynastyCatalog, summary: Dictionary) -> Array[String]:
	return _update(profile, catalog, summary, false)


static func refresh_collection(profile: FcDynastyProfile, catalog: FcDynastyCatalog) -> Array[String]:
	return _update(profile, catalog, {}, true)


static func _update(profile: FcDynastyProfile, catalog: FcDynastyCatalog, summary: Dictionary, collection: bool) -> Array[String]:
	var done: Array[String] = []
	var sid := catalog.active_season_id()
	if sid == "":
		return done
	for o in catalog.season(sid).get("objectives", []):
		var is_collection := str(o["objective"]["type"]) == "collection"
		if is_collection != collection:
			continue
		var state := objective_state(profile, sid, str(o["id"]))
		if state["done"]:
			continue
		if collection:
			FcDynastyObjective.update_collection(state, o["objective"], profile, catalog)
		else:
			FcDynastyObjective.update_game(state, o["objective"], summary)
		_state(profile, sid)["objectives"][str(o["id"])] = state
		if state["done"]:
			done.append(str(o["id"]))
	return done


static func milestones(profile: FcDynastyProfile, catalog: FcDynastyCatalog, season_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pts := points(profile, catalog, season_id)
	var claimed: Array = profile.seasons.get(season_id, {}).get("claimed_milestones", [])
	for m in catalog.season(season_id).get("milestones", []):
		out.append({"id": str(m["id"]), "name": str(m.get("name", m["id"])), "points": int(m["points"]),
			"reached": pts >= int(m["points"]), "claimed": claimed.has(str(m["id"])), "rewards": m.get("rewards", {})})
	out.sort_custom(func(a, b): return a["points"] < b["points"])
	return out


static func claim_milestone(profile: FcDynastyProfile, catalog: FcDynastyCatalog, season_id: String, milestone_id: String) -> FcDynastyResult:
	for m in milestones(profile, catalog, season_id):
		if m["id"] != milestone_id:
			continue
		if m["claimed"]:
			return FcDynastyResult.failure("already_claimed", "You already claimed this milestone.")
		if not m["reached"]:
			return FcDynastyResult.failure("not_reached", "This milestone needs %d season points." % m["points"])
		var granted := FcDynastyRewards.grant(profile, catalog, m["rewards"], "milestone_reward", "%s/%s" % [season_id, milestone_id],
			"claim:milestone:%s:%s" % [season_id, milestone_id])
		if not granted.ok:
			return granted
		_state(profile, season_id)["claimed_milestones"].append(milestone_id)
		return granted
	return FcDynastyResult.failure("unknown_milestone", "That milestone is not in this season.")


## Everything the Season screen shows.
static func overview(profile: FcDynastyProfile, catalog: FcDynastyCatalog) -> Dictionary:
	var sid := catalog.active_season_id()
	if sid == "":
		return {}
	var def := catalog.season(sid)
	var objectives: Array = []
	for o in def.get("objectives", []):
		var s := objective_state(profile, sid, str(o["id"]))
		objectives.append({"id": str(o["id"]), "title": str(o.get("title", o["id"])), "points": int(o["points"]),
			"progress": s["progress"], "target": FcDynastyObjective.target_of(o["objective"]), "done": s["done"]})
	var pts := points(profile, catalog, sid)
	var ms := milestones(profile, catalog, sid)
	var top := 0
	for m in ms:
		top = maxi(top, m["points"])
	return {"season_id": sid, "name": str(def.get("name", sid)), "description": str(def.get("description", "")),
		"points": pts, "top_milestone": top, "objectives": objectives, "milestones": ms,
		"challenge_ids": def.get("challenge_ids", []), "tournament_ids": tournament_ids(def)}


static func tournament_ids(season_def: Dictionary) -> Array:
	var out: Array = []
	for t in season_def.get("tournaments", []):
		out.append(str(t["tournament_id"]))
	return out
