class_name FcSaveMigrator
extends RefCounted
## Upgrades old save data to the current layout, one version step at a time.
##
## When DATA_VERSION (src/core/version.gd) goes from N to N+1, register a step
## for N here that converts a version-N payload Dictionary into version N+1.
## A save from version 1 loaded by version 4 passes through steps 1->2, 2->3
## and 3->4 in order. Steps must never be edited after release.
##
## Built-in steps: 1 -> 2 (Career Mode) adds the empty `career_profiles` list. 2 -> 3 (play-by-play) gives every stored box
## score an empty `events` log. 3 -> 4 (Career Mode phase 4) gives every career profile its public image and a timeline built from
## its history and decisions. 4 -> 5 (Franchise Experience data foundation, D-077) gives every scheduled game of every season held in
## detail a stable id and links the stored box scores to their games. Tests may register their own steps, which replace a built-in step
## with the same number.

var _steps: Dictionary = {}


func _init() -> void:
	register(1, _v1_to_v2)
	register(2, _v2_to_v3)
	register(3, _v3_to_v4)
	register(4, _v4_to_v5)


## Version 2 added the Career Mode section. A version-1 save has no career, so it gets an empty list.
func _v1_to_v2(payload: Dictionary) -> Dictionary:
	var out := payload.duplicate(true)
	if not out.has("career_profiles"):
		out["career_profiles"] = []
	return out


## Version 3 added the play-by-play log to the box scores a season keeps (`recent_boxes`). Games saved before it have no
## recording, so each gets an empty log (the replay screen then says no replay was kept for that game).
func _v2_to_v3(payload: Dictionary) -> Dictionary:
	var out := payload.duplicate(true)
	var world = out.get("world", {})
	if world is Dictionary:
		for season in world.get("seasons", []):
			if not (season is Dictionary):
				continue
			for entry in season.get("recent_boxes", []):
				if entry is Dictionary and not entry.has("events"):
					entry["events"] = {"rows": []}
	return out


## Version 4 added the public image (fan_favor 50, media_image 50, hype 0, no headlines) and the career timeline to every career profile.
## A career that already has seasons and decisions gets a timeline built from them (one row per season and per decision), so an older
## career is not blank. Written inline on purpose: a released step must never change when other code does.
func _v3_to_v4(payload: Dictionary) -> Dictionary:
	var out := payload.duplicate(true)
	for profile in out.get("career_profiles", []):
		if not (profile is Dictionary):
			continue
		for key in [["fan_favor", 50], ["media_image", 50], ["hype", 0], ["public_year", 0]]:
			if not profile.has(key[0]):
				profile[key[0]] = key[1]
		if not profile.has("headlines"):
			profile["headlines"] = []
		if not profile.has("timeline"):
			var rows: Array = []
			for h in profile.get("history", []):
				if h is Dictionary:
					rows.append({"year": int(h.get("year", 0)), "kind": "season", "text": "Season %d: %d games, %s points a game" % [int(h.get("year", 0)), int(h.get("games", 0)), str(h.get("points", 0))]})
			for d in profile.get("decisions", []):
				if d is Dictionary:
					rows.append({"year": int(d.get("year", 0)), "kind": "decision", "text": "Decided: %s (%s)" % [str(d.get("key", "")), str(d.get("choice", ""))]})
			rows.sort_custom(func(a, b) -> bool: return int(a["year"]) < int(b["year"]))
			profile["timeline"] = rows.slice(maxi(0, rows.size() - 300))
	return out


## Version 5 (D-077 C1, C2) added stable game ids, compact result lines, day logs, transactions, rating history, owner objectives, sim
## preferences, the ledger and stored jersey numbers. Only the game ids can be rebuilt from an old save: every scheduled game of every
## season still held in detail gets the next id of the world's "game" counter, season by season (in season id order) and game by game (in
## the stored order, which is by day), so ids never clash and are never reused; each stored box score gets the id of the game it belongs to
## (same day, series and teams). Everything else starts empty (no history is invented): jersey numbers are given out when the game loads
## (FcRosterNumbers, a deterministic rule), and reports, lines and logs begin with the next day played. Written inline on purpose: a
## released step must never change when other code does.
func _v4_to_v5(payload: Dictionary) -> Dictionary:
	var out := payload.duplicate(true)
	var world = out.get("world", {})
	if not (world is Dictionary):
		return out
	var ids: Dictionary = world.get("ids", {})
	var counter := int(ids.get("game", 0))
	var seasons: Array = world.get("seasons", []).duplicate()
	seasons.sort_custom(func(a, b) -> bool: return int(a.get("id", 0)) < int(b.get("id", 0)))
	for season in seasons:
		if not (season is Dictionary):
			continue
		for g in season.get("games", []):
			if g is Dictionary and int(g.get("id", 0)) <= 0:
				counter += 1
				g["id"] = counter
		for key in ["recent_boxes"]:
			for entry in season.get(key, []):
				if not (entry is Dictionary) or int(entry.get("game_id", 0)) > 0:
					continue
				var box: Dictionary = entry.get("box", {})
				var teams: Array = box.get("team_ids", [])
				for g in season.get("games", []):
					if g is Dictionary and int(g.get("d", -1)) == int(entry.get("day", -2)) and int(g.get("s", 0)) == int(entry.get("series", 0)) \
							and teams.size() == 2 and int(g.get("h", 0)) == int(teams[0]) and int(g.get("a", 0)) == int(teams[1]):
						entry["game_id"] = int(g["id"])
						break
	ids["game"] = counter
	world["ids"] = ids
	return out


## `step` is a Callable taking the payload Dictionary and returning the
## upgraded Dictionary (or null if it cannot be upgraded).
func register(from_version: int, step: Callable) -> void:
	_steps[from_version] = step


## Returns {"ok": bool, "payload": Dictionary, "message": String}.
func migrate(payload: Dictionary, from_version: int, to_version: int) -> Dictionary:
	var current := payload
	var v := from_version
	while v < to_version:
		if not _steps.has(v):
			return {"ok": false, "payload": payload,
				"message": "no migration from save version %d to %d" % [v, v + 1]}
		var result = _steps[v].call(current)
		if not (result is Dictionary):
			return {"ok": false, "payload": payload,
				"message": "migration from save version %d failed" % v}
		current = result
		v += 1
	return {"ok": true, "payload": current, "message": ""}
