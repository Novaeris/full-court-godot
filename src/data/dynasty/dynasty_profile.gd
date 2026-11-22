class_name FcDynastyProfile
extends RefCounted
## Everything a Dynasty Mode player owns and has done. Saved as one file (FcDynastyStore). It stores ONLY stable ids and
## counters: what a card IS always comes from the loaded content release; the small `snapshot` kept with each owned card
## exists so a card missing from a later release can still be shown honestly (never to change gameplay).
##
## State changes go through the domain services (src/dynasty), never straight from a screen, so every change is checked,
## recorded in the ledger and saved atomically.

const SCHEMA := 1

var profile_id: String = ""
var team_name: String = "My Dynasty"
var abbreviation: String = "DYN"
## Team colour as a hex string (no alpha), chosen at creation.
var color_hex: String = "f58c29"
## Seed for all pack and opponent randomness; saved as text (rule 6: 64-bit numbers are text).
var rng_seed: int = 0
## Content release the profile was created with and every release seen since (provenance, oldest first).
var created_release_id: String = ""
var release_history: Array = []

var balances: Dictionary = {"credits": 0, "tokens": 0, "shards": 0}
## card_id -> {card_id, quantity, revision, snapshot{}, first_txn, mastery}
var cards: Dictionary = {}
var ledger: Array = []
var txn_counter: int = 0
## request_id -> txn_id: a repeated request is answered from here and never applied twice.
var processed_requests: Dictionary = {}
var pack_openings: Array = []
var opening_counter: int = 0
## pack_id -> packs opened since its last pity hit.
var pity: Dictionary = {}
var roster := FcDynastyRoster.new()
var record: Dictionary = {"games": 0, "wins": 0, "losses": 0, "points_for": 0, "points_against": 0, "streak": 0}
## card_id -> {games, points, rebounds, assists, steals, blocks, threes}
var card_stats: Dictionary = {}
var game_counter: int = 0
var game_history: Array = []
## The last few games' replays, oldest first: {n, label, box, events}. Kept so a game can be watched again after the session (the
## number kept is the config's replay_limit). Display only: no rule reads them.
var replays: Array = []
## challenge_id -> {progress, completed, claimed, claim_txn}
var challenges: Dictionary = {}
## season_id -> {points, claimed_milestones: [], objectives: {id: {progress, done}}}
var seasons: Dictionary = {}
## {"active": {} or a run, "history": [], "run_counter": int}  (see FcDynastyTournament)
var tournament: Dictionary = {"active": {}, "history": [], "run_counter": 0}
## The ranked ladder (FcDynastyLadder): {rating, peak, games, wins, season_id, reached, history}.
var ladder: Dictionary = FcDynastyLadder.fresh()
## Collection goals already claimed (FcDynastyGoals): {"claimed": [goal ids]}. Progress itself is derived, never stored.
var goals: Dictionary = {"claimed": []}
## Set once the starter collection has been granted.
var starter_granted: bool = false


static func create(team: String, abbr: String, seed_value: int, release_id: String, color: String = "f58c29") -> FcDynastyProfile:
	var p := FcDynastyProfile.new()
	p.team_name = team.strip_edges()
	p.abbreviation = abbr.strip_edges().to_upper()
	p.rng_seed = seed_value
	p.color_hex = color
	p.created_release_id = release_id
	p.release_history = [release_id] if release_id != "" else []
	p.profile_id = "fcd_%016x" % (hash("%d:%s" % [seed_value, team]) & 0x7FFFFFFFFFFFFFFF)
	return p


func balance(currency: String) -> int:
	return int(balances.get(currency, 0))


func quantity_of(card_id: String) -> int:
	return int(cards.get(card_id, {}).get("quantity", 0))


## How many different cards are owned.
func unique_owned() -> int:
	return cards.size()


func owned_card_ids() -> Array[String]:
	var out: Array[String] = []
	for id in cards:
		out.append(str(id))
	out.sort()
	return out


## Notes that a release was loaded with this profile (kept once, in order).
func note_release(release_id: String) -> void:
	if release_id != "" and (release_history.is_empty() or release_history[release_history.size() - 1] != release_id):
		release_history.append(release_id)


