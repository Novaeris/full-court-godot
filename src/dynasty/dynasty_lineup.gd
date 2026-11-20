class_name FcDynastyLineup
extends RefCounted
## Roster rules for a Dynasty team: who may fill which slot, whether the roster is valid, recommendations, the team overall
## and the team identity. Pure functions on the profile and catalog; a roster that does not pass `problems()` can never enter
## a game (see FcDynastyMatch).
##
## Rules: 13 slots (5 starters PG-SG-SF-PF-C, 7 bench, 1 reserve); every card is owned and in the loaded release; one card
## per real player (two editions of the same player cannot both be on the roster); a starter must list the slot's position as
## his primary or secondary position; bench and reserve can be anyone.

const IDENTITY_NAMES := {
	"three": "Three-point shooting", "mid": "Mid-range scoring", "finishing": "Finishing at the rim", "playmaking": "Playmaking",
	"perimeter_d": "Perimeter defense", "interior_d": "Interior defense", "rebound": "Rebounding", "steal": "Pressure defense",
}


static func eligible(view: Dictionary, slot: int) -> bool:
	if slot >= FcDynastyRoster.STARTERS:
		return true
	var want: int = FcDynastyRoster.SLOT_POSITIONS[slot]
	return int(view.get("position_id", 0)) == want or int(view.get("secondary_id", 0)) == want


## Everything wrong with the roster, in plain words ([] = valid and ready to play).
static func problems(profile: FcDynastyProfile, catalog: FcDynastyCatalog) -> Array[String]:
	var out: Array[String] = []
	var r := profile.roster
	var seen_players := {}
	for i in FcDynastyRoster.SIZE:
		var id := str(r.slots[i])
		if id == "":
			out.append("%s is empty." % FcDynastyRoster.slot_name(i))
			continue
		if not profile.cards.has(id):
			out.append("%s: you do not own this card." % FcDynastyRoster.slot_name(i))
			continue
		if not catalog.has_card(id):
			out.append("%s: this card is not in the current content release." % FcDynastyRoster.slot_name(i))
			continue
		var v := catalog.view(id)
		if not eligible(v, i):
			out.append("%s: %s is a %s and cannot start here." % [FcDynastyRoster.slot_name(i), v["name"], v["position"]])
		if seen_players.has(v["player_id"]):
			out.append("%s appears twice (two editions of one player cannot share a roster)." % v["name"])
		seen_players[v["player_id"]] = true
	return out


static func is_valid(profile: FcDynastyProfile, catalog: FcDynastyCatalog) -> bool:
	return problems(profile, catalog).is_empty()


## Puts `card_id` into `slot`. A card already on the roster moves (the two slots swap if the displaced card fits the old slot,
## otherwise the old slot is left empty).
static func assign(profile: FcDynastyProfile, catalog: FcDynastyCatalog, slot: int, card_id: String) -> FcDynastyResult:
	if slot < 0 or slot >= FcDynastyRoster.SIZE:
		return FcDynastyResult.failure("bad_slot", "There is no such roster slot.")
	if not profile.cards.has(card_id):
		return FcDynastyResult.failure("not_owned", "You do not own this card.")
	if not catalog.has_card(card_id):
		return FcDynastyResult.failure("unavailable", "This card is not in the current content release, so it cannot be used.")
	var v := catalog.view(card_id)
	if not eligible(v, slot):
		return FcDynastyResult.failure("position", "%s plays %s and cannot start at %s." % [v["name"], v["position"], FcPosition.abbreviation(FcDynastyRoster.SLOT_POSITIONS[slot])])
	var r := profile.roster
	var from := r.slot_of(card_id)
	# one card per real player: another edition of this player elsewhere on the roster is not allowed
	for i in FcDynastyRoster.SIZE:
		var other := str(r.slots[i])
		if other != "" and i != slot and i != from and catalog.has_card(other) and catalog.view(other)["player_id"] == v["player_id"]:
			return FcDynastyResult.failure("same_player", "%s is already on your roster in another edition." % v["name"])
	var displaced := str(r.slots[slot])
	if from >= 0 and from != slot:
		var back := displaced != "" and catalog.has_card(displaced) and eligible(catalog.view(displaced), from)
		r.slots[from] = displaced if back else ""
		var m: int = r.minutes[from]
		r.minutes[from] = r.minutes[slot] if back else 0
		r.minutes[slot] = m
	r.slots[slot] = card_id
	return FcDynastyResult.success()


static func clear_slot(profile: FcDynastyProfile, slot: int) -> FcDynastyResult:
	if slot < 0 or slot >= FcDynastyRoster.SIZE:
		return FcDynastyResult.failure("bad_slot", "There is no such roster slot.")
	profile.roster.slots[slot] = ""
	profile.roster.minutes[slot] = 0
	return FcDynastyResult.success()


