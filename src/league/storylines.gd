class_name FcStorylines
extends RefCounted
## League-wide storylines: the headlines of the league's history, worked out from the finished seasons and the careers the world keeps
## forever. Nothing is stored (same idea as FcRecords); each item is {"year", "kind", "headline", "text", "team_ids", "player_ids", "weight"}
## and the list is ordered newest year first, then by weight (the bigger story first).
##
## Kinds: dynasty (back-to-back and three-peat titles), drought (a title after many seasons without one), worst_to_first (a bottom team
## that wins it all the next year), cinderella (a low seed that wins the title), collapse (the champion misses the playoffs the year
## after), mvp (a repeat MVP), record (a new single-season league record), legend (a great player retires), jersey (a number is retired),
## rivalry (a rivalry grows to heated or bitter).

const DROUGHT_SEASONS := 10
const WORST_TO_FIRST_RANK_FRACTION := 0.6
const CINDERELLA_RANK := 5

var world: FcWorld
var league_id: int
var _history: FcFranchiseHistory
var _rivalries: FcRivalries
var _items: Array[Dictionary] = []
var _champion_by_year: Dictionary = {}


func _init(game_world: FcWorld, league: int, current_year: int = 9999) -> void:
	world = game_world
	league_id = league
	_history = FcFranchiseHistory.new(world, league_id)
	_rivalries = FcRivalries.new(world, league_id)
	_build(current_year)


## Every storyline, newest first.
func all() -> Array[Dictionary]:
	return _items


## The latest `count` storylines.
func recent(count: int = 8) -> Array[Dictionary]:
	return _items.slice(0, count)


## Storylines that involve a team.
func for_team(team_id: int, count: int = 8) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in _items:
		if (item["team_ids"] as Array).has(team_id):
			out.append(item)
	return out.slice(0, count)


## Storylines that involve a player.
func for_player(player_id: int, count: int = 8) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in _items:
		if (item["player_ids"] as Array).has(player_id):
			out.append(item)
	return out.slice(0, count)


# --- building -----------------------------------------------------------------------------------------------------------

func _build(current_year: int) -> void:
	var seasons := _history.seasons()
	var title_years := {}      # team id -> [years]
	var mvp_years := {}        # player id -> [years]
	var first_year := seasons[0].year if not seasons.is_empty() else 0
	for season in seasons:
		_champion_by_year[season.year] = season.champion_id
	var previous: FcSeason = null
	for s in seasons:
		if s.year > current_year:
			break
		_season_stories(s, previous, title_years, first_year)
		_mvp_story(s, mvp_years)
		previous = s
	_record_stories(current_year)
	_legend_stories(current_year)
	_jersey_stories(current_year)
	_rivalry_stories(current_year)
	_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["year"] != b["year"]:
			return a["year"] > b["year"]
		if a["weight"] != b["weight"]:
			return a["weight"] > b["weight"]
		return str(a["headline"]) < str(b["headline"]))


func _add(year: int, kind: String, headline: String, text: String, teams: Array, players: Array, weight: int) -> void:
	_items.append({"year": year, "kind": kind, "headline": headline, "text": text, "team_ids": teams, "player_ids": players, "weight": weight})


func _team(team_id: int) -> String:
	return world.team_display_name(team_id)


func _season_stories(s: FcSeason, previous: FcSeason, title_years: Dictionary, first_year: int) -> void:
	var champion := s.champion_id
	if champion > 0:
		var years: Array = title_years.get(champion, [])
		var streak := 1   # this title plus the titles won in the years just before it
		while streak < 20 and int(_champion_by_year.get(s.year - streak, 0)) == champion:
			streak += 1
		if streak >= 3:
			_add(s.year, "dynasty", "%s win a %s straight title" % [_team(champion), _ordinal(streak)], "%s have now won %d championships in a row: a dynasty." % [_team(champion), streak], [champion], [], 95)
		elif streak == 2:
			_add(s.year, "dynasty", "%s repeat as champions" % _team(champion), "Back-to-back titles for %s." % _team(champion), [champion], [], 70)
		else:
			var last_title := 0
			for y in years:
				last_title = maxi(last_title, int(y))
			var wait := s.year - last_title if last_title > 0 else s.year - first_year
			if wait >= DROUGHT_SEASONS:
				_add(s.year, "drought", "%s end a %d-season wait for a title" % [_team(champion), wait], "%s are champions for the first time in %d seasons." % [_team(champion), wait], [champion], [], 82)
		years.append(s.year)
		title_years[champion] = years
		var rank := _rank_in(s, champion)
		var size := s.final_standings.size()
		if rank >= CINDERELLA_RANK and size >= 8:
			_add(s.year, "cinderella", "%s win it all from the %s seed" % [_team(champion), _ordinal(rank)], "Ranked only %d of %d after the regular season, %s still took the title." % [rank, size, _team(champion)], [champion], [], 60)
		if previous != null:
			var before := _rank_in(previous, champion)
			if before > 0 and before >= ceili(previous.final_standings.size() * WORST_TO_FIRST_RANK_FRACTION):
				_add(s.year, "worst_to_first", "%s go from %d of %d to champions" % [_team(champion), before, previous.final_standings.size()], "One year after finishing %d of %d, %s are champions." % [before, previous.final_standings.size(), _team(champion)], [champion], [], 88)
	if previous != null and previous.champion_id > 0 and s.playoffs != null and not s.playoffs.qualified(previous.champion_id) and _rank_in(s, previous.champion_id) > 0:
		_add(s.year, "collapse", "%s fall from champions to the lottery" % _team(previous.champion_id), "The defending champions %s did not even reach the playoffs." % _team(previous.champion_id), [previous.champion_id], [], 50)


