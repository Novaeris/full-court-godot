class_name FcPlayerGameStats
extends RefCounted
## One player's line in a game's box score.

var player_id: int = 0
var team_id: int = 0
var name: String = ""
var position: int = 0
var started: bool = false
var seconds: int = 0
var points: int = 0
var fgm: int = 0
var fga: int = 0
var tpm: int = 0
var tpa: int = 0
var ftm: int = 0
var fta: int = 0
var oreb: int = 0
var dreb: int = 0
var ast: int = 0
var stl: int = 0
var blk: int = 0
var tov: int = 0
var pf: int = 0
var plus_minus: int = 0


func rebounds() -> int:
	return oreb + dreb


func minutes() -> float:
	return seconds / 60.0


func to_dict() -> Dictionary:
	return {
		"player_id": player_id, "team_id": team_id, "name": name, "position": position,
		"started": started, "seconds": seconds, "points": points, "fgm": fgm, "fga": fga,
		"tpm": tpm, "tpa": tpa, "ftm": ftm, "fta": fta, "oreb": oreb, "dreb": dreb,
		"ast": ast, "stl": stl, "blk": blk, "tov": tov, "pf": pf, "plus_minus": plus_minus,
	}


static func from_dict(d: Dictionary) -> FcPlayerGameStats:
	var s := FcPlayerGameStats.new()
	s.player_id = int(d.get("player_id", 0))
	s.team_id = int(d.get("team_id", 0))
	s.name = str(d.get("name", ""))
	s.position = int(d.get("position", 0))
	s.started = bool(d.get("started", false))
	for key in ["seconds", "points", "fgm", "fga", "tpm", "tpa", "ftm", "fta", "oreb", "dreb", "ast", "stl", "blk", "tov", "pf", "plus_minus"]:
		s.set(key, int(d.get(key, 0)))
	return s
