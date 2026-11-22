class_name FcPlayerSimilarity
extends RefCounted
## How alike two players are, from their attributes alone (pure, deterministic, no randomness, no game state): the root-mean-square gap over the
## attribute keys, turned into a 0 to 100 score (100 = identical ratings). It is used to list the players a player plays like: Owner and Career
## compare against the league's active players, Dynasty against the cards of the loaded release. Ties are broken by the candidate id, so the same
## inputs always give the same list. It reads numbers and returns numbers; it never changes anything.

## Points of score lost per point of average gap: an average gap of 10 attribute points scores 78.
const PENALTY := 2.2


## 0 to 100 (100: every attribute the same). Keys missing from either side count as 50 (the attribute default).
static func similarity(a: Dictionary, b: Dictionary, keys: Array) -> int:
	if keys.is_empty():
		return 0
	var total := 0.0
	for key in keys:
		var d := float(a.get(key, 50)) - float(b.get(key, 50))
		total += d * d
	var rmse := sqrt(total / float(keys.size()))
	return clampi(roundi(100.0 - PENALTY * rmse), 0, 100)


## The `count` candidates most like `target`: [{id, similarity}] best first (ties by id). `candidates` is [{id, values: {key: value}}].
static func nearest(target: Dictionary, candidates: Array, keys: Array, count: int = 5) -> Array:
	var scored: Array = []
	for c in candidates:
		scored.append({"id": c["id"], "similarity": similarity(target, c["values"], keys)})
	scored.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x["similarity"] != y["similarity"]:
			return x["similarity"] > y["similarity"]
		return str(x["id"]) < str(y["id"]))
	return scored.slice(0, count)
