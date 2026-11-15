class_name FcScheduledGame
extends RefCounted
## One game of a season: when (day number, 0 = the first day of the season),
## who hosts whom, and once played the result. Playoff games carry the id of
## their series. Box scores are NOT stored here (a season has over a thousand
## games); the compact result and the accumulated player/team statistics are.

var day: int = 0
var home_id: int = 0
var away_id: int = 0
var played: bool = false
var home_score: int = 0
var away_score: int = 0
var overtimes: int = 0
## 0 for a regular-season game; otherwise the playoff series number.
var series: int = 0


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
	return g
