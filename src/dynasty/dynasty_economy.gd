class_name FcDynastyEconomy
extends RefCounted
## Currency and ledger rules. The ONLY code that changes a balance. Every change becomes a ledger entry with a stable
## transaction id ("tx_000001"...), so there is always a clear record of what happened and why, and a repeated request
## (same request_id) is answered from the record instead of being applied twice.
##
## These functions change the profile in memory only; FcDynastySession saves it (and undoes the change if the save fails).


## The ledger entry for a request id that was already applied, or {} if it was not.
static func previous(profile: FcDynastyProfile, request_id: String) -> Dictionary:
	if request_id == "" or not profile.processed_requests.has(request_id):
		return {}
	var txn_id := str(profile.processed_requests[request_id])
	for t in profile.ledger:
		if str(t.get("txn_id", "")) == txn_id:
			return t
	return {"txn_id": txn_id}


static func can_afford(profile: FcDynastyProfile, cost: Dictionary) -> bool:
	for currency in cost:
		if int(cost[currency]) < 0 or profile.balance(str(currency)) < int(cost[currency]):
			return false
	return true


## Applies `deltas` ({currency: signed amount}) and records the transaction. Fails (changing nothing) if a balance
## would go negative or a currency is unknown.
static func apply(profile: FcDynastyProfile, kind: String, ref: String, deltas: Dictionary,
		card_ids: Array = [], request_id: String = "", note: String = "") -> FcDynastyResult:
	for currency in deltas:
		if not FcDynastyConfig.CURRENCIES.has(str(currency)):
			return FcDynastyResult.failure("unknown_currency", "Unknown currency '%s'." % str(currency))
		if profile.balance(str(currency)) + int(deltas[currency]) < 0:
			return FcDynastyResult.failure("insufficient_funds", "Not enough %s." % str(currency))
	for currency in deltas:
		profile.balances[currency] = profile.balance(str(currency)) + int(deltas[currency])
	profile.txn_counter += 1
	var txn := {
		"txn_id": "tx_%06d" % profile.txn_counter, "kind": kind, "ref": ref,
		"deltas": deltas.duplicate(), "cards": card_ids.duplicate(), "note": note,
	}
	profile.ledger.append(txn)
	var limit := FcDynastyConfig.build().get_int(["ledger_limit"], 400)
	while profile.ledger.size() > limit:
		profile.ledger.pop_front()
	if request_id != "":
		profile.processed_requests[request_id] = txn["txn_id"]
	return FcDynastyResult.success({"txn": txn})


## Convenience: a pure cost (positive numbers) becomes negative deltas.
static func spend(profile: FcDynastyProfile, kind: String, ref: String, cost: Dictionary,
		card_ids: Array = [], request_id: String = "") -> FcDynastyResult:
	var deltas := {}
	for currency in cost:
		deltas[currency] = -int(cost[currency])
	return apply(profile, kind, ref, deltas, card_ids, request_id)
