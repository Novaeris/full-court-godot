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
## IDEMPOTENCY (enforced here, for every caller): with a non-empty `request_id`
##   - a request id not seen before is applied normally and remembered (only after it succeeds: a failed request reserves nothing);
##   - the SAME id again with the same kind, ref, deltas and cards changes nothing (no balance change, no new ledger entry, no counter
##     increment) and returns success with data {"txn": <the original ledger entry>, "replayed": true};
##   - the same id with DIFFERENT parameters is refused with the code "request_conflict" (a misleading success would hide a bug);
##   - if the original entry has since been trimmed from the ledger (it keeps only the newest entries), only its id is known, so the
##     parameters cannot be compared and the repeat is treated as a replay.
## An empty request id is never remembered or matched: every such call is a new transaction.
## A fresh transaction returns {"txn": ..., "replayed": false}. Callers that do more than move currency (grant cards, open packs) must
## check "replayed" and not repeat that work.
static func apply(profile: FcDynastyProfile, kind: String, ref: String, deltas: Dictionary,
		card_ids: Array = [], request_id: String = "", note: String = "") -> FcDynastyResult:
	if request_id != "":
		var prior := previous(profile, request_id)
		if not prior.is_empty():
			if prior.has("kind") and not _same_request(prior, kind, ref, deltas, card_ids):
				return FcDynastyResult.failure("request_conflict", "The request '%s' was already used for a different transaction." % request_id)
			return FcDynastyResult.success({"txn": prior, "replayed": true})
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
	return FcDynastyResult.success({"txn": txn, "replayed": false})


static func _same_request(prior: Dictionary, kind: String, ref: String, deltas: Dictionary, card_ids: Array) -> bool:
	if str(prior.get("kind", "")) != kind or str(prior.get("ref", "")) != ref:
		return false
	var before: Dictionary = prior.get("deltas", {})
	if before.size() != deltas.size():
		return false
	for currency in deltas:
		if not before.has(currency) or int(before[currency]) != int(deltas[currency]):
			return false
	var cards_before: Array = prior.get("cards", [])
	if cards_before.size() != card_ids.size():
		return false
	for i in card_ids.size():
		if str(cards_before[i]) != str(card_ids[i]):
			return false
	return true


## Convenience: a pure cost (positive numbers) becomes negative deltas.
static func spend(profile: FcDynastyProfile, kind: String, ref: String, cost: Dictionary,
		card_ids: Array = [], request_id: String = "") -> FcDynastyResult:
	var deltas := {}
	for currency in cost:
		deltas[currency] = -int(cost[currency])
	return apply(profile, kind, ref, deltas, card_ids, request_id)
