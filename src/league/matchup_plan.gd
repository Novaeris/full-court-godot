class_name FcMatchupPlan
extends RefCounted
## The result of FcMatchupPlanner: for every pair of teams, how many games
## they play and who hosts how many. Not a calendar (no dates yet), just the
## "who plays whom how often, home or away" that any calendar must follow.

## Each entry: {"a": team id, "b": team id, "games": int, "a_home": int, "b_home": int}
var pairs: Array[Dictionary] = []

var _games: Dictionary = {}
var _home: Dictionary = {}


func _add(a: int, b: int, games: int, a_home: int, b_home: int) -> void:
	pairs.append({"a": a, "b": b, "games": games, "a_home": a_home, "b_home": b_home})
	_games[a] = int(_games.get(a, 0)) + games
	_games[b] = int(_games.get(b, 0)) + games
	_home[a] = int(_home.get(a, 0)) + a_home
	_home[b] = int(_home.get(b, 0)) + b_home


func games_of(team_id: int) -> int:
	return int(_games.get(team_id, 0))


func home_games_of(team_id: int) -> int:
	return int(_home.get(team_id, 0))


func away_games_of(team_id: int) -> int:
	return games_of(team_id) - home_games_of(team_id)


## Total games in the season (each game counted once).
func total_games() -> int:
	var total := 0
	for p in pairs:
		total += int(p["games"])
	return total


## Largest |home - away| over all teams. 0 or 1 means perfectly fair.
func max_home_away_gap() -> int:
	var worst := 0
	for tid in _games:
		worst = maxi(worst, absi(home_games_of(tid) - away_games_of(tid)))
	return worst


func games_per_team_range() -> Vector2i:
	var low := 1 << 30
	var high := 0
	for tid in _games:
		low = mini(low, int(_games[tid]))
		high = maxi(high, int(_games[tid]))
	return Vector2i(low, high)
