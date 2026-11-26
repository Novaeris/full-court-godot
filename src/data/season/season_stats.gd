class_name FcSeasonStats
extends RefCounted
## Accumulated counting statistics for every player over a set of games
## (a regular season, or a playoff run). Saved compactly. Leaders and
## per-game averages are computed from the totals.

const KEYS := ["gp", "seconds", "points", "fgm", "fga", "tpm", "tpa", "ftm", "fta",
	"oreb", "dreb", "ast", "stl", "blk", "tov", "pf"]
## Columns kept for the season only (not copied into career rows): games started and shots at the rim made and attempted (D-077: the
## shot chart shows the three shot kinds the simulation decides: at the rim, mid-range, three).
const EXTRA_KEYS := ["gs", "rim_m", "rim_a"]

## player id -> Dictionary with KEYS plus "team" (team id of his latest game) and "name"
var lines: Dictionary = {}


func add_box_score(box: FcBoxScore) -> void:
	for p in box.players:
		if p.seconds <= 0:
			continue
		if not lines.has(p.player_id):
			var blank := {"team": p.team_id, "name": p.name}
			for k in KEYS + EXTRA_KEYS:
				blank[k] = 0
			lines[p.player_id] = blank
		var l: Dictionary = lines[p.player_id]
		l["team"] = p.team_id
		l["gp"] += 1
		l["seconds"] += p.seconds
		l["points"] += p.points
		for k in ["fgm", "fga", "tpm", "tpa", "ftm", "fta", "oreb", "dreb", "ast", "stl", "blk", "tov", "pf"]:
			l[k] += int(p.get(k))
		l["gs"] += 1 if p.started else 0
		l["rim_m"] += p.rim_m
		l["rim_a"] += p.rim_a


func games_played(player_id: int) -> int:
	return int(lines.get(player_id, {}).get("gp", 0))


## Per-game average of a stat ("points", "rebounds", "ast", "minutes", ...).
func per_game(player_id: int, stat: String) -> float:
	if not lines.has(player_id):
		return 0.0
	var l: Dictionary = lines[player_id]
	var gp: int = l["gp"]
	if gp == 0:
		return 0.0
	match stat:
		"rebounds":
			return float(l["oreb"] + l["dreb"]) / gp
		"minutes":
			return l["seconds"] / 60.0 / gp
	return float(l[stat]) / gp


func percentage(player_id: int, made: String, attempted: String) -> float:
	var l: Dictionary = lines.get(player_id, {})
	return float(l.get(made, 0)) / maxf(1.0, float(l.get(attempted, 0)))


## Player ids sorted by a per-game stat, best first, among players with at
## least `min_games` games.
func leaders(stat: String, min_games: int = 1, count: int = 10) -> Array[int]:
	var ids: Array[int] = []
	for pid in lines:
		if lines[pid]["gp"] >= min_games:
			ids.append(int(pid))
	ids.sort_custom(func(a: int, b: int):
		var va := per_game(a, stat)
		var vb := per_game(b, stat)
		return va > vb if va != vb else a < b)
	return ids.slice(0, count)


func to_dict() -> Dictionary:
	var out := {}
	for pid in lines:
		var l: Dictionary = lines[pid]
		var row: Array = [l["team"], l["name"]]
		for k in KEYS:
			row.append(l[k])
		for k in EXTRA_KEYS:
			row.append(int(l.get(k, 0)))
		out[str(pid)] = row
	return out


static func from_dict(d: Dictionary) -> FcSeasonStats:
	var s := FcSeasonStats.new()
	for pid in d:
		var row: Array = d[pid]
		var l := {"team": int(row[0]), "name": str(row[1])}
		for i in KEYS.size():
			l[KEYS[i]] = int(row[2 + i])
		for i in EXTRA_KEYS.size():   # seasons saved before these columns existed read as zero
			l[EXTRA_KEYS[i]] = int(row[2 + KEYS.size() + i]) if row.size() > 2 + KEYS.size() + i else 0
		s.lines[int(pid)] = l
	return s
