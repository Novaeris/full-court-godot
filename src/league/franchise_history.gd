class_name FcFranchiseHistory
extends RefCounted
## A franchise's story, worked out from what the world keeps forever: every finished season's final standings, champion, runner-up and
## playoff bracket (kept even after a season is archived) and every player's career rows (year, team, statistics). Nothing here is
## stored, so there is no save format to migrate (the same idea as FcRecords, which it uses for the Hall of Fame score).
##
## What it answers: the season-by-season log of a team, its franchise records (titles, finals, best and worst years, droughts), its
## all-time leaders while wearing its colours, and its RETIRED NUMBERS.
##
## Retired numbers: the number the player wore (stored since data version 5; older players get the deterministic preference from a hash
## of the player id), moved to the next free number if the team already retired it. A player's number is retired by the ONE franchise he
## spent most seasons with, once he has retired, spent at least MIN_SEASONS there and reached NUMBER_SCORE on the Hall of Fame score
## (lower than induction, so great franchise players are honoured even when they miss the Hall). It happens the season after his last
## one with that team.

const MIN_SEASONS := 7
const NUMBER_SCORE := 35.0

var world: FcWorld
var league_id: int
var records: FcRecords
var _team_cache: Dictionary = {}      # team id -> {player id: with_team totals} (one pass over the careers per team)
var _retired_cache: Dictionary = {}   # current year -> {team id: [retired numbers]}


func _init(game_world: FcWorld, league: int) -> void:
	world = game_world
	league_id = league
	records = FcRecords.new(game_world, league)


## Finished seasons of this league, oldest first.
func seasons() -> Array[FcSeason]:
	var out: Array[FcSeason] = []
	for s in world.seasons.all():
		if s.league_id == league_id and s.status == FcSeason.Status.COMPLETE:
			out.append(s)
	out.sort_custom(func(a: FcSeason, b: FcSeason) -> bool: return a.year < b.year)
	return out