## Rotation setting for a slot: -1 fewer minutes, 0 normal, +1 more.
static func set_minutes(profile: FcDynastyProfile, slot: int, value: int) -> FcDynastyResult:
	if slot < 0 or slot >= FcDynastyRoster.SIZE:
		return FcDynastyResult.failure("bad_slot", "There is no such roster slot.")
	profile.roster.minutes[slot] = clampi(value, -1, 1)
	return FcDynastyResult.success()


## The best roster the player could field right now as an Array of 13 card ids ("" where nobody is left). Does not change anything.
static func recommend(profile: FcDynastyProfile, catalog: FcDynastyCatalog) -> Array[String]:
	var pool: Array[Dictionary] = []
	for id in profile.owned_card_ids():
		if catalog.has_card(id):
			pool.append(catalog.view(id))
	pool.sort_custom(func(a, b): return [-a["overall"], a["card_id"]] < [-b["overall"], b["card_id"]])
	var out: Array[String] = []
	out.resize(FcDynastyRoster.SIZE)
	out.fill("")
	var used_players := {}
	var used_cards := {}
	# fill the position with the fewest candidates first so a scarce position is not starved
	var order: Array = [0, 1, 2, 3, 4]
	var counts := {}
	for slot in order:
		var n := 0
		for v in pool:
			if eligible(v, slot):
				n += 1
		counts[slot] = n
	order.sort_custom(func(a, b): return [counts[a], a] < [counts[b], b])
	for slot in order:
		for v in pool:
			if eligible(v, slot) and not used_players.has(v["player_id"]):
				out[slot] = v["card_id"]
				used_players[v["player_id"]] = true
				used_cards[v["card_id"]] = true
				break
	# the greedy pass can strand a slot when a legal five exists (it picks the best card per slot); the shared rule finds one
	var incomplete := false
	for slot in FcDynastyRoster.STARTERS:
		incomplete = incomplete or out[slot] == ""
	if incomplete:
		var matched := FcDynastyContentRules.match_starters(pool)
		if not matched.has(-1):
			out.fill("")
			used_players.clear()
			for slot in FcDynastyRoster.STARTERS:
				out[slot] = pool[matched[slot]]["card_id"]
				used_players[pool[matched[slot]]["player_id"]] = true
	var next := FcDynastyRoster.STARTERS
	for v in pool:
		if next >= FcDynastyRoster.SIZE:
			break
		if not used_players.has(v["player_id"]):
			out[next] = v["card_id"]
			used_players[v["player_id"]] = true
			next += 1
	return out


## Applies recommend() to the roster (resets the rotation settings).
static func auto_fill(profile: FcDynastyProfile, catalog: FcDynastyCatalog) -> FcDynastyResult:
	var rec := recommend(profile, catalog)
	profile.roster.clear()
	for i in rec.size():
		profile.roster.slots[i] = rec[i]
	return FcDynastyResult.success()


## Owned, usable cards that may go in `slot`, best first (for the card picker).
static func candidates(profile: FcDynastyProfile, catalog: FcDynastyCatalog, slot: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in profile.owned_card_ids():
		if catalog.has_card(id) and eligible(catalog.view(id), slot):
			out.append(catalog.view(id))
	out.sort_custom(func(a, b): return [-a["overall"], a["card_id"]] < [-b["overall"], b["card_id"]])
	return out


## The team's overall: a weighted average of the filled slots' card overalls (weights per slot are economy data), so starters
## count most. Empty slots are ignored, so an unfinished roster shows the strength of what is there.
static func team_overall(profile: FcDynastyProfile, catalog: FcDynastyCatalog) -> float:
	return overall_of_cards(profile.roster.slots, catalog)


static func overall_of_cards(slots: Array, catalog: FcDynastyCatalog) -> float:
	var weights := catalog.config.team_weights()
	var total := 0.0
	var weight_sum := 0.0
	for i in slots.size():
		var id := str(slots[i])
		if id == "" or not catalog.has_card(id):
			continue
		var w := float(weights[i]) if i < weights.size() else 1.0
		total += w * float(catalog.view(id)["overall"])
		weight_sum += w
	return total / weight_sum if weight_sum > 0.0 else 0.0


## Plain-language identity from the starters' composite ratings: the team's two strongest areas.
static func identity(profile: FcDynastyProfile, catalog: FcDynastyCatalog) -> Array[String]:
	var sums := {}
	var n := 0
	for i in FcDynastyRoster.STARTERS:
		var id := str(profile.roster.slots[i])
		if id == "" or not catalog.has_card(id):
			continue
		var comps := catalog.ratings.compute(catalog.make_player(id, i + 1))
		for key in IDENTITY_NAMES:
			sums[key] = float(sums.get(key, 0.0)) + float(comps.get(key, 0.0))
		n += 1
	var out: Array[String] = []
	if n == 0:
		return out
	var keys: Array = IDENTITY_NAMES.keys()
	keys.sort_custom(func(a, b): return sums[a] > sums[b])
	for k in keys.slice(0, 2):
		out.append(str(IDENTITY_NAMES[k]))
	return out
