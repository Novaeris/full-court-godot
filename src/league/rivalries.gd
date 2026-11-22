class_name FcRivalries
extends RefCounted
## Team rivalries, worked out from the playoff series the world keeps forever (every finished season's bracket survives archiving):
## who met whom, who won, which series went to the last game, which were finals. Teams that keep meeting, keep winning narrow series
## off each other, or share a division become rivals, and the rivalry DEVELOPS over the years from nothing to budding, heated and bitter.
## Nothing here is stored (same idea as FcRecords): change the rules below and every history is re-read.
##
## Score = MEETING_POINTS per series + CLOSE_POINTS per series decided in the last game + FINAL_POINTS per meeting in the final
## + DIVISION_POINTS when they share a division and have met at least once.

const MEETING_POINTS := 10
const CLOSE_POINTS := 6
const FINAL_POINTS := 10
const DIVISION_POINTS := 6
const BUDDING := 10
const HEATED := 28
const BITTER := 50

var world: FcWorld
var league_id: int
## "low:high" team ids -> {"a", "b", "series": [{"year", "round", "winner", "wins_a", "wins_b", "close", "final"}]} (a < b, oldest first).
var _pairs: Dictionary = {}


func _init(game_world: FcWorld, league: int) -> void:
	world = game_world
	league_id = league
	var seasons: Array[FcSeason] = []
	for s in world.seasons.all():
		if s.league_id == league_id and s.status == FcSeason.Status.COMPLETE and s.playoffs != null:
			seasons.append(s)
	seasons.sort_custom(func(a: FcSeason, b: FcSeason) -> bool: return a.year < b.year)
	for s in seasons:
		for series in s.playoffs.series:
			if series.is_bye or series.winner_id == 0 or series.team_a == 0 or series.team_b == 0:
				continue
			var low: int = mini(series.team_a, series.team_b)
			var high: int = maxi(series.team_a, series.team_b)
			var key := "%d:%d" % [low, high]
			if not _pairs.has(key):
				_pairs[key] = {"a": low, "b": high, "series": []}
			var wins_low: int = series.wins_a if series.team_a == low else series.wins_b
			var wins_high: int = series.wins_b if series.team_a == low else series.wins_a
			var loser_wins := mini(wins_low, wins_high)
			(_pairs[key]["series"] as Array).append({"year": s.year, "round": series.round, "winner": series.winner_id, "wins_a": wins_low, "wins_b": wins_high,
				"close": loser_wins == series.wins_needed() - 1, "final": series.round == s.playoffs.rounds})


## Every pair that has met, as rivalry summaries (see `summary_of`), strongest first.
func all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in _pairs:
		out.append(summary_of(int(_pairs[key]["a"]), int(_pairs[key]["b"])))
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["score"] > y["score"] if x["score"] != y["score"] else (x["a"] < y["a"] if x["a"] != y["a"] else x["b"] < y["b"]))
	return out


## The rivalries of one team, strongest first (only pairs that reached at least BUDDING unless `include_minor`).
func of_team(team_id: int, count: int = 5, include_minor: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in all():
		if (int(r["a"]) == team_id or int(r["b"]) == team_id) and (include_minor or int(r["score"]) >= BUDDING):
			out.append(r)
	return out.slice(0, count)


## The league's strongest rivalries.
func top(count: int = 5) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in all():
		if int(r["score"]) >= BUDDING:
			out.append(r)
	return out.slice(0, count)


## {"a", "b" (team ids, a < b), "meetings", "wins_a", "wins_b", "close", "finals", "last_year", "score", "level" ("", "Budding", "Heated"
## or "Bitter"), "same_division", "series", "headline"}. Works for a pair that has never met too (all zero).
func summary_of(a: int, b: int) -> Dictionary:
	var low: int = mini(a, b)
	var high: int = maxi(a, b)
	var series: Array = _pairs.get("%d:%d" % [low, high], {"series": []})["series"]
	var s := _tally(low, high, series)
	s["series"] = series
	s["headline"] = headline_of(s)
	return s


## How the rivalry grew: one row per year they met, with the score and level reached by the end of that year: [{"year", "score", "level"}].
func development(a: int, b: int) -> Array[Dictionary]:
	var low: int = mini(a, b)
	var high: int = maxi(a, b)
	var series: Array = _pairs.get("%d:%d" % [low, high], {"series": []})["series"]
	var out: Array[Dictionary] = []
	var upto: Array = []
	var last_year := -1
	for entry in series:
		upto.append(entry)
		if int(entry["year"]) == last_year:
			out.pop_back()
		last_year = int(entry["year"])
		var t := _tally(low, high, upto)
		out.append({"year": last_year, "score": t["score"], "level": t["level"]})
	return out


static func level_of(score: int) -> String:
	if score >= BITTER:
		return "Bitter"
	if score >= HEATED:
		return "Heated"
	if score >= BUDDING:
		return "Budding"
	return ""


func headline_of(s: Dictionary) -> String:
	if int(s["meetings"]) == 0:
		return "%s and %s have never met in the playoffs." % [world.team_display_name(int(s["a"])), world.team_display_name(int(s["b"]))]
	var leader := "tied"
	var x := int(s["wins_a"])
	var y := int(s["wins_b"])
	var names := [world.team_display_name(int(s["a"])), world.team_display_name(int(s["b"]))]
	if x != y:
		leader = "%s lead %d-%d" % [names[0] if x > y else names[1], maxi(x, y), mini(x, y)]
	else:
		leader = "the series count is level at %d-%d" % [x, y]
	return "%s and %s have met %d time%s in the playoffs; %s." % [names[0], names[1], s["meetings"], "" if int(s["meetings"]) == 1 else "s", leader]


func _tally(low: int, high: int, series: Array) -> Dictionary:
	var wins_low := 0
	var wins_high := 0
	var close := 0
	var finals := 0
	var last_year := 0
	for entry in series:
		if int(entry["winner"]) == low:
			wins_low += 1
		else:
			wins_high += 1
		if bool(entry["close"]):
			close += 1
		if bool(entry["final"]):
			finals += 1
		last_year = int(entry["year"])
	var league: FcLeague = world.leagues.get_by_id(league_id)
	var division: FcDivision = league.division_of_team(low) if league != null else null
	var same := division != null and division.team_ids.has(high)
	var score := series.size() * MEETING_POINTS + close * CLOSE_POINTS + finals * FINAL_POINTS + (DIVISION_POINTS if same and not series.is_empty() else 0)
	return {"a": low, "b": high, "meetings": series.size(), "wins_a": wins_low, "wins_b": wins_high, "close": close, "finals": finals,
		"last_year": last_year, "score": score, "level": level_of(score), "same_division": same}
