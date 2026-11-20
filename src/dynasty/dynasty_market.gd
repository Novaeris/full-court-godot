class_name FcDynastyMarket
extends RefCounted
## Direct acquisition: buying a card outright at the price the release publishes (card `price`, feature card_market_v1). No
## price is ever invented here: a card without a published price is simply not for sale. Also the hook that keeps collection
## objectives in step after anything changes the collection.


static func listing(profile: FcDynastyProfile, catalog: FcDynastyCatalog) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in catalog.market_card_ids():
		var v := catalog.view(id)
		var cur := str(v["price"]["currency"])
		out.append({"card": v, "currency": cur, "amount": int(v["price"]["amount"]), "owned": profile.quantity_of(id),
			"affordable": profile.balance(cur) >= int(v["price"]["amount"])})
	out.sort_custom(func(a, b): return [-a["card"]["overall"], a["card"]["card_id"]] < [-b["card"]["overall"], b["card"]["card_id"]])
	return out


static func acquire(profile: FcDynastyProfile, catalog: FcDynastyCatalog, card_id: String, request_id: String) -> FcDynastyResult:
	var prior := FcDynastyEconomy.previous(profile, request_id)
	if not prior.is_empty():
		return FcDynastyResult.success({"txn": prior, "repeated": true})
	var v := catalog.view(card_id)
	if v.is_empty() or not bool(v["acquirable"]):
		return FcDynastyResult.failure("not_for_sale", "This card cannot be bought directly.")
	var cost := {str(v["price"]["currency"]): int(v["price"]["amount"])}
	var paid := FcDynastyEconomy.spend(profile, "acquire_card", card_id, cost, [card_id], request_id)
	if not paid.ok:
		return paid
	if bool(paid.data.get("replayed", false)):
		return FcDynastyResult.success({"txn": paid.data["txn"], "repeated": true})   # already done: change nothing again
	var got := FcDynastyCollection.grant_card(profile, card_id, int(v["revision"]), catalog.snapshot_of(card_id), paid.data["txn"]["txn_id"])
	paid.data["new"] = got["new"]
	collection_changed(profile, catalog)
	return paid


## Keeps collection-based challenges and season objectives in step. Returns the ids newly completed.
static func collection_changed(profile: FcDynastyProfile, catalog: FcDynastyCatalog) -> Dictionary:
	return {"challenges": FcDynastyChallenges.refresh_collection(profile, catalog),
		"objectives": FcDynastySeason.refresh_collection(profile, catalog)}
