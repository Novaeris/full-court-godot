class_name FcCollectionQuery
extends RefCounted
## Builds the rows of the collection browser: owned cards (with copies and mastery), cards of the release the player does
## not own yet, and owned cards the loaded release no longer has (as placeholders). Filtering and sorting live here, not in the
## screen, so they are tested without a UI.

const SORTS := ["overall_desc", "overall_asc", "name", "rarity_desc", "position", "copies_desc"]
const SORT_NAMES := ["Overall (high to low)", "Overall (low to high)", "Player name", "Rarity", "Position", "Copies owned"]


## `filters` keys (all optional): search (text in player name, title or edition), position (abbreviation, matches primary or
## secondary), rarity, team (exact), edition (text), min_overall, max_overall, ownership ("all", "owned", "unowned").
static func rows(profile: FcDynastyProfile, catalog: FcDynastyCatalog, filters: Dictionary = {}, sort: String = "overall_desc") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ownership := str(filters.get("ownership", "all"))
	var seen := {}
	for id in catalog.card_ids():
		seen[id] = true
		var owned := profile.cards.has(id)
		var row := catalog.owned_view(id, profile.cards[id]) if owned else catalog.view(id).duplicate()
		_decorate(row, profile, owned)
		if _matches(row, filters, ownership):
			out.append(row)
	for id in profile.cards:
		if seen.has(id):
			continue
		var row2 := catalog.owned_view(str(id), profile.cards[id])
		_decorate(row2, profile, true)
		if _matches(row2, filters, ownership):
			out.append(row2)
	_sort(out, sort)
	return out


static func _decorate(row: Dictionary, profile: FcDynastyProfile, owned: bool) -> void:
	var rec: Dictionary = profile.cards.get(str(row["card_id"]), {})
	row["owned"] = owned
	row["quantity"] = int(rec.get("quantity", 0))
	row["mastery"] = int(rec.get("mastery", 0))
	row["spare"] = maxi(0, row["quantity"] - 1)


static func _matches(row: Dictionary, f: Dictionary, ownership: String) -> bool:
	if ownership == "owned" and not row["owned"]:
		return false
	if ownership == "unowned" and row["owned"]:
		return false
	var search := str(f.get("search", "")).strip_edges().to_lower()
	if search != "":
		var hay := ("%s %s %s" % [row["name"], row["title"], row["edition"]]).to_lower()
		if not hay.contains(search):
			return false
	var pos := str(f.get("position", ""))
	if pos != "" and row["position"] != pos and row["secondary"] != pos:
		return false
	var rarity := str(f.get("rarity", ""))
	if rarity != "" and row["rarity"] != rarity:
		return false
	var team := str(f.get("team", ""))
	if team != "" and row["team"] != team:
		return false
	var edition := str(f.get("edition", "")).strip_edges().to_lower()
	if edition != "" and not str(row["edition"]).to_lower().contains(edition):
		return false
	if int(row["overall"]) < int(f.get("min_overall", 0)) or int(row["overall"]) > int(f.get("max_overall", 100)):
		return false
	return true


static func _sort(rows_to_sort: Array[Dictionary], sort: String) -> void:
	var rank := func(r: Dictionary) -> int: return FcDynastyContentRules.rarity_rank(str(r["rarity"]))
	match sort:
		"overall_asc":
			rows_to_sort.sort_custom(func(a, b): return [a["overall"], a["name"]] < [b["overall"], b["name"]])
		"name":
			rows_to_sort.sort_custom(func(a, b): return [a["name"], -a["overall"]] < [b["name"], -b["overall"]])
		"rarity_desc":
			rows_to_sort.sort_custom(func(a, b): return [-rank.call(a), -a["overall"], a["name"]] < [-rank.call(b), -b["overall"], b["name"]])
		"position":
			rows_to_sort.sort_custom(func(a, b): return [a["position_id"], -a["overall"], a["name"]] < [b["position_id"], -b["overall"], b["name"]])
		"copies_desc":
			rows_to_sort.sort_custom(func(a, b): return [-a["quantity"], -a["overall"], a["name"]] < [-b["quantity"], -b["overall"], b["name"]])
		_:
			rows_to_sort.sort_custom(func(a, b): return [-a["overall"], a["name"], a["card_id"]] < [-b["overall"], b["name"], b["card_id"]])


## Distinct values for the filter drop-downs.
static func teams(catalog: FcDynastyCatalog) -> Array[String]:
	var out: Array[String] = []
	for id in catalog.card_ids():
		var t := str(catalog.view(id)["team"])
		if t != "" and not out.has(t):
			out.append(t)
	out.sort()
	return out


## "12 of 32 cards (38%)" style progress for the hub.
static func progress(profile: FcDynastyProfile, catalog: FcDynastyCatalog) -> Dictionary:
	var total := catalog.card_ids().size()
	var owned := 0
	for id in catalog.card_ids():
		if profile.cards.has(id):
			owned += 1
	return {"owned": owned, "total": total, "percent": (100 * owned / total) if total > 0 else 0}
