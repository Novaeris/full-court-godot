class_name FcDynastyObjective
extends RefCounted
## Evaluates one published objective (shared by challenges and season objectives) against REAL game results.
## Progress only ever comes from a game summary produced by the simulation (FcDynastyMatch.summarize) or from the profile's
## collection; nothing a screen does can move it.
##
## State is {"progress": int, "done": bool}.


static func empty_state() -> Dictionary:
	return {"progress": 0, "done": false}


static func target_of(obj: Dictionary) -> int:
	return int(obj.get("target", 1))


## Folds one finished game into the state. Collection objectives ignore games (see update_collection).
static func update_game(state: Dictionary, obj: Dictionary, summary: Dictionary) -> void:
	if bool(state.get("done", false)):
		return
	var progress := int(state.get("progress", 0))
	match str(obj.get("type", "")):
		"stat":
			var stat := str(obj["stat"])
			var value := 0
			if str(obj.get("scope", "team")) == "player":
				for line in summary["players"]:
					value = maxi(value, int(line.get(stat, 0)))
			else:
				value = int(summary["team"].get(stat, 0))
			if str(obj.get("mode", "single_game")) == "cumulative":
				progress += value
			else:
				progress = maxi(progress, value)
		"wins":
			if bool(summary["won"]):
				progress += 1
		"win_margin":
			if bool(summary["won"]):
				progress = maxi(progress, int(summary["margin"]))
	_finish(state, obj, progress)


## Sets a collection objective's progress from what the player owns.
static func update_collection(state: Dictionary, obj: Dictionary, profile: FcDynastyProfile, catalog: FcDynastyCatalog) -> void:
	if bool(state.get("done", false)) or str(obj.get("type", "")) != "collection":
		return
	var value := 0
	match str(obj.get("metric", "")):
		"unique_cards":
			value = profile.unique_owned()
		"rarity_cards":
			for id in profile.cards:
				var rarity := str(catalog.view(str(id)).get("rarity", profile.cards[id].get("snapshot", {}).get("rarity", "")))
				if rarity == str(obj.get("rarity", "")):
					value += 1
		"duplicates":
			for id in profile.cards:
				value += maxi(0, profile.quantity_of(str(id)) - 1)
	_finish(state, obj, value)


static func _finish(state: Dictionary, obj: Dictionary, progress: int) -> void:
	var target := target_of(obj)
	state["progress"] = mini(progress, target)
	state["done"] = progress >= target
