class_name FcBoxScore
extends RefCounted
## The result of one simulated game: final score, scores by period, every
## player's line, and team totals with advanced statistics. Side 0 is the
## home team, side 1 the away team.

var team_ids: Array[int] = [0, 0]
var team_names: Array[String] = ["", ""]
var abbreviations: Array[String] = ["", ""]
## Points per period for each side (4 regulation periods, then overtimes).
var period_scores: Array = [[], []]
var scores: Array[int] = [0, 0]
var players: Array[FcPlayerGameStats] = []
## Possessions estimated the standard way, per side.
var possessions: Array[float] = [0.0, 0.0]
var overtimes: int = 0
## Injuries suffered in this game: [[player id, games out, injury name], ...].
var injuries: Array = []


func winner_side() -> int:
	if scores[0] == scores[1]:
		return -1
	return 0 if scores[0] > scores[1] else 1


func winner_team_id() -> int:
	var s := winner_side()
	return team_ids[s] if s >= 0 else 0


func players_of(side: int) -> Array[FcPlayerGameStats]:
	var out: Array[FcPlayerGameStats] = []
	for p in players:
		if p.team_id == team_ids[side]:
			out.append(p)
	return out


## Team totals for one side as a Dictionary of the same counting stats.
func team_totals(side: int) -> Dictionary:
	var t := {"points": 0, "fgm": 0, "fga": 0, "tpm": 0, "tpa": 0, "ftm": 0, "fta": 0,
		"oreb": 0, "dreb": 0, "ast": 0, "stl": 0, "blk": 0, "tov": 0, "pf": 0, "seconds": 0}
	for p in players_of(side):
		for key in t:
			t[key] += int(p.get(key))
	return t


## Advanced statistics for one side: possessions, ratings per 100 possessions,
## shooting efficiency, rebound and turnover rates, pace.
func advanced(side: int) -> Dictionary:
	var t := team_totals(side)
	var o := team_totals(1 - side)
	var poss: float = t["fga"] + 0.44 * t["fta"] - t["oreb"] + t["tov"]
	var opp_poss: float = o["fga"] + 0.44 * o["fta"] - o["oreb"] + o["tov"]
	var avg_poss: float = (poss + opp_poss) / 2.0
	var minutes: float = t["seconds"] / 300.0
	return {
		"possessions": avg_poss,
		"offensive_rating": 100.0 * t["points"] / maxf(1.0, avg_poss),
		"defensive_rating": 100.0 * o["points"] / maxf(1.0, avg_poss),
		"pace": 48.0 * avg_poss / maxf(1.0, minutes),
		"efg": (t["fgm"] + 0.5 * t["tpm"]) / maxf(1.0, t["fga"]),
		"true_shooting": t["points"] / (2.0 * maxf(1.0, t["fga"] + 0.44 * t["fta"])),
		"turnover_rate": t["tov"] / maxf(1.0, poss),
		"offensive_rebound_rate": t["oreb"] / maxf(1.0, t["oreb"] + o["dreb"]),
		"free_throw_rate": t["fta"] / maxf(1.0, t["fga"]),
		"three_point_rate": t["tpa"] / maxf(1.0, t["fga"]),
		"assist_rate": t["ast"] / maxf(1.0, t["fgm"]),
	}


## A one-line result, e.g. "HOU 112, PHO 104 (final)".
func summary() -> String:
	var tail := " (final)" if overtimes == 0 else " (final, %d OT)" % overtimes
	return "%s %d, %s %d%s" % [abbreviations[0], scores[0], abbreviations[1], scores[1], tail]


## Player lines as a table for printing, best scorers first.
func table(side: int) -> String:
	var lines: Array[String] = ["%-22s %2s %5s %5s %5s %5s %4s %3s %3s %3s %3s %3s %3s %4s" % [
		team_names[side], "", "MIN", "PTS", "FG", "3P", "FT", "REB", "AST", "STL", "BLK", "TO", "PF", "+/-"]]
	var list := players_of(side)
	list.sort_custom(func(a: FcPlayerGameStats, b: FcPlayerGameStats): return a.seconds > b.seconds)
	for p in list:
		if p.seconds == 0:
			continue
		lines.append("%-22s %2s %5.1f %5d %2d-%-2d %2d-%-2d %2d-%-2d %3d %3d %3d %3d %3d %3d %+4d" % [
			p.name, FcPosition.abbreviation(p.position), p.minutes(), p.points, p.fgm, p.fga, p.tpm, p.tpa,
			p.ftm, p.fta, p.rebounds(), p.ast, p.stl, p.blk, p.tov, p.pf, p.plus_minus])
	return "\n".join(lines)


func to_dict() -> Dictionary:
	var player_dicts: Array = []
	for p in players:
		player_dicts.append(p.to_dict())
	return {
		"team_ids": team_ids.duplicate(), "team_names": team_names.duplicate(),
		"abbreviations": abbreviations.duplicate(), "period_scores": period_scores.duplicate(true),
		"scores": scores.duplicate(), "players": player_dicts, "overtimes": overtimes,
		"injuries": injuries.duplicate(true),
	}


static func from_dict(d: Dictionary) -> FcBoxScore:
	var b := FcBoxScore.new()
	for i in 2:
		b.team_ids[i] = int(d["team_ids"][i])
		b.team_names[i] = str(d["team_names"][i])
		b.abbreviations[i] = str(d["abbreviations"][i])
		b.scores[i] = int(d["scores"][i])
		b.period_scores[i] = []
		for v in d["period_scores"][i]:
			b.period_scores[i].append(int(v))
	b.overtimes = int(d.get("overtimes", 0))
	for row in d.get("injuries", []):
		b.injuries.append([int(row[0]), int(row[1]), str(row[2])])
	for pd in d.get("players", []):
		b.players.append(FcPlayerGameStats.from_dict(pd))
	return b
