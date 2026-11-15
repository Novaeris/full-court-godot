class_name FcPlayoffSeries
extends RefCounted
## One best-of-N series in the playoff bracket. Teams A and B are filled in as
## earlier series finish (`source_a` / `source_b` name the series that feed
## this one; 0 means the team was fixed when the bracket was built).

var number: int = 0
## 1-based round across the whole playoffs (conference rounds first, then the final stage).
var round: int = 1
## "conference" (inside one conference's bracket), "finals" (conference champions
## meet), or "league" (one bracket for the whole league).
var stage: String = "league"
## Conference index for conference-stage series; -1 otherwise.
var bracket: int = -1
var best_of: int = 7
var team_a: int = 0
var team_b: int = 0
## Position in the regular-season league ranking (1 = best record); decides home court.
var rank_a: int = 0
var rank_b: int = 0
var seed_a: int = 0
var seed_b: int = 0
var source_a: int = 0
var source_b: int = 0
var wins_a: int = 0
var wins_b: int = 0
var winner_id: int = 0
## True for a first-round bye: the single team advances with no games.
var is_bye: bool = false


func wins_needed() -> int:
	return floori(best_of / 2.0) + 1


func is_complete() -> bool:
	return winner_id > 0


func is_ready() -> bool:
	return not is_complete() and team_a > 0 and team_b > 0


func games_played() -> int:
	return wins_a + wins_b


## The team with the better regular-season record hosts games 1 and 2 (and 5, 7).
func higher_team() -> int:
	return team_a if rank_a <= rank_b else team_b


## Home team of the next game: 2-2-1-1-1 for best-of-7, 2-2-1 for 5, 1-1-1 for 3.
func next_home_team() -> int:
	var higher := higher_team()
	var lower := team_b if higher == team_a else team_a
	var pattern: Array = {7: [1, 1, 0, 0, 1, 0, 1], 5: [1, 1, 0, 0, 1], 3: [1, 0, 1], 1: [1]}.get(best_of, [1])
	var index := mini(games_played(), pattern.size() - 1)
	return higher if pattern[index] == 1 else lower


## Records a game result; returns true if the series is now decided.
func record_game(winner_team: int) -> bool:
	if winner_team == team_a:
		wins_a += 1
	else:
		wins_b += 1
	if wins_a >= wins_needed():
		winner_id = team_a
	elif wins_b >= wins_needed():
		winner_id = team_b
	return is_complete()


func loser_id() -> int:
	if not is_complete() or is_bye:
		return 0
	return team_b if winner_id == team_a else team_a


func to_dict() -> Dictionary:
	return {
		"n": number, "r": round, "st": stage, "br": bracket, "bo": best_of,
		"a": team_a, "b": team_b, "ra": rank_a, "rb": rank_b, "sa": seed_a, "sb": seed_b,
		"fa": source_a, "fb": source_b, "wa": wins_a, "wb": wins_b, "w": winner_id, "bye": is_bye,
	}


static func from_dict(d: Dictionary) -> FcPlayoffSeries:
	var s := FcPlayoffSeries.new()
	s.number = int(d.get("n", 0))
	s.round = int(d.get("r", 1))
	s.stage = str(d.get("st", "league"))
	s.bracket = int(d.get("br", -1))
	s.best_of = int(d.get("bo", 7))
	s.team_a = int(d.get("a", 0))
	s.team_b = int(d.get("b", 0))
	s.rank_a = int(d.get("ra", 0))
	s.rank_b = int(d.get("rb", 0))
	s.seed_a = int(d.get("sa", 0))
	s.seed_b = int(d.get("sb", 0))
	s.source_a = int(d.get("fa", 0))
	s.source_b = int(d.get("fb", 0))
	s.wins_a = int(d.get("wa", 0))
	s.wins_b = int(d.get("wb", 0))
	s.winner_id = int(d.get("w", 0))
	s.is_bye = bool(d.get("bye", false))
	return s
