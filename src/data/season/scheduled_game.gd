class_name FcScheduledGame
extends RefCounted
## One game of a season: when (day number, 0 = the first day of the season),
## who hosts whom, and once played the result. Playoff games carry the id of
## their series. Box scores are NOT stored here (a season has over a thousand
## games); the compact result and the accumulated player/team statistics are.
## Every game has a stable `id` from the world's id generator (kind "game", D-077 C2): reports, the ledger, the calendar and replays refer
## to a game by it. A played game also keeps a compact `line` (D-077 C6) while its season is held in detail:
##   {"q": [[home points per period], [away points per period]], "top": [[player id, points, rebounds, assists, team id], ...] (the three
##    best scorers of each team, home first), "pog": player id of the player of the game}.

const KIND := "game"

var id: int = 0
var day: int = 0
var home_id: int = 0
var away_id: int = 0
var played: bool = false
var home_score: int = 0
var away_score: int = 0
var overtimes: int = 0
## 0 for a regular-season game; otherwise the playoff series number.
var series: int = 0
var line: Dictionary = {}


func _init(game_day: int = 0, home: int = 0, away: int = 0) -> void:
	day = game_day
	home_id = home
	away_id = away


func winner_id() -> int:
	if not played:
		return 0
	return home_id if home_score > away_score else away_id


func loser_id() -> int:
	if not played:
		return 0
	return away_id if home_score > away_score else home_id


func involves(team_id: int) -> bool:
	return home_id == team_id or away_id == team_id


func to_dict() -> Dictionary:
	var d := {"d": day, "h": home_id, "a": away_id}
	if id > 0:
		d["id"] = id
	if not line.is_empty():
		d["ln"] = line.duplicate(true)
	if played:
		d["hs"] = home_score
		d["as"] = away_score
		if overtimes > 0:
			d["ot"] = overtimes
	if series > 0:
		d["s"] = series
	return d


static func from_dict(d: Dictionary) -> FcScheduledGame:
	var g := FcScheduledGame.new(int(d.get("d", 0)), int(d.get("h", 0)), int(d.get("a", 0)))
	g.played = d.has("hs")
	g.home_score = int(d.get("hs", 0))
	g.away_score = int(d.get("as", 0))
	g.overtimes = int(d.get("ot", 0))
	g.series = int(d.get("s", 0))
	g.id = int(d.get("id", 0))
	var raw_line = d.get("ln", {})
	if raw_line is Dictionary and not raw_line.is_empty():
		g.line = _clean_line(raw_line)
	return g


## JSON turns integers into floats; put the compact line's numbers back.
static func _clean_line(raw: Dictionary) -> Dictionary:
	var q: Array = []
	for side in raw.get("q", []):
		var periods: Array = []
		for v in side:
			periods.append(int(v))
		q.append(periods)
	var top: Array = []
	for row in raw.get("top", []):
		var r: Array = []
		for v in row:
			r.append(int(v))
		top.append(r)
	return {"q": q, "top": top, "pog": int(raw.get("pog", 0))}


## The compact line of a finished game from its box score: periods, the three best scorers of each side and the player of the game.
static func line_from_box(box: FcBoxScore) -> Dictionary:
	var top: Array = []
	var best_id := 0
	var best := -INF
	for side in 2:
		var players := box.players_of(side)
		players.sort_custom(func(a: FcPlayerGameStats, b: FcPlayerGameStats) -> bool: return a.points > b.points if a.points != b.points else a.player_id < b.player_id)
		for p in players.slice(0, 3):
			top.append([p.player_id, p.points, p.rebounds(), p.ast, p.team_id])
	var winner := 0 if box.scores[0] > box.scores[1] else 1
	for p in box.players_of(winner):
		var v := p.points + 1.2 * p.rebounds() + 1.5 * p.ast + 2.0 * (p.stl + p.blk) - p.tov
		if v > best or (v == best and p.player_id < best_id):
			best = v
			best_id = p.player_id
	return {"q": box.period_scores.duplicate(true), "top": top, "pog": best_id}