func _mvp_story(s: FcSeason, mvp_years: Dictionary) -> void:
	var mvp := int(s.awards.get("mvp", 0))
	if mvp <= 0:
		return
	var years: Array = mvp_years.get(mvp, [])
	years.append(s.year)
	mvp_years[mvp] = years
	var count := years.size()
	if count < 2:
		return
	var consecutive := int(years[count - 2]) == s.year - 1
	var name := world.player_name(mvp)
	if count == 2 and consecutive:
		_add(s.year, "mvp", "%s wins a second straight MVP" % name, "%s is the league's best player again." % name, [], [mvp], 66)
	elif count >= 3:
		_add(s.year, "mvp", "%s wins MVP for the %s time" % [name, _ordinal(count)], "%s adds another MVP to a legendary career." % name, [], [mvp], 78)


func _record_stories(current_year: int) -> void:
	for entry in [["points", "points"], ["rebounds", "rebounds"], ["ast", "assists"]]:
		var best := _history.records.single_season_records(entry[0], 1)
		if best.is_empty():
			continue
		var year := int(best[0][2])
		if year > current_year:
			continue
		var pid := int(best[0][1])
		_add(year, "record", "%s sets the single-season %s record" % [world.player_name(pid), entry[1]], "%d %s in one season is the most the league has seen." % [best[0][0], entry[1]], [], [pid], 75)


func _legend_stories(current_year: int) -> void:
	for pid in world.careers:
		var p: FcPlayer = world.players.get_by_id(pid)
		if p == null or p.status != FcPlayer.Status.RETIRED or p.retired_season > current_year:
			continue
		var score := _history.records.score_of(pid)
		if score < FcFranchiseHistory.NUMBER_SCORE:
			continue
		var t := world.career_totals(pid)
		var hall := score >= FcRecords.INDUCTION_SCORE
		_add(p.retired_season, "legend", "%s retires after %d seasons" % [world.player_name(pid), t["seasons"]], "%d points, %d rebounds and %d assists over a career%s." % [t["points"], t["rebounds"], t["ast"], ", a certain Hall of Famer" if hall else ""], [], [int(pid)], 85 if hall else 55)


func _jersey_stories(current_year: int) -> void:
	var all := _history.retired_numbers_all(current_year)
	for team_id in all:
		for h in all[team_id]:
			_add(int(h["ceremony"]), "jersey", "%s retire #%d for %s" % [_team(team_id), h["number"], world.player_name(int(h["player_id"]))], "%d seasons (%d-%d) with %s earn the highest honour a franchise has." % [h["seasons"], h["first"], h["last"], _team(team_id)], [team_id], [int(h["player_id"])], 65)


func _rivalry_stories(current_year: int) -> void:
	for r in _rivalries.all():
		var previous_level := ""
		for step in _rivalries.development(int(r["a"]), int(r["b"])):
			if int(step["year"]) > current_year:
				break
			var level := str(step["level"])
			if level != previous_level and (level == "Heated" or level == "Bitter"):
				_add(int(step["year"]), "rivalry", "%s and %s: a %s rivalry" % [_team(int(r["a"])), _team(int(r["b"])), level.to_lower()], _rivalries.headline_of(_rivalries.summary_of(int(r["a"]), int(r["b"]))), [int(r["a"]), int(r["b"])], [], 55 if level == "Heated" else 68)
			previous_level = level


func _rank_in(s: FcSeason, team_id: int) -> int:
	for i in s.final_standings.size():
		if int(s.final_standings[i][0]) == team_id:
			return i + 1
	return 0


static func _ordinal(n: int) -> String:
	var tail := n % 100
	var suffix := "th"
	if tail < 11 or tail > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]
