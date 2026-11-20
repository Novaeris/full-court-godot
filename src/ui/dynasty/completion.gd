class_name FcCompletion
extends RefCounted
## How much of the collection the player has, overall and by rarity, team and edition. A pure read of collection rows
## (FcCollectionQuery.rows with no filter); it changes nothing. Used by the completion panel and the hub.


## {"overall": {owned, total, percent}, "by_rarity": [{key, owned, total, percent, complete}], "by_team": [...], "by_edition": [...]}.
## Rarities come in rarity order (unknown ones last); teams and editions alphabetically. A card with no team is not counted in by_team.
static func compute(rows: Array) -> Dictionary:
	var overall := _group()
	var rarity := {}
	var team := {}
	var edition := {}
	for row in rows:
		var owned: bool = bool(row.get("owned", false))
		_add(overall, owned)
		_add(_bucket(rarity, str(row.get("rarity", "common"))), owned)
		if str(row.get("team", "")) != "":
			_add(_bucket(team, str(row["team"])), owned)
		if str(row.get("edition", "")) != "":
			_add(_bucket(edition, str(row["edition"])), owned)
	var rarity_keys := rarity.keys()
	rarity_keys.sort_custom(func(a: String, b: String) -> bool:
		var ra := _rank(a)
		var rb := _rank(b)
		return ra < rb or (ra == rb and a < b))
	return {"overall": _finish("all", overall), "by_rarity": _list(rarity, rarity_keys), "by_team": _list(team, _sorted(team)), "by_edition": _list(edition, _sorted(edition))}


## Position in rarity order; unknown (future) rarities come after the known ones.
static func _rank(rarity: String) -> int:
	var i := FcDynastyContentRules.RARITY_ORDER.find(rarity)
	return i if i >= 0 else 999


static func _group() -> Dictionary:
	return {"owned": 0, "total": 0}


static func _bucket(groups: Dictionary, key: String) -> Dictionary:
	if not groups.has(key):
		groups[key] = _group()
	return groups[key]


static func _add(group: Dictionary, owned: bool) -> void:
	group["total"] += 1
	group["owned"] += 1 if owned else 0


static func _finish(key: String, group: Dictionary) -> Dictionary:
	var total: int = group["total"]
	return {"key": key, "owned": group["owned"], "total": total, "percent": (100 * int(group["owned"]) / total) if total > 0 else 0, "complete": total > 0 and group["owned"] == total}


static func _sorted(groups: Dictionary) -> Array:
	var keys := groups.keys()
	keys.sort()
	return keys


static func _list(groups: Dictionary, keys: Array) -> Array:
	var out: Array = []
	for key in keys:
		out.append(_finish(str(key), groups[key]))
	return out
