class_name FcOnlineMatchmaker
extends RefCounted
## Matchmaking by rating. Players wait in a queue; the search window around a rating starts at `base_window` and widens with waiting time
## (so nobody waits forever and early pairs are fair). Pairing is greedy over the rating-sorted queue and deterministic (ties broken by
## who joined first, then account id), so the same queue and clock always give the same pairs. The server issues every match's seed from
## its secret key, so a client cannot pick a lucky one.

var base_window: int = 100
var widen_per_second: float = 5.0
var _queue: Array = []   # [{account_id, rating, joined_at}]
var _counter: int = 0


func join(account_id: String, rating: int, t: int) -> bool:
	if in_queue(account_id):
		return false
	_queue.append({"account_id": account_id, "rating": rating, "joined_at": t})
	return true


func leave(account_id: String) -> bool:
	for i in _queue.size():
		if _queue[i]["account_id"] == account_id:
			_queue.remove_at(i)
			return true
	return false


func in_queue(account_id: String) -> bool:
	for e in _queue:
		if e["account_id"] == account_id:
			return true
	return false


func size() -> int:
	return _queue.size()


## The rating gap allowed between two waiting players at time `t` (the longer waiter's wait counts).
func window_at(t: int, joined_a: int, joined_b: int) -> int:
	var waited := maxi(0, t - mini(joined_a, joined_b))
	return base_window + roundi(float(waited) * widen_per_second)


## Pairs everyone who can be paired now and removes them from the queue. Returns [[entry_a, entry_b], ...]; the lower-rated is `a`.
func find_pairs(t: int) -> Array:
	var sorted := _queue.duplicate()
	sorted.sort_custom(func(x, y) -> bool:
		if x["rating"] != y["rating"]:
			return x["rating"] < y["rating"]
		if x["joined_at"] != y["joined_at"]:
			return x["joined_at"] < y["joined_at"]
		return str(x["account_id"]) < str(y["account_id"]))
	var pairs: Array = []
	var used := {}
	for i in sorted.size():
		if used.has(i):
			continue
		for j in range(i + 1, sorted.size()):
			if used.has(j):
				continue
			if absi(int(sorted[j]["rating"]) - int(sorted[i]["rating"])) <= window_at(t, int(sorted[i]["joined_at"]), int(sorted[j]["joined_at"])):
				used[i] = true
				used[j] = true
				pairs.append([sorted[i], sorted[j]])
				break
	for pair in pairs:
		leave(str(pair[0]["account_id"]))
		leave(str(pair[1]["account_id"]))
	return pairs


## The next match id and its server-issued seed: derived from the server key and a counter, so it is unpredictable to clients yet
## reproducible by the server (and by a test that knows the key).
func next_match(server_key: String) -> Dictionary:
	_counter += 1
	var id := "m_%06d" % _counter
	return {"match_id": id, "seed": seed_for(server_key, id)}


static func seed_for(server_key: String, match_id: String) -> int:
	return int(("0x" + FcOnlineCrypto.hmac_hex(server_key, "seed:" + match_id).substr(0, 15)).hex_to_int())
