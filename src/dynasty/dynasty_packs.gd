class_name FcDynastyPacks
extends RefCounted
## Pack generation and opening: pure domain logic, no UI. What a pack gives is decided only when it is opened, from the
## published definition and a seeded generator (FcRng forked from the profile seed and the opening number), so tests can fix
## the outcome and nobody can peek at it beforehand.
##
## Opening is all-or-nothing and recorded BEFORE any reveal animation: the cards are already in the collection and in
## `profile.pack_openings` when the screen starts the show. A repeated request id returns the same record and never pays or
## grants twice. (FcDynastySession.commit makes the whole step atomic with the save.)


## Rolls the cards of one pack. Returns {"cards": Array[String] in reveal order (best last), "pity": new pity counter}.
## `pity_counter` is how many packs have been opened since the last pity hit.
static func roll(catalog: FcDynastyCatalog, pack_id: String, rng: FcRng, pity_counter: int = 0) -> Dictionary:
	var def: Dictionary = catalog.packs().get(pack_id, {})
	var pool: Array = []
	for id in def.get("card_ids", []):
		if catalog.has_card(str(id)):
			pool.append(str(id))
	if not def.has("odds"):
		return {"cards": pool.duplicate(), "pity": pity_counter}
	var by_rarity := {}
	for id in pool:
		var r := str(catalog.view(id)["rarity"])
		if not by_rarity.has(r):
			by_rarity[r] = []
		by_rarity[r].append(id)
	var count := int(def.get("cards_per_pack", 1))
	var min_rank: Array = []
	for i in count:
		min_rank.append(-1)
	var slot := 0
	for g in def.get("guarantees", []):
		for k in int(g["count"]):
			if slot < count:
				min_rank[slot] = FcDynastyContentRules.rarity_rank(str(g["min_rarity"]))
				slot += 1
	var pity_def: Dictionary = def.get("pity", {}) if def.get("pity") is Dictionary else {}
	var pity_rank := FcDynastyContentRules.rarity_rank(str(pity_def.get("rarity", ""))) if not pity_def.is_empty() else -1
	var pity_due := pity_rank >= 0 and pity_counter + 1 >= int(pity_def.get("after", 0))
	if pity_due:
		# the last slot carries the pity guarantee (guaranteed slots come first, so it is usually free)
		min_rank[count - 1] = maxi(int(min_rank[count - 1]), pity_rank)
	var odds: Dictionary = def["odds"]
	var rolled: Array = []
	for i in count:
		var rarities: Array = []
		var weights: Array = []
		for r in FcDynastyContentRules.RARITY_ORDER:
			if by_rarity.has(r) and FcDynastyContentRules.rarity_rank(r) >= int(min_rank[i]):
				rarities.append(r)
				weights.append(float(odds.get(r, 0)))
		var total := 0.0
		for w in weights:
			total += w
		if total <= 0.0:
			weights = []
			for r in rarities:
				weights.append(1.0)
		var chosen: String = rarities[rng.weighted_index(weights)]
		var list: Array = by_rarity[chosen]
		rolled.append(list[rng.range_int(0, list.size() - 1)])
	var hit := false
	for id in rolled:
		if pity_rank >= 0 and FcDynastyContentRules.rarity_rank(str(catalog.view(id)["rarity"])) >= pity_rank:
			hit = true
	# reveal order: lowest rarity first, so the best card is last (stable for equal rarity)
	var indexed: Array = []
	for i in rolled.size():
		indexed.append([FcDynastyContentRules.rarity_rank(str(catalog.view(rolled[i])["rarity"])), i, rolled[i]])
	indexed.sort_custom(func(a, b): return [a[0], a[1]] < [b[0], b[1]])
	var ordered: Array = []
	for e in indexed:
		ordered.append(e[2])
	return {"cards": ordered, "pity": 0 if hit else pity_counter + 1}


