extends SceneTree
## Simulates many games and checks the results look like real basketball.
##
## Run (PowerShell, from the project folder):
##   ./tools/simulate_games.ps1                  1000 games, seed 2026
##   ./tools/simulate_games.ps1 games=5000 seed=7
##   ./tools/simulate_games.ps1 box              print one full box score
##   ./tools/simulate_games.ps1 mirror           equal teams: measures home-court advantage
## It builds the default league, plays random matchups, and prints league
## averages next to realistic target ranges (OK / CHECK), the spread of
## scores, how well better teams win, and sample extremes.

const TARGETS := [
	# label, key, low, high, format
	["Points per team", "points", 105.0, 118.0, "%.1f"],
	["Pace (possessions / 48 min)", "pace", 93.0, 103.0, "%.1f"],
	["Field goal %", "fg_pct", 0.440, 0.490, "%.3f"],
	["Three-point %", "tp_pct", 0.340, 0.385, "%.3f"],
	["Three-point attempts / FGA", "tp_rate", 0.33, 0.43, "%.3f"],
	["Free throw %", "ft_pct", 0.740, 0.810, "%.3f"],
	["Free throw attempts", "fta", 19.0, 26.0, "%.1f"],
	["Rebounds", "reb", 41.0, 47.0, "%.1f"],
	["Offensive rebound %", "oreb_pct", 0.21, 0.29, "%.3f"],
	["Assists", "ast", 21.0, 28.0, "%.1f"],
	["Turnovers", "tov", 11.5, 15.5, "%.1f"],
	["Steals", "stl", 6.0, 9.0, "%.1f"],
	["Blocks", "blk", 4.0, 6.5, "%.1f"],
	["Personal fouls", "pf", 17.0, 23.0, "%.1f"],
	["Effective FG %", "efg", 0.500, 0.560, "%.3f"],
	["Overtime games %", "ot_pct", 0.02, 0.09, "%.3f"],
]


func _initialize() -> void:
	var games := 1000
	var seed_value := 2026
	var show_box := false
	var mirror := false
	for arg in OS.get_cmdline_user_args():
		if arg == "box":
			show_box = true
			continue
		if arg == "mirror":
			mirror = true
			continue
		var parts: PackedStringArray = arg.split("=", true, 1)
		if parts.size() == 2 and parts[0] == "games":
			games = int(parts[1])
		elif parts.size() == 2 and parts[0] == "seed":
			seed_value = int(parts[1])

	var gen := FcWorldGenerator.create_default()
	var world := gen.generate(seed_value)
	var ratings := FcPlayerRatings.load_default()
	var teams: Array[FcGameTeam] = []
	for tid in world.teams.ids():
		teams.append(FcGameTeam.from_world(world, tid, ratings))
	var sim := FcGameSimulator.new()
	var rng := FcRng.new(seed_value).fork("games")

	if show_box:
		var box := sim.simulate(teams[0], teams[1], rng)
		_print_box(box)
		quit(0)
		return
	if mirror:
		_mirror_test(sim, rng, FcGameTeam.from_world(world, teams[0].team_id, ratings), FcGameTeam.from_world(world, teams[0].team_id, ratings), games)
		quit(0)
		return

	var totals := {}
	var team_games := 0
	var wins := {}
	var played := {}
	var margins: Array = []
	var home_wins := 0
	var overtime := 0
	var highest := 0
	var lowest := 999
	var top_scorer := 0
	var t0 := Time.get_ticks_msec()
	for g in games:
		var home_index := rng.range_int(0, teams.size() - 1)
		var away_index := rng.range_int(0, teams.size() - 2)
		if away_index >= home_index:
			away_index += 1
		var box := sim.simulate(teams[home_index], teams[away_index], rng)
		for side in 2:
			var t := box.team_totals(side)
			var adv := box.advanced(side)
			team_games += 1
			for key in ["points", "fgm", "fga", "tpm", "tpa", "ftm", "fta", "oreb", "dreb", "ast", "stl", "blk", "tov", "pf"]:
				totals[key] = float(totals.get(key, 0.0)) + t[key]
			totals["pace"] = float(totals.get("pace", 0.0)) + adv["pace"]
			totals["opp_dreb"] = float(totals.get("opp_dreb", 0.0)) + box.team_totals(1 - side)["dreb"]
			highest = maxi(highest, box.scores[side])
			lowest = mini(lowest, box.scores[side])
			for p in box.players_of(side):
				top_scorer = maxi(top_scorer, p.points)
		var winner := box.winner_team_id()
		wins[winner] = int(wins.get(winner, 0)) + 1
		played[box.team_ids[0]] = int(played.get(box.team_ids[0], 0)) + 1
		played[box.team_ids[1]] = int(played.get(box.team_ids[1], 0)) + 1
		if box.winner_side() == 0:
			home_wins += 1
		if box.overtimes > 0:
			overtime += 1
		margins.append(absi(box.scores[0] - box.scores[1]))
	var seconds := (Time.get_ticks_msec() - t0) / 1000.0

	var n := float(team_games)
	var avg := {
		"points": totals["points"] / n, "pace": totals["pace"] / n,
		"fg_pct": totals["fgm"] / totals["fga"], "tp_pct": totals["tpm"] / totals["tpa"],
		"tp_rate": totals["tpa"] / totals["fga"], "ft_pct": totals["ftm"] / totals["fta"],
		"fta": totals["fta"] / n, "reb": (totals["oreb"] + totals["dreb"]) / n,
		"oreb_pct": totals["oreb"] / (totals["oreb"] + totals["opp_dreb"]),
		"ast": totals["ast"] / n, "tov": totals["tov"] / n, "stl": totals["stl"] / n,
		"blk": totals["blk"] / n, "pf": totals["pf"] / n,
		"efg": (totals["fgm"] + 0.5 * totals["tpm"]) / totals["fga"],
		"ot_pct": float(overtime) / games,
	}
	print("=== %d games simulated in %.1f s (%.1f ms per game), seed %d ===" % [games, seconds, seconds * 1000.0 / games, seed_value])
	print("")
	print("%-32s %9s   %-17s %s" % ["League average (per team)", "Result", "Realistic range", ""])
	var flagged := 0
	for row in TARGETS:
		var v: float = avg[row[1]]
		var ok: bool = v >= row[2] and v <= row[3]
		if not ok:
			flagged += 1
		print("%-32s %9s   %-17s %s" % [row[0], row[4] % v, (row[4] + " - " + row[4]) % [row[2], row[3]], "OK" if ok else "CHECK"])
	print("")
	print("Home team wins %.1f%% (teams are not equal, so see 'mirror' for the pure home edge)" % (100.0 * home_wins / games))
	margins.sort()
	print("Margin of victory: median %d, 90th percentile %d, blowouts (25+) %.1f%%" % [
		margins[floori(margins.size() / 2.0)], margins[floori(margins.size() * 0.9)],
		100.0 * margins.filter(func(m): return m >= 25).size() / games])
	print("Team scores: lowest %d, highest %d; best individual scoring night: %d points" % [lowest, highest, top_scorer])

	var rows: Array = []
	for tid in played:
		var team: FcGameTeam = null
		for t in teams:
			if t.team_id == tid:
				team = t
		var rating := 0.0
		for p in team.players.slice(0, 8):
			rating += p.overall
		rows.append({"abbr": team.abbreviation, "rating": rating / 8.0, "win_pct": float(wins.get(tid, 0)) / played[tid], "games": played[tid]})
	rows.sort_custom(func(a, b): return a["rating"] > b["rating"])
	print("")
	print("Better teams should win more. Top-8 player rating vs win%:")
	var top_wins := 0.0
	var bottom_wins := 0.0
	for i in 5:
		top_wins += rows[i]["win_pct"]
		bottom_wins += rows[rows.size() - 1 - i]["win_pct"]
	print("  5 strongest teams win %.1f%% | 5 weakest teams win %.1f%%" % [top_wins * 20.0, bottom_wins * 20.0])
	print("  correlation of team rating and win%%: %.2f" % _correlation(rows.map(func(r): return r["rating"]), rows.map(func(r): return r["win_pct"])))
	print("")
	print("%d of %d checks outside the realistic range." % [flagged, TARGETS.size()])
	quit(0)


