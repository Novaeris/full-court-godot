class_name FcOnlineMatch
extends RefCounted
## Head-to-head play between two accounts, decided by the SERVER. A match is a record {match_id, seed, a: {account_id, name, slots, minutes},
## b: {...}} where the rosters are copied from the server-held profiles when the match is made and the seed is issued by the server. The
## result is worked out by the same deterministic simulation used for offline games, so anyone holding the record gets the identical
## score: a client's claimed result is CHECKED by re-simulating (`verify_claim`), never trusted. Pure: no network, no clock.

const RATING_FLOOR := 100


## Makes the match record from two profiles. `seed_value` must come from the server (FcOnlineMatchmaker.seed_for).
static func make(match_id: String, account_a: String, profile_a: FcDynastyProfile, account_b: String, profile_b: FcDynastyProfile, seed_value: int) -> Dictionary:
	return {"match_id": match_id, "seed": str(seed_value),
		"a": {"account_id": account_a, "name": profile_a.team_name, "abbreviation": profile_a.abbreviation, "slots": profile_a.roster.slots.duplicate(), "minutes": profile_a.roster.minutes.duplicate()},
		"b": {"account_id": account_b, "name": profile_b.team_name, "abbreviation": profile_b.abbreviation, "slots": profile_b.roster.slots.duplicate(), "minutes": profile_b.roster.minutes.duplicate()}}


## The authoritative result: {"score_a", "score_b", "winner" ("a"|"b")}. `a` is the home team. Same record and catalog always give the same result.
static func result_of(catalog: FcDynastyCatalog, record: Dictionary) -> Dictionary:
	var a: Dictionary = record["a"]
	var b: Dictionary = record["b"]
	var team_a := FcDynastyMatch.build_team(a["slots"], a["minutes"], catalog, FcDynastyMatch.USER_TEAM_ID, str(a["name"]), str(a["abbreviation"]), 0)
	var team_b := FcDynastyMatch.build_team(b["slots"], b["minutes"], catalog, FcDynastyMatch.OPPONENT_TEAM_ID, str(b["name"]), str(b["abbreviation"]), FcDynastyMatch.OPPONENT_ID_BASE)
	var played := FcDynastyMatch.simulate(team_a, team_b, int(str(record["seed"])), true)
	var box: FcBoxScore = played["box"]
	return {"score_a": box.scores[0], "score_b": box.scores[1], "winner": "a" if box.scores[0] > box.scores[1] else "b"}


## Checks a result a client claims. Returns {"valid": bool, "result": the real result}.
static func verify_claim(catalog: FcDynastyCatalog, record: Dictionary, claimed: Dictionary) -> Dictionary:
	var real := result_of(catalog, record)
	var valid := int(claimed.get("score_a", -1)) == int(real["score_a"]) and int(claimed.get("score_b", -1)) == int(real["score_b"])
	return {"valid": valid, "result": real}


## The ladder rating changes for both sides: {"a": delta, "b": delta}. Elo from FcDynastyLadder; equal and opposite.
static func rating_changes(rating_a: int, rating_b: int, a_won: bool) -> Dictionary:
	var da := FcDynastyLadder.delta_for(rating_a, rating_b, a_won)
	return {"a": da, "b": -da}