## Buys and opens a pack. On success data["opening"] is the persisted record:
## {opening_id, pack_id, request_id, txn_id, revealed, cards: [{card_id, new, quantity}]}.
static func buy_and_open(profile: FcDynastyProfile, catalog: FcDynastyCatalog, pack_id: String, request_id: String) -> FcDynastyResult:
	var prior := opening_for_request(profile, request_id)
	if not prior.is_empty():
		return FcDynastyResult.success({"opening": prior, "repeated": true})
	var def: Dictionary = catalog.packs().get(pack_id, {})
	if def.is_empty():
		return FcDynastyResult.failure("unknown_pack", "That pack is not in the current content release.")
	if not def.has("price"):
		return FcDynastyResult.failure("not_for_sale", "This pack cannot be bought.")
	var cost := {str(def["price"]["currency"]): int(def["price"]["amount"])}
	if not FcDynastyEconomy.can_afford(profile, cost):
		return FcDynastyResult.failure("insufficient_funds", "Not enough %s for this pack." % str(def["price"]["currency"]))
	return _open(profile, catalog, pack_id, request_id, cost, "buy_pack")


## Opens a pack that is a reward (no price). Same recording and safety as buy_and_open.
static func open_reward(profile: FcDynastyProfile, catalog: FcDynastyCatalog, pack_id: String, request_id: String) -> FcDynastyResult:
	var prior := opening_for_request(profile, request_id)
	if not prior.is_empty():
		return FcDynastyResult.success({"opening": prior, "repeated": true})
	if not catalog.packs().has(pack_id):
		return FcDynastyResult.failure("unknown_pack", "That pack is not in the current content release.")
	return _open(profile, catalog, pack_id, request_id, {}, "reward_pack")


static func _open(profile: FcDynastyProfile, catalog: FcDynastyCatalog, pack_id: String, request_id: String,
		cost: Dictionary, kind: String) -> FcDynastyResult:
	var number := profile.opening_counter + 1
	var rng := FcRng.new(profile.rng_seed).fork("pack:%d" % number)
	var rolled := roll(catalog, pack_id, rng, int(profile.pity.get(pack_id, 0)))
	var ids: Array = rolled["cards"]
	if ids.is_empty():
		return FcDynastyResult.failure("empty_pack", "This pack has no cards to give.")
	var paid := FcDynastyEconomy.spend(profile, kind, pack_id, cost, ids, request_id)
	if not paid.ok:
		return paid
	if bool(paid.data.get("replayed", false)):
		return FcDynastyResult.failure("duplicate_request", "This pack request was already processed.")   # normally caught earlier by opening_for_request
	var txn_id: String = paid.data["txn"]["txn_id"]
	var entries: Array = []
	for id in ids:
		var got := FcDynastyCollection.grant_card(profile, str(id), int(catalog.view(str(id))["revision"]), catalog.snapshot_of(str(id)), txn_id)
		entries.append({"card_id": str(id), "new": got["new"], "quantity": got["quantity"]})
	profile.opening_counter = number
	profile.pity[pack_id] = int(rolled["pity"])
	var opening := {"opening_id": "op_%06d" % number, "pack_id": pack_id, "request_id": request_id, "txn_id": txn_id,
		"revealed": false, "cards": entries}
	profile.pack_openings.append(opening)
	return FcDynastyResult.success({"opening": opening, "txn": paid.data["txn"]})


static func opening_for_request(profile: FcDynastyProfile, request_id: String) -> Dictionary:
	if request_id == "":
		return {}
	for o in profile.pack_openings:
		if str(o.get("request_id", "")) == request_id:
			return o
	return {}


## Openings whose reveal was never finished (the game closed mid-animation): shown again on next visit.
static func pending_openings(profile: FcDynastyProfile) -> Array:
	return profile.pack_openings.filter(func(o): return not bool(o.get("revealed", false)))


static func acknowledge(profile: FcDynastyProfile, opening_id: String) -> FcDynastyResult:
	for o in profile.pack_openings:
		if str(o.get("opening_id", "")) == opening_id:
			o["revealed"] = true
			return FcDynastyResult.success()
	return FcDynastyResult.failure("unknown_opening", "That pack opening does not exist.")
