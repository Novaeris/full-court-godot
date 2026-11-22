class_name FcAchievements
extends RefCounted
## Player achievements (Owner and Career Mode), DERIVED from numbers the game already keeps; nothing is stored, so no save changes and no way
## for an achievement to drift out of step with the statistics it comes from. The list, thresholds and names are data
## (data/achievements/achievements.json). Three tiers each (bronze, silver, gold). Pure: metrics in, results out; deterministic.

const PATH := "res://data/achievements/achievements.json"

static var _cache: Dictionary = {}


static func _data() -> Dictionary:
	if _cache.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_cache = parsed if parsed is Dictionary else {"tier_names": ["", "Bronze", "Silver", "Gold"], "achievements": []}
	return _cache


## The metrics every achievement reads, from a player's career rows ([year, team, gp, seconds, points, fgm, fga, tpm, tpa, ftm, fta, oreb, dreb, ast,
## stl, blk, tov, pf] per season), his honours (FcRecords.honours_of), his injury history (FcWorld.injuries_of) and the seasons in a row with his club.
static func metrics_for(rows: Array, honours: Dictionary, injuries: Array, club_seasons: int) -> Dictionary:
	var m := {"career_points": 0, "career_rebounds": 0, "career_assists": 0, "career_steals": 0, "career_blocks": 0, "career_threes": 0, "seasons_played": rows.size(),
		"career_games": 0, "best_season_ppg": 0, "best_season_rpg": 0, "best_season_apg": 0, "one_club_seasons": club_seasons,
		"titles": int(honours.get("titles", 0)), "mvp": int(honours.get("mvp", 0)), "finals_mvp": int(honours.get("finals_mvp", 0)),
		"scoring_titles": int(honours.get("scoring_titles", 0)), "all_league_first": int(honours.get("all_league_first", 0)), "comebacks": 0}
	for row in rows:
		if row.size() < 16:
			continue
		var gp := maxi(1, int(row[2]))
		m["career_games"] += int(row[2])
		m["career_points"] += int(row[4])
		m["career_threes"] += int(row[7])
		m["career_rebounds"] += int(row[11]) + int(row[12])
		m["career_assists"] += int(row[13])
		m["career_steals"] += int(row[14])
		m["career_blocks"] += int(row[15])
		if int(row[2]) >= 20:   # a handful of games proves nothing about a season
			m["best_season_ppg"] = maxi(m["best_season_ppg"], int(row[4]) / gp)
			m["best_season_rpg"] = maxi(m["best_season_rpg"], (int(row[11]) + int(row[12])) / gp)
			m["best_season_apg"] = maxi(m["best_season_apg"], int(row[13]) / gp)
	for injury in injuries:
		if bool(injury.get("severe", false)):
			for row in rows:
				if int(row[0]) > int(injury["year"]) and int(row[2]) >= 40:
					m["comebacks"] += 1
					break
	return m


## Every achievement with its state: [{id, name, description, unit, value, tier (0 to 3), tier_name, thresholds, next (the next threshold, 0 when gold), progress (0 to 1 toward it)}].
static func evaluate(metrics: Dictionary) -> Array:
	var data := _data()
	var tier_names: Array = data.get("tier_names", ["", "Bronze", "Silver", "Gold"])
	var out: Array = []
	for def in data["achievements"]:
		var value := int(metrics.get(str(def["metric"]), 0))
		var thresholds: Array = def["thresholds"]
		var tier := 0
		for i in thresholds.size():
			if value >= int(thresholds[i]):
				tier = i + 1
		var next := int(thresholds[tier]) if tier < thresholds.size() else 0
		var floor_value := int(thresholds[tier - 1]) if tier > 0 else 0
		var progress := 1.0 if next == 0 else clampf(float(value - floor_value) / float(maxi(1, next - floor_value)), 0.0, 1.0)
		out.append({"id": str(def["id"]), "name": str(def["name"]), "description": str(def["description"]), "unit": str(def["unit"]), "value": value, "tier": tier,
			"tier_name": str(tier_names[tier]) if tier < tier_names.size() else "", "thresholds": thresholds.duplicate(), "next": next, "progress": progress})
	return out


## The earned ones, best tier first (ties by name).
static func earned(results: Array) -> Array:
	var out: Array = results.filter(func(r: Dictionary) -> bool: return int(r["tier"]) > 0)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["tier"] > b["tier"] or (a["tier"] == b["tier"] and str(a["name"]) < str(b["name"])))
	return out


## The `count` achievements closest to their next tier (started, not gold), nearest first (ties by name).
static func next_up(results: Array, count: int = 3) -> Array:
	var out: Array = results.filter(func(r: Dictionary) -> bool: return int(r["tier"]) < 3 and int(r["value"]) > 0)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["progress"] > b["progress"] or (a["progress"] == b["progress"] and str(a["name"]) < str(b["name"])))
	return out.slice(0, count)
