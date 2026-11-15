class_name FcStandings
extends RefCounted
## League standings computed from played regular-season games.
##
## Ranking (the order of tiebreakers, applied only while teams stay tied):
##   1. winning percentage
##   2. head-to-head record among the tied teams
##   3. record against their own division (only if all tied teams share a division)
##   4. record against their own conference
##   5. point differential
##   6. team id (a fixed stand-in for a coin flip, so results never change on reload)
## This is a simplified version of professional-league tiebreaker rules.

var league: FcLeague
## team id -> record Dictionary (see _blank())
var records: Dictionary = {}


static func compute(for_league: FcLeague, games: Array[FcScheduledGame]) -> FcStandings:
	var s := FcStandings.new()
	s.league = for_league
	for tid in for_league.all_team_ids():
		s.records[tid] = _blank()
	for g in games:
		if g.played and g.series == 0 and s.records.has(g.home_id) and s.records.has(g.away_id):
			s._add_game(g)
	return s


static func _blank() -> Dictionary:
	return {"w": 0, "l": 0, "home_w": 0, "home_l": 0, "away_w": 0, "away_l": 0,
		"div_w": 0, "div_l": 0, "conf_w": 0, "conf_l": 0, "pf": 0, "pa": 0,
		"h2h": {}, "streak": 0, "results": []}


func _add_game(g: FcScheduledGame) -> void:
	var home_won := g.home_score > g.away_score
	var same_division := league.division_of_team(g.home_id) == league.division_of_team(g.away_id)
	var same_conference := league.conference_of_team(g.home_id) == league.conference_of_team(g.away_id)
	for side in 2:
		var team := g.home_id if side == 0 else g.away_id
		var other := g.away_id if side == 0 else g.home_id
		var won := home_won if side == 0 else not home_won
		var r: Dictionary = records[team]
		r["w" if won else "l"] += 1
		r[("home_" if side == 0 else "away_") + ("w" if won else "l")] += 1
		if same_division:
			r["div_w" if won else "div_l"] += 1
		if same_conference:
			r["conf_w" if won else "conf_l"] += 1
		r["pf"] += g.home_score if side == 0 else g.away_score
		r["pa"] += g.away_score if side == 0 else g.home_score
		if not r["h2h"].has(other):
			r["h2h"][other] = [0, 0]
		r["h2h"][other][0 if won else 1] += 1
		r["results"].append(won)
		var streak: int = r["streak"]
		if won:
			r["streak"] = streak + 1 if streak > 0 else 1
		else:
			r["streak"] = streak - 1 if streak < 0 else -1


func games_played(team_id: int) -> int:
	var r: Dictionary = records[team_id]
	return r["w"] + r["l"]


func win_pct(team_id: int) -> float:
	var g := games_played(team_id)
	return float(records[team_id]["w"]) / g if g > 0 else 0.0


func point_differential(team_id: int) -> int:
	return records[team_id]["pf"] - records[team_id]["pa"]


## Record against the last ten games as [wins, losses].
func last_ten(team_id: int) -> Array[int]:
	var results: Array = records[team_id]["results"]
	var wins := 0
	var count := mini(10, results.size())
	for i in count:
		if results[results.size() - 1 - i]:
			wins += 1
	return [wins, count - wins]


## Text like "W3" or "L2".
func streak_text(team_id: int) -> String:
	var s: int = records[team_id]["streak"]
	return "-" if s == 0 else ("W%d" % s if s > 0 else "L%d" % -s)


## Games behind the leader of a ranked list (half-games).
func games_behind(leader_id: int, team_id: int) -> float:
	var a: Dictionary = records[leader_id]
	var b: Dictionary = records[team_id]
	return ((a["w"] - b["w"]) + (b["l"] - a["l"])) / 2.0


## Teams sorted best first, applying the tiebreakers.
func ranked(team_ids: Array) -> Array[int]:
	var ids: Array[int] = []
	for t in team_ids:
		ids.append(int(t))
	# group by exact winning percentage
	ids.sort_custom(func(a: int, b: int): return _compare_pct(a, b) > 0)
	var out: Array[int] = []
	var i := 0
	while i < ids.size():
		var j := i + 1
		while j < ids.size() and _compare_pct(ids[i], ids[j]) == 0:
			j += 1
		var group := ids.slice(i, j)
		out.append_array(_break_ties(group) if group.size() > 1 else group)
		i = j
	return out


func league_ranking() -> Array[int]:
	return ranked(league.all_team_ids())


func conference_ranking(conference: FcConference) -> Array[int]:
	var ids: Array = []
	for d in conference.divisions:
		ids.append_array(d.team_ids)
	return ranked(ids)


func division_ranking(division: FcDivision) -> Array[int]:
	return ranked(division.team_ids)


## Division id -> team id of the division leader.
func division_leaders() -> Dictionary:
	var out := {}
	for d in league.all_divisions():
		var order := division_ranking(d)
		if not order.is_empty():
			out[d.id] = order[0]
	return out


# --- tiebreaks ---------------------------------------------------------------

## > 0 if a has the better winning percentage, 0 if equal.
func _compare_pct(a: int, b: int) -> int:
	var ga := games_played(a)
	var gb := games_played(b)
	var lhs: int = records[a]["w"] * gb
	var rhs: int = records[b]["w"] * ga
	if ga == 0 or gb == 0:
		return 0 if ga == gb else (1 if ga > gb else -1)
	return signi(lhs - rhs)


func _break_ties(group: Array[int]) -> Array[int]:
	var same_division := true
	var first_division := league.division_of_team(group[0])
	for t in group:
		if league.division_of_team(t) != first_division:
			same_division = false
	var keys := {}
	for t in group:
		var h2h_w := 0
		var h2h_g := 0
		for other in group:
			if other != t and records[t]["h2h"].has(other):
				h2h_w += records[t]["h2h"][other][0]
				h2h_g += records[t]["h2h"][other][0] + records[t]["h2h"][other][1]
		var h2h_pct := float(h2h_w) / h2h_g if h2h_g > 0 else 0.5
		var r: Dictionary = records[t]
		var div_games: int = r["div_w"] + r["div_l"]
		var conf_games: int = r["conf_w"] + r["conf_l"]
		var div_pct := float(r["div_w"]) / div_games if (same_division and div_games > 0) else 0.5
		var conf_pct := float(r["conf_w"]) / conf_games if conf_games > 0 else 0.5
		keys[t] = [h2h_pct, div_pct, conf_pct, float(point_differential(t)), -float(t)]
	var sorted := group.duplicate()
	sorted.sort_custom(func(a: int, b: int):
		for i in 5:
			if not is_equal_approx(keys[a][i], keys[b][i]):
				return keys[a][i] > keys[b][i]
		return false)
	return sorted
