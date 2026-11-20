class_name FcDynastyOnboarding
extends RefCounted
## Starting a Dynasty profile and keeping it in step with the loaded content release.
##
## The starter collection is whatever the release's `dynasty_config` publishes (starter cards, a starter pack's cards,
## starting currency). Nothing is invented here: a release without them simply starts the player empty-handed and the
## hub explains why.


## Grants the published starter collection once. Safe to call again (it does nothing the second time).
static func grant_starter(profile: FcDynastyProfile, catalog: FcDynastyCatalog) -> FcDynastyResult:
	if profile.starter_granted:
		return FcDynastyResult.success({"cards": [], "repeated": true})
	var cfg := catalog.config
	var card_ids: Array = []
	for id in cfg.get_value(["starter_card_ids"], []):
		if catalog.has_card(str(id)):
			card_ids.append(str(id))
	var pack_id := cfg.starter_pack_id()
	if pack_id != "" and catalog.packs().has(pack_id):
		for id in catalog.packs()[pack_id].get("card_ids", []):
			if catalog.has_card(str(id)) and not catalog.packs()[pack_id].has("odds"):
				card_ids.append(str(id))
	var deltas := {}
	for pair in [["credits", "starter_credits"], ["tokens", "starter_tokens"], ["shards", "starter_shards"]]:
		var amount := cfg.get_int([pair[1]], 0)
		if amount > 0:
			deltas[pair[0]] = amount
	var paid := FcDynastyEconomy.apply(profile, "starter", "starter_collection", deltas, card_ids, "starter_grant")
	if not paid.ok:
		return paid
	if bool(paid.data.get("replayed", false)):
		return FcDynastyResult.failure("duplicate_request", "The starter collection was already granted.")
	var txn_id: String = paid.data["txn"]["txn_id"]
	for id in card_ids:
		FcDynastyCollection.grant_card(profile, str(id), int(catalog.view(str(id)).get("revision", 1)), catalog.snapshot_of(str(id)), txn_id)
	profile.starter_granted = true
	return FcDynastyResult.success({"cards": card_ids, "txn": paid.data["txn"]})


## Records that the profile now runs on the loaded release and reports how the collection lines up with it.
static func sync_release(profile: FcDynastyProfile, catalog: FcDynastyCatalog) -> Dictionary:
	profile.note_release(catalog.release_id())
	var split := {"available": 0, "unavailable": 0, "changed": 0}
	for id in profile.cards:
		if catalog.has_card(str(id)):
			split["available"] += 1
			if int(profile.cards[id].get("revision", 1)) != int(catalog.view(str(id))["revision"]):
				split["changed"] += 1
		else:
			split["unavailable"] += 1
	return split
