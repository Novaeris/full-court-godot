class_name FcPlayoffs
extends RefCounted
## The playoff bracket of a season: who qualified (with seeds) and every
## series. Games themselves are FcScheduledGame entries in the season with
## `series` set to the series number.

## Each entry: {"team": id, "bracket": conference index or -1, "seed": int, "leader": bool, "rank": league rank}
var qualifiers: Array[Dictionary] = []
var series: Array[FcPlayoffSeries] = []
var rounds: int = 0
## Number of playoff days played so far (each day plays one game of every ready series).
var day: int = 0


func get_series(number: int) -> FcPlayoffSeries:
	for s in series:
		if s.number == number:
			return s
	return null


func series_in_round(round_number: int) -> Array[FcPlayoffSeries]:
	var out: Array[FcPlayoffSeries] = []
	for s in series:
		if s.round == round_number:
			out.append(s)
	return out


func ready_series() -> Array[FcPlayoffSeries]:
	var out: Array[FcPlayoffSeries] = []
	for s in series:
		if s.is_ready():
			out.append(s)
	return out


## The last series (the championship series), or null.
func final_series() -> FcPlayoffSeries:
	var best: FcPlayoffSeries = null
	for s in series:
		if best == null or s.round > best.round or (s.round == best.round and s.number > best.number):
			best = s
	return best


func is_complete() -> bool:
	var f := final_series()
	return f != null and f.is_complete()


func champion_id() -> int:
	var f := final_series()
	return f.winner_id if f != null and f.is_complete() else 0


func runner_up_id() -> int:
	var f := final_series()
	return f.loser_id() if f != null else 0


func qualified(team_id: int) -> bool:
	for q in qualifiers:
		if q["team"] == team_id:
			return true
	return false


func to_dict() -> Dictionary:
	var series_dicts: Array = []
	for s in series:
		series_dicts.append(s.to_dict())
	return {"qualifiers": qualifiers.duplicate(true), "series": series_dicts, "rounds": rounds, "day": day}


static func from_dict(d: Dictionary) -> FcPlayoffs:
	var p := FcPlayoffs.new()
	for q in d.get("qualifiers", []):
		p.qualifiers.append({"team": int(q["team"]), "bracket": int(q["bracket"]), "seed": int(q["seed"]), "leader": bool(q["leader"]), "rank": int(q["rank"])})
	for s in d.get("series", []):
		p.series.append(FcPlayoffSeries.from_dict(s))
	p.rounds = int(d.get("rounds", 0))
	p.day = int(d.get("day", 0))
	return p