## One row per finished season the team played in, oldest first:
## {"year", "wins", "losses", "rank", "teams", "playoffs" (made them), "champion", "result" (words)}.
func season_log(team_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in seasons():
		var rank := 0
		var wins := 0
		var losses := 0
		for i in s.final_standings.size():
			var row: Array = s.final_standings[i]
			if int(row[0]) == team_id:
				rank = i + 1
				wins = int(row[1])
				losses = int(row[2])
		if rank == 0:
			continue
		out.append({"year": s.year, "wins": wins, "losses": losses, "rank": rank, "teams": s.final_standings.size(),
			"playoffs": s.playoffs != null and s.playoffs.qualified(team_id), "champion": s.champion_id == team_id, "result": result_text(s, team_id)})
	return out


## How the team's playoffs ended: "Champions", "Lost the final", "Lost in round 2" or "Missed the playoffs".
func result_text(season: FcSeason, team_id: int) -> String:
	if season.champion_id == team_id:
		return "Champions"
	if season.runner_up_id == team_id:
		return "Lost the final"
	if season.playoffs == null or not season.playoffs.qualified(team_id):
		return "Missed the playoffs"
	var round_lost := 0
	for series in season.playoffs.series:
		if series.is_bye or series.winner_id == 0 or series.winner_id == team_id:
			continue
		if series.team_a == team_id or series.team_b == team_id:
			round_lost = maxi(round_lost, series.round)
	return "Lost in round %d" % round_lost if round_lost > 0 else "Made the playoffs"


## Franchise totals: {"seasons", "wins", "losses", "titles", "title_years", "finals", "playoffs", "best", "worst", "drought", "playoff_streak"}.
## `best` and `worst` are the log rows with the most and fewest wins (null with no seasons); `drought` is the seasons since the last title
## (or since the team's first season when it never won one); `playoff_streak` is how many of the latest seasons in a row reached the playoffs.
func summary(team_id: int) -> Dictionary:
	var log := season_log(team_id)
	var t := {"seasons": log.size(), "wins": 0, "losses": 0, "titles": 0, "title_years": [], "finals": 0, "playoffs": 0,
		"best": null, "worst": null, "drought": 0, "playoff_streak": 0}
	for row in log:
		t["wins"] += int(row["wins"])
		t["losses"] += int(row["losses"])
		if row["champion"]:
			t["titles"] += 1
			(t["title_years"] as Array).append(row["year"])
		if row["champion"] or row["result"] == "Lost the final":
			t["finals"] += 1
		if row["playoffs"]:
			t["playoffs"] += 1
		if t["best"] == null or int(row["wins"]) > int(t["best"]["wins"]):
			t["best"] = row
		if t["worst"] == null or int(row["wins"]) < int(t["worst"]["wins"]):
			t["worst"] = row
	var since_title := 0
	for i in range(log.size() - 1, -1, -1):
		if log[i]["champion"]:
			break
		since_title += 1
	t["drought"] = since_title
	var streak := 0
	for i in range(log.size() - 1, -1, -1):
		if not log[i]["playoffs"]:
			break
		streak += 1
	t["playoff_streak"] = streak
	return t


## Career rows of a player with one team: {"seasons", "first", "last", "points", "rebounds", "ast", "stl", "blk", "gp"}.
func with_team(player_id: int, team_id: int) -> Dictionary:
	var t := {"seasons": 0, "first": 0, "last": 0, "points": 0, "rebounds": 0, "ast": 0, "stl": 0, "blk": 0, "gp": 0}
	for row in world.careers.get(player_id, []):
		if int(row[1]) != team_id:
			continue
		t["seasons"] += 1
		if t["first"] == 0:
			t["first"] = int(row[0])
		t["last"] = int(row[0])
		t["gp"] += int(row[2])
		t["points"] += int(row[4])
		t["rebounds"] += int(row[11]) + int(row[12])
		t["ast"] += int(row[13])
		t["stl"] += int(row[14])
		t["blk"] += int(row[15])
	return t


## Every player's totals with one team, worked out in ONE pass over the careers and kept: {player id: with_team totals}.
func team_totals(team_id: int) -> Dictionary:
	if _team_cache.has(team_id):
		return _team_cache[team_id]
	var out := {}
	for pid in world.careers:
		var t := with_team(pid, team_id)
		if int(t["seasons"]) > 0:
			out[int(pid)] = t
	_team_cache[team_id] = out
	return out


## The team's all-time leaders in a stat ("points", "rebounds", "ast", "stl", "blk", "gp") while playing for it:
## [[total, player id, seasons with the team], ...], best first.
func leaders(team_id: int, stat: String, count: int = 5) -> Array:
	var out: Array = []
	var totals := team_totals(team_id)
	for pid in totals:
		if int(totals[pid][stat]) > 0:
			out.append([int(totals[pid][stat]), int(pid), int(totals[pid]["seasons"])])
	out.sort_custom(func(a, b) -> bool: return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	return out.slice(0, count)


## The team's best single seasons for a stat ("points", "rebounds", "ast", "stl", "blk"): [[total, player id, year], ...].
func season_records(team_id: int, stat: String, count: int = 5) -> Array:
	var out: Array = []
	for pid in world.careers:
		for row in world.careers[pid]:
			if int(row[1]) != team_id:
				continue
			var value := 0
			match stat:
				"points": value = int(row[4])
				"rebounds": value = int(row[11]) + int(row[12])
				"ast": value = int(row[13])
				"stl": value = int(row[14])
				"blk": value = int(row[15])
			out.append([value, int(pid), int(row[0])])
	out.sort_custom(func(a, b) -> bool: return a[0] > b[0] if a[0] != b[0] else (a[1] < b[1] if a[1] != b[1] else a[2] < b[2]))
	return out.slice(0, count)


## The team a player spent most seasons with (ties go to the team of his latest season), or 0 with no career rows.
func primary_team(player_id: int) -> int:
	var counts := {}
	var latest := 0
	for row in world.careers.get(player_id, []):
		counts[int(row[1])] = int(counts.get(int(row[1]), 0)) + 1
		latest = int(row[1])
	var best := 0
	var best_count := 0
	for tid in counts:
		if int(counts[tid]) > best_count or (int(counts[tid]) == best_count and int(tid) == latest):
			best = int(tid)
			best_count = int(counts[tid])
	return best


## The team's retired numbers as of `current_year`, in the order they were retired:
## [{"player_id", "number", "ceremony" (year), "seasons", "first", "last", "score"}].
func retired_numbers(team_id: int, current_year: int) -> Array[Dictionary]:
	var all := retired_numbers_all(current_year)
	var mine: Array[Dictionary] = []
	mine.assign(all.get(team_id, []))
	return mine


## Every franchise's retired numbers as of `current_year` from ONE pass over the careers (kept for the next call): {team id: [...]}.
func retired_numbers_all(current_year: int) -> Dictionary:
	if _retired_cache.has(current_year):
		return _retired_cache[current_year]
	var by_team := {}
	for pid in world.careers:
		var player: FcPlayer = world.players.get_by_id(pid)
		if player == null or player.status != FcPlayer.Status.RETIRED:
			continue
		var team_id := primary_team(pid)
		if team_id == 0:
			continue
		var t := with_team(pid, team_id)
		if int(t["seasons"]) < MIN_SEASONS:
			continue
		var ceremony: int = int(t["last"]) + 1
		if ceremony > current_year:
			continue
		var score := records.score_of(pid)
		if score < NUMBER_SCORE:
			continue
		if not by_team.has(team_id):
			by_team[team_id] = []
		(by_team[team_id] as Array).append({"player_id": int(pid), "number": 0, "ceremony": ceremony, "seasons": int(t["seasons"]),
			"first": int(t["first"]), "last": int(t["last"]), "score": score})
	for team_id in by_team:
		var honoured: Array = by_team[team_id]
		honoured.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["ceremony"] < b["ceremony"] if a["ceremony"] != b["ceremony"] else a["player_id"] < b["player_id"])
		var used := {}
		for h in honoured:
			var worn: FcPlayer = world.players.get_by_id(int(h["player_id"]))
			var number := worn.jersey_number if worn != null and worn.jersey_number > 0 else jersey_for(int(h["player_id"]))   # the number he wore
			while used.has(number):
				number = number % 99 + 1
			used[number] = true
			h["number"] = number
	_retired_cache[current_year] = by_team
	return by_team


## A player's preferred number, 1 to 99: a steady choice from his id, spread like real rosters (three players in four wear 1 to 35, the rest
## anything up to 99). A well-mixed hash (FNV-1a), so players with neighbouring ids do not bunch around the same numbers. Since data version 5
## players also have a stored number (FcPlayer.jersey_number, FcRosterNumbers); this is the preference it starts from.
static func jersey_for(player_id: int) -> int:
	var h := 2166136261
	for b in ("jersey:%d" % player_id).to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return (h >> 2) % 35 + 1 if h % 4 != 0 else (h >> 2) % 99 + 1
