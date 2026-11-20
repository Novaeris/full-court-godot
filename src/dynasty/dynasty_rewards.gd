class_name FcDynastyRewards
extends RefCounted
## Grants a published reward bundle ({credits, tokens, shards, card_ids, pack_ids}): one ledger transaction for currency
## and cards, plus recorded reward-pack openings. Used by challenge claims, season milestones, tournaments and game results,
## so there is exactly one place that turns "a reward" into balances and cards.


static func is_empty(rewards: Dictionary) -> bool:
	for key in rewards:
		var v = rewards[key]
		if (v is Array and not v.is_empty()) or (v is int and v > 0) or (v is float and v > 0.0):
			return false
	return true


## Returns success with data {txn, cards: [card ids granted directly], openings: [pack opening records]}.
static func grant(profile: FcDynastyProfile, catalog: FcDynastyCatalog, rewards: Dictionary, kind: String, ref: String,
		request_id: String) -> FcDynastyResult:
	var deltas := {}
	for c in FcDynastyConfig.CURRENCIES:
		if int(rewards.get(c, 0)) > 0:
			deltas[c] = int(rewards[c])
	var card_ids: Array = []
	for id in rewards.get("card_ids", []):
		if catalog.has_card(str(id)):
			card_ids.append(str(id))
	var paid := FcDynastyEconomy.apply(profile, kind, ref, deltas, card_ids, request_id)
	if not paid.ok:
		return paid
	var txn_id: String = paid.data["txn"]["txn_id"]
	for id in card_ids:
		FcDynastyCollection.grant_card(profile, str(id), int(catalog.view(str(id))["revision"]), catalog.snapshot_of(str(id)), txn_id)
	var openings: Array = []
	var n := 0
	for pack_id in rewards.get("pack_ids", []):
		n += 1
		var opened := FcDynastyPacks.open_reward(profile, catalog, str(pack_id), "%s:pack%d" % [txn_id, n])
		if not opened.ok:
			return opened
		openings.append(opened.data["opening"])
	return FcDynastyResult.success({"txn": paid.data["txn"], "cards": card_ids, "openings": openings, "rewards": rewards})
