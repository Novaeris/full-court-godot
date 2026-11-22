class_name FcDynastyLadder
extends RefCounted
## The Dynasty ranked ladder (data/dynasty/ladder.json): a rating changed by quick games, a tier from the rating, and a rank among a
## fixed field of computer players made from the profile seed (so the rank is real but fully offline and reproducible). A new Dynasty
## season softly resets the rating and pays the season-end credits of the tier reached; the first time a tier is reached in a season it
## pays that tier's credits once. Everything stored is whole numbers and text in `profile.ladder`; money moves only through
## FcDynastyEconomy (with request ids, so a repeat never pays twice). Pure and seeded; no randomness at play time.
##
## profile.ladder = {rating, peak, games, wins, season_id, reached: [tier ids paid this season], history: [{season_id, rating, peak, tier}]}

static var _cache: Dictionary = {}


static func rules() -> Dictionary:
	if _cache.is_empty():
		var file := FileAccess.open("res://data/dynasty/ladder.json", FileAccess.READ)
		var parsed = FcChecks.parse_json(file.get_as_text()) if file != null else null
		_cache = parsed if parsed is Dictionary else {}
	return _cache


static func _int(key: String, fallback: int) -> int:
	return int(rules().get(key, fallback))


static func start_rating() -> int:
	return _int("start_rating", 1000)


## A ladder record for a profile that has never played ranked (also what an older profile is migrated to).
static func fresh() -> Dictionary:
	return {"rating": start_rating(), "peak": start_rating(), "games": 0, "wins": 0, "season_id": "", "reached": [], "history": []}


static func tiers() -> Array:
	return rules().get("tiers", [])


## The tier (a row of the data) a rating belongs to.
static func tier_of(rating: int) -> Dictionary:
	var out: Dictionary = {}
	for t in tiers():
		if rating >= int(t["min"]):
			out = t
	return out


## The next tier above `rating`, or {} at the top.
static func next_tier(rating: int) -> Dictionary:
	for t in tiers():
		if int(t["min"]) > rating:
			return t
	return {}


## Rating points won or lost: Elo with the data's k. `won` is the real result; the opponent's rating decides how likely it was.
static func delta_for(rating: int, opponent_rating: int, won: bool) -> int:
	var expected := 1.0 / (1.0 + pow(10.0, float(opponent_rating - rating) / 400.0))
	return roundi(float(_int("k_factor", 24)) * ((1.0 if won else 0.0) - expected))


## The computer field: [{name, rating}] best first, fixed for a profile seed.
static func field(profile: FcDynastyProfile) -> Array:
	var spec: Dictionary = rules().get("field", {})
	var rng := FcRng.new(hash("%d:ladder-field" % profile.rng_seed))
	var firsts: Array = spec.get("names_first", ["CPU"])
	var lasts: Array = spec.get("names_last", ["Team"])
	var out: Array = []
	var seen := {}
	for i in int(spec.get("size", 99)):
		var name := "%s %s" % [firsts[rng.range_int(0, firsts.size() - 1)], lasts[rng.range_int(0, lasts.size() - 1)]]
		if seen.has(name):
			name = "%s %d" % [name, i + 1]
		seen[name] = true
		# a bell-shaped spread: the average of three draws
		var bell := (rng.range_float(-1.0, 1.0) + rng.range_float(-1.0, 1.0) + rng.range_float(-1.0, 1.0)) / 3.0
		out.append({"name": name, "rating": maxi(_int("rating_floor", 100), roundi(float(spec.get("mean", 1000)) + bell * float(spec.get("spread", 220)) * 1.5))})
	out.sort_custom(func(a, b) -> bool: return a["rating"] > b["rating"] if a["rating"] != b["rating"] else str(a["name"]) < str(b["name"]))
	return out


## The user's rank among the field (1 = best): one plus the number of computer players rated strictly higher.
static func rank(profile: FcDynastyProfile) -> int:
	var r := int(profile.ladder["rating"])
	var above := 0
	for f in field(profile):
		if int(f["rating"]) > r:
			above += 1
	return above + 1


## Starts a new ladder season when the active Dynasty season changed: the rating moves part of the way back to the start, the season
## just finished is written to the history and its tier's season credits are paid (once, by request id). Returns the credits paid.
static func roll_season(profile: FcDynastyProfile, season_id: String) -> int:
	var ladder := profile.ladder
	if str(ladder.get("season_id", "")) == season_id:
		return 0
	var paid := 0
	var previous := str(ladder.get("season_id", ""))
	if previous != "" and int(ladder["games"]) > 0:
		var tier := tier_of(int(ladder["rating"]))
		var credits := int(tier.get("season_credits", 0))
		if credits > 0:
			var r := FcDynastyEconomy.apply(profile, "ladder_season", previous, {"credits": credits}, [], "ladder_season:%s" % previous, "Ranked season %s: %s" % [previous, tier.get("name", "")])
			if r.ok and not bool(r.data.get("replayed", false)):
				paid = credits
		(ladder["history"] as Array).append({"season_id": previous, "rating": int(ladder["rating"]), "peak": int(ladder["peak"]), "tier": str(tier.get("id", ""))})
		while (ladder["history"] as Array).size() > _int("history_limit", 20):
			(ladder["history"] as Array).pop_front()
		var start := start_rating()
		ladder["rating"] = start + roundi((int(ladder["rating"]) - start) * float(_int("reset_keep_percent", 50)) / 100.0)
		ladder["peak"] = int(ladder["rating"])
	ladder["season_id"] = season_id
	ladder["reached"] = []
	return paid