func validate() -> Array[String]:
	var errors: Array[String] = []
	if team_name.is_empty() or team_name.length() > 40:
		errors.append("team name must be 1-40 characters")
	for c in FcDynastyConfig.CURRENCIES:
		if balance(c) < 0:
			errors.append("%s balance is negative" % c)
	for id in cards:
		if quantity_of(str(id)) < 1:
			errors.append("card %s has no copies" % id)
	if int(ladder.get("rating", 0)) < 0 or int(ladder.get("games", 0)) < 0:
		errors.append("the ladder rating and games cannot be negative")
	for slot in roster.slots:
		if str(slot) != "" and not cards.has(str(slot)):
			errors.append("roster holds %s, which is not owned" % slot)
	return errors


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA,
		"profile_id": profile_id, "team_name": team_name, "abbreviation": abbreviation, "color_hex": color_hex,
		"rng_seed": str(rng_seed),
		"created_release_id": created_release_id, "release_history": release_history.duplicate(),
		"balances": balances.duplicate(),
		"cards": cards.duplicate(true),
		"ledger": ledger.duplicate(true), "txn_counter": txn_counter,
		"processed_requests": processed_requests.duplicate(),
		"pack_openings": pack_openings.duplicate(true), "opening_counter": opening_counter,
		"pity": pity.duplicate(),
		"roster": roster.to_dict(),
		"record": record.duplicate(), "card_stats": card_stats.duplicate(true),
		"game_counter": game_counter, "game_history": game_history.duplicate(true), "replays": replays.duplicate(true),
		"challenges": challenges.duplicate(true), "seasons": seasons.duplicate(true),
		"tournament": tournament.duplicate(true), "starter_granted": starter_granted, "ladder": ladder.duplicate(true), "goals": goals.duplicate(true),
	}


static func from_dict(d: Dictionary) -> FcDynastyProfile:
	var p := FcDynastyProfile.new()
	p.profile_id = str(d.get("profile_id", ""))
	p.team_name = str(d.get("team_name", "My Dynasty"))
	p.abbreviation = str(d.get("abbreviation", "DYN"))
	p.color_hex = str(d.get("color_hex", "f58c29"))
	p.rng_seed = int(str(d.get("rng_seed", "0")))
	p.created_release_id = str(d.get("created_release_id", ""))
	p.release_history = _arr(d.get("release_history"))
	var b = d.get("balances", {})
	for c in FcDynastyConfig.CURRENCIES:
		p.balances[c] = int(b.get(c, 0)) if b is Dictionary else 0
	p.cards = _dict(d.get("cards"))
	p.ledger = _arr(d.get("ledger"))
	p.txn_counter = int(d.get("txn_counter", 0))
	p.processed_requests = _dict(d.get("processed_requests"))
	p.pack_openings = _arr(d.get("pack_openings"))
	p.opening_counter = int(d.get("opening_counter", 0))
	p.pity = _dict(d.get("pity"))
	p.roster = FcDynastyRoster.from_dict(_dict(d.get("roster")))
	var rec := _dict(d.get("record"))
	for k in p.record:
		p.record[k] = int(rec.get(k, 0))
	p.card_stats = _dict(d.get("card_stats"))
	p.game_counter = int(d.get("game_counter", 0))
	p.game_history = _arr(d.get("game_history"))
	p.replays = _arr(d.get("replays"))
	p.challenges = _dict(d.get("challenges"))
	p.seasons = _dict(d.get("seasons"))
	var t := _dict(d.get("tournament"))
	p.tournament = {"active": _dict(t.get("active")), "history": _arr(t.get("history")), "run_counter": int(t.get("run_counter", 0))}
	p.starter_granted = bool(d.get("starter_granted", false))
	p.goals = {"claimed": _arr(_dict(d.get("goals")).get("claimed"))}
	var l := _dict(d.get("ladder"))
	if not l.is_empty():
		p.ladder = FcDynastyLadder.fresh()
		for k in ["rating", "peak", "games", "wins"]:
			p.ladder[k] = int(l.get(k, p.ladder[k]))
		p.ladder["season_id"] = str(l.get("season_id", ""))
		p.ladder["reached"] = _arr(l.get("reached"))
		p.ladder["history"] = _arr(l.get("history"))
	return p


## JSON gives whole numbers back as floats; this turns them into ints again, deeply, so loaded data equals saved data.
static func normalize(value: Variant) -> Variant:
	if value is float and is_equal_approx(value, floorf(value)):
		return int(value)
	if value is Dictionary:
		var out := {}
		for k in value:
			out[k] = normalize(value[k])
		return out
	if value is Array:
		var out2 := []
		for v in value:
			out2.append(normalize(v))
		return out2
	return value


static func _arr(v) -> Array:
	return normalize(v) if v is Array else []


static func _dict(v) -> Dictionary:
	return normalize(v) if v is Dictionary else {}
