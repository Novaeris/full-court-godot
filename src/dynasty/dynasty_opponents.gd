class_name FcDynastyOpponents
extends RefCounted
## Computer opponents. A team is built from the release's own cards by picking, for every roster slot, a different player
## whose card overall is close to the wanted level (with seeded jitter so opponents differ). Deterministic from the seed.
## Teams published in a tournament definition (explicit card_ids) are used as written; only a team given just a rating is built here.


## Returns Array of 13 card ids (starters first, positions respected).
static func generate(catalog: FcDynastyCatalog, target_overall: int, seed_value: int) -> Array[String]:
	var rng := FcRng.new(seed_value)
	var pool: Array[Dictionary] = []
	for id in catalog.card_ids():
		pool.append(catalog.view(id))
	var out: Array[String] = []
	out.resize(FcDynastyRoster.SIZE)
	out.fill("")
	var used := {}
	# starters first (position-eligible), then bench: bench cards sit a little below the starters
	for slot in FcDynastyRoster.SIZE:
		var want := float(target_overall) - (0.0 if slot < FcDynastyRoster.STARTERS else 4.0 + 1.5 * (slot - FcDynastyRoster.STARTERS))
		var best := ""
		var best_score := INF
		for v in pool:
			if used.has(v["player_id"]) or not FcDynastyLineup.eligible(v, slot):
				continue
			var score := absf(float(v["overall"]) - want) + rng.range_float(0.0, 3.0)
			if score < best_score:
				best_score = score
				best = v["card_id"]
		if best == "":
			# the release is small: relax the position rule rather than field no one
			for v in pool:
				if used.has(v["player_id"]):
					continue
				var score2 := absf(float(v["overall"]) - want) + rng.range_float(0.0, 3.0)
				if score2 < best_score:
					best_score = score2
					best = v["card_id"]
		out[slot] = best
		if best != "":
			used[catalog.view(best)["player_id"]] = true
	return out


## The slots and display name of a tournament team definition (explicit cards, else built from `rating`).
static func tournament_team(catalog: FcDynastyCatalog, team_def: Dictionary, seed_value: int) -> Dictionary:
	var slots: Array[String] = []
	if team_def.get("card_ids") is Array:
		for id in team_def["card_ids"]:
			slots.append(str(id))
	else:
		slots = generate(catalog, int(team_def.get("rating", 60)), seed_value)
	var abbr := str(team_def.get("abbreviation", str(team_def.get("name", "CPU")).substr(0, 3).to_upper()))
	return {"name": str(team_def.get("name", "CPU")), "abbreviation": abbr, "slots": slots}
