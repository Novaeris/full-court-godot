class_name FcDynastyCollection
extends RefCounted
## Card ownership rules. Ownership is one record per card_id with a quantity (copies). Editions of the same player are
## different card_ids and so different records: they are never merged. A record keeps the revision and a small identity
## snapshot from the moment the card was first obtained, so history survives a later release dropping or changing the card.
##
## Cosmetic mastery (frames and effects) never touches ratings, attributes or badges; gameplay always reads the release.


## Adds one copy. `snapshot` is the identity worth remembering ({title, player_name, rarity, position, overall}).
## Returns {"new": bool, "quantity": int}.
static func grant_card(profile: FcDynastyProfile, card_id: String, revision: int, snapshot: Dictionary, txn_id: String) -> Dictionary:
	if profile.cards.has(card_id):
		profile.cards[card_id]["quantity"] = int(profile.cards[card_id]["quantity"]) + 1
		return {"new": false, "quantity": int(profile.cards[card_id]["quantity"])}
	profile.cards[card_id] = {
		"card_id": card_id, "quantity": 1, "revision": revision,
		"snapshot": snapshot.duplicate(), "first_txn": txn_id, "mastery": 0,
	}
	return {"new": true, "quantity": 1}


## Copies beyond the first.
static func duplicates_of(profile: FcDynastyProfile, card_id: String) -> int:
	return maxi(0, profile.quantity_of(card_id) - 1)


## A copy is "spare" only if the roster does not need it: the first copy is never spare.
static func convert_duplicate(profile: FcDynastyProfile, config: FcDynastyConfig, card_id: String,
		rarity: String, request_id: String) -> FcDynastyResult:
	var prior := FcDynastyEconomy.previous(profile, request_id)
	if not prior.is_empty():
		return FcDynastyResult.success({"txn": prior, "repeated": true})
	if duplicates_of(profile, card_id) < 1:
		return FcDynastyResult.failure("no_duplicate", "You only have one copy of this card; the first copy is never converted.")
	var shards := config.shards_for(rarity)
	if shards <= 0:
		return FcDynastyResult.failure("not_convertible", "This rarity cannot be converted.")
	var paid := FcDynastyEconomy.apply(profile, "convert_duplicate", card_id, {"shards": shards}, [card_id], request_id)
	if not paid.ok:
		return paid
	profile.cards[card_id]["quantity"] = profile.quantity_of(card_id) - 1
	paid.data["shards"] = shards
	return paid


## Spends one duplicate copy and shards to raise a card's cosmetic mastery by one level.
static func apply_mastery(profile: FcDynastyProfile, config: FcDynastyConfig, card_id: String, request_id: String) -> FcDynastyResult:
	var prior := FcDynastyEconomy.previous(profile, request_id)
	if not prior.is_empty():
		return FcDynastyResult.success({"txn": prior, "repeated": true})
	if not profile.cards.has(card_id):
		return FcDynastyResult.failure("not_owned", "You do not own this card.")
	var level := int(profile.cards[card_id].get("mastery", 0))
	if level >= config.mastery_max():
		return FcDynastyResult.failure("max_mastery", "This card is at its highest mastery.")
	if duplicates_of(profile, card_id) < 1:
		return FcDynastyResult.failure("no_duplicate", "Mastery needs a spare duplicate of this card.")
	var cost := config.mastery_cost(level)
	var paid := FcDynastyEconomy.apply(profile, "mastery", card_id, {"shards": -cost}, [card_id], request_id)
	if not paid.ok:
		return paid
	profile.cards[card_id]["quantity"] = profile.quantity_of(card_id) - 1
	profile.cards[card_id]["mastery"] = level + 1
	paid.data["level"] = level + 1
	return paid