## Plays one team against an identical copy of itself, so the only differences
## are luck and home court.
func _mirror_test(sim: FcGameSimulator, rng: FcRng, home: FcGameTeam, away: FcGameTeam, games: int) -> void:
	var home_wins := 0
	var margin := 0.0
	var squares := 0.0
	var total_points := 0.0
	for g in games:
		var box := sim.simulate(home, away, rng)
		if box.scores[0] > box.scores[1]:
			home_wins += 1
		var m := float(box.scores[0] - box.scores[1])
		margin += m
		squares += m * m
		total_points += box.scores[0] + box.scores[1]
	var mean := margin / games
	print("=== Equal teams, %d games ===" % games)
	print("Home team wins %.1f%% (target 56-61%%), average home margin %+.1f points (target +2 to +4)" % [100.0 * home_wins / games, mean])
	print("Spread of the final margin (standard deviation): %.1f points (real basketball is about 12-14)" % sqrt(squares / games - mean * mean))
	print("Average points per team: %.1f" % (total_points / games / 2.0))


func _print_box(box: FcBoxScore) -> void:
	print("=== %s ===" % box.summary())
	var line := "By period: "
	for side in 2:
		var parts: Array = []
		for v in box.period_scores[side]:
			parts.append(str(v))
		line += "%s %s   " % [box.abbreviations[side], " ".join(parts)]
	print(line)
	for side in 2:
		print("")
		print(box.table(side))
		var t := box.team_totals(side)
		var a := box.advanced(side)
		print("Team: %d pts, FG %d-%d, 3P %d-%d, FT %d-%d, REB %d, AST %d, TO %d | pace %.1f, ORtg %.1f, eFG %.3f" % [
			t["points"], t["fgm"], t["fga"], t["tpm"], t["tpa"], t["ftm"], t["fta"], t["oreb"] + t["dreb"], t["ast"], t["tov"],
			a["pace"], a["offensive_rating"], a["efg"]])


func _correlation(xs: Array, ys: Array) -> float:
	var n := float(xs.size())
	var mean_x := 0.0
	var mean_y := 0.0
	for i in xs.size():
		mean_x += xs[i]
		mean_y += ys[i]
	mean_x /= n
	mean_y /= n
	var cov := 0.0
	var var_x := 0.0
	var var_y := 0.0
	for i in xs.size():
		cov += (xs[i] - mean_x) * (ys[i] - mean_y)
		var_x += pow(xs[i] - mean_x, 2.0)
		var_y += pow(ys[i] - mean_y, 2.0)
	return cov / sqrt(maxf(var_x * var_y, 0.000001))