## Folds one finished quick game into the ladder. `offset` is the opponent level's overall offset (easy -8, even 0, hard 6 by default).
## Returns {"delta", "rating", "tier", "tier_up" (bool), "reward" (credits for reaching a new tier), "season_reward", "rank"}.
static func on_game(profile: FcDynastyProfile, catalog: FcDynastyCatalog, won: bool, offset: int) -> Dictionary:
	var season_reward := roll_season(profile, catalog.active_season_id())
	var ladder := profile.ladder
	var before := int(ladder["rating"])
	var opponent := before + offset * _int("opponent_rating_per_offset", 10)
	var delta := delta_for(before, opponent, won)
	var after := maxi(_int("rating_floor", 100), before + delta)
	ladder["rating"] = after
	ladder["peak"] = maxi(int(ladder["peak"]), after)
	ladder["games"] = int(ladder["games"]) + 1
	ladder["wins"] = int(ladder["wins"]) + (1 if won else 0)
	var settled := _settle(profile, before, after)
	return {"delta": after - before, "rating": after, "tier": settled["tier"], "tier_up": settled["tier_up"], "reward": settled["reward"], "season_reward": season_reward, "rank": rank(profile)}


## A finished tournament run changes the rating by the data's bonus for the placement (champion, finalist, semifinal, quarterfinal), so
## tournaments matter for the ranking too. Returns the same dictionary as on_game ("delta" is the bonus).
static func on_tournament(profile: FcDynastyProfile, catalog: FcDynastyCatalog, placement: String) -> Dictionary:
	var season_reward := roll_season(profile, catalog.active_season_id())
	var ladder := profile.ladder
	var before := int(ladder["rating"])
	var bonus := int((rules().get("tournament_bonus", {}) as Dictionary).get(placement, 0))
	var after := maxi(_int("rating_floor", 100), before + bonus)
	ladder["rating"] = after
	ladder["peak"] = maxi(int(ladder["peak"]), after)
	var settled := _settle(profile, before, after)
	return {"delta": after - before, "rating": after, "tier": settled["tier"], "tier_up": settled["tier_up"], "reward": settled["reward"], "season_reward": season_reward, "rank": rank(profile)}


## Marks every tier at or below the new rating as reached and pays the credits of tiers the rating just climbed into. Returns {tier, tier_up, reward}.
static func _settle(profile: FcDynastyProfile, before: int, after: int) -> Dictionary:
	var ladder := profile.ladder
	var tier := tier_of(after)
	var reward := 0
	var tier_up := false
	var reached: Array = ladder["reached"]
	# every tier at or below the new rating counts as reached (a big jump skips none of the credits); only a tier the rating just climbed into pays
	for t in tiers():
		if int(t["min"]) <= after and not reached.has(str(t["id"])):
			reached.append(str(t["id"]))
			var credits := int(t.get("reach_credits", 0))
			if credits > 0 and int(t["min"]) > before:
				var r := FcDynastyEconomy.apply(profile, "ladder_tier", "%s:%s" % [ladder["season_id"], t["id"]], {"credits": credits}, [], "ladder_tier:%s:%s" % [ladder["season_id"], t["id"]], "Reached %s" % t["name"])
				if r.ok and not bool(r.data.get("replayed", false)):
					reward += credits
					tier_up = true
	return {"tier": str(tier.get("name", "")), "tier_up": tier_up, "reward": reward}


## What the ladder screen shows: {rating, peak, games, wins, tier, next_tier, to_next, rank, field_size, standings: [{rank, name, rating, you}], history}.
static func view(profile: FcDynastyProfile) -> Dictionary:
	var ladder := profile.ladder
	var rating := int(ladder["rating"])
	var tier := tier_of(rating)
	var nxt := next_tier(rating)
	var rows: Array = []
	var me := {"name": profile.team_name, "rating": rating, "you": true}
	var combined: Array = []
	for f in field(profile):
		combined.append({"name": f["name"], "rating": f["rating"], "you": false})
	combined.append(me)
	combined.sort_custom(func(a, b) -> bool: return a["rating"] > b["rating"] if a["rating"] != b["rating"] else bool(a["you"]) and not bool(b["you"]))
	var my_rank := 1
	for i in combined.size():
		var row: Dictionary = combined[i]
		row["rank"] = i + 1
		if bool(row["you"]):
			my_rank = i + 1
	rows = combined.slice(0, 5)
	if my_rank > 5:
		rows.append(me)
	return {"rating": rating, "peak": int(ladder["peak"]), "games": int(ladder["games"]), "wins": int(ladder["wins"]), "tier": str(tier.get("name", "")),
		"next_tier": str(nxt.get("name", "")), "to_next": int(nxt["min"]) - rating if not nxt.is_empty() else 0, "rank": my_rank,
		"field_size": combined.size(), "standings": rows, "history": (ladder["history"] as Array).duplicate(true)}
