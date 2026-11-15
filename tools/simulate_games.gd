extends SceneTree
## Simulates many games and checks the results look like real basketball.
##
## Run (PowerShell, from the project folder):
##   ./tools/simulate_games.ps1                  1000 games, seed 2026
##   ./tools/simulate_games.ps1 games=5000 seed=7
##   ./tools/simulate_games.ps1 tune=three_base:0.25,rim_base:0.38   try tuning values without editing the file
##   ./tools/simulate_games.ps1 era=late_2010s    early_2010s | mid_2010s (default) | late_2010s
##   ./tools/simulate_games.ps1 box              print one full box score
##   ./tools/simulate_games.ps1 mirror           equal teams: measures home-court advantage
## It builds the default league, plays random matchups, and prints league
## averages next to realistic target ranges (OK / CHECK), the spread of
## scores, how well better teams win, and sample extremes.

## label, key, display format
const ROWS := [
	["Points per team", "points", "%.1f"],
	["Pace (possessions / 48 min)", "pace", "%.1f"],
	["Field goal %", "fg_pct", "%.3f"],
	["Three-point %", "tp_pct", "%.3f"],
	["Three-point attempts / FGA", "tp_rate", "%.3f"],
	["Free throw %", "ft_pct", "%.3f"],
	["Free throw attempts", "fta", "%.1f"],
	["Rebounds", "reb", "%.1f"],
	["Offensive rebound %", "oreb_pct", "%.3f"],
	["Assists", "ast", "%.1f"],
	["Turnovers", "tov", "%.1f"],
	["Steals", "stl", "%.1f"],
	["Blocks", "blk", "%.1f"],
	["Personal fouls", "pf", "%.1f"],
	["Effective FG %", "efg", "%.3f"],
	["Overtime games %", "ot_pct", "%.3f"],
]


func _initialize() -> void:
	var games := 1000
	var seed_value := 2026
	var show_box := false
	var mirror := false
	var era := ""
	var tune := {}
	var leaders := false
	for arg in OS.get_cmdline_user_args():
		if arg == "leaders":
			leaders = true
			continue
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
		elif parts.size() == 2 and parts[0] == "era":
			era = parts[1]
		elif parts.size() == 2 and parts[0] == "tune":
			for item in parts[1].split(","):
				var kv := item.split(":")
				if kv.size() == 2:
					tune[kv[0]] = float(kv[1])

	var gen := FcWorldGenerator.create_default()
	var world := gen.generate(seed_value)
	var ratings := FcPlayerRatings.load_default()
	var teams: Array[FcGameTeam] = []
	for tid in world.teams.ids():
		teams.append(FcGameTeam.from_world(world, tid, ratings))
	var sim := FcGameSimulator.new(tune, era)
	var rng := FcRng.new(seed_value).fork("games")
	var eras := FcGameSimulator.load_eras()
	var era_key := era if era != "" else str(eras.get("default", ""))
	var targets: Dictionary = eras.get("eras", {}).get(era_key, {}).get("targets", {})

	if show_box:
		var box := sim.simulate(teams[0], teams[1], rng)
		_print_box(box)
		quit(0)
		return
	if leaders:
		_season_leaders(sim, rng, world, teams)
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
	print("=== %d games simulated in %.1f s (%.1f ms per game), seed %d, era: %s ===" % [games, seconds, seconds * 1000.0 / games, seed_value, era_key])
	print("")
	print("%-32s %9s   %-17s %s" % ["League average (per team)", "Result", "Realistic range", ""])
	var flagged := 0
	for row in ROWS:
		var v: float = avg[row[1]]
		var range_pair: Array = targets.get(row[1], [-INF, INF])
		var ok: bool = v >= range_pair[0] and v <= range_pair[1]
		if not ok:
			flagged += 1
		print("%-32s %9s   %-17s %s" % [row[0], row[2] % v, (row[2] + " - " + row[2]) % [range_pair[0], range_pair[1]], "OK" if ok else "CHECK"])
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
	print("%d of %d checks outside the realistic range." % [flagged, ROWS.size()])
	quit(0)


## Plays one full season (every pair of teams as often as the schedule rules say, with
## the home/away split from the matchup planner) and prints the individual leaders,
## which is where star realism shows up: real scoring leaders average about 28-35 points.
func _season_leaders(sim: FcGameSimulator, rng: FcRng, world: FcWorld, teams: Array[FcGameTeam]) -> void:
	var league: FcLeague = world.leagues.get_by_id(1)
	var rules: FcLeagueRules = world.rules_of_league(1)
	var plan := FcMatchupPlanner.plan(league, rules.season)
	var by_id := {}
	for t in teams:
		by_id[t.team_id] = t
	var lines := {}   # player id -> {"name","team","gp","pts","reb","ast","stl","blk","min"}
	var wins := {}
	var best_night := {"pts": 0, "name": ""}
	var fifty_games := 0
	var games := 0
	var t0 := Time.get_ticks_msec()
	for pair in plan.pairs:
		for g in int(pair["games"]):
			var a_is_home: bool = g < int(pair["a_home"])
			var home: FcGameTeam = by_id[pair["a"] if a_is_home else pair["b"]]
			var away: FcGameTeam = by_id[pair["b"] if a_is_home else pair["a"]]
			var box := sim.simulate(home, away, rng)
			games += 1
			wins[box.winner_team_id()] = int(wins.get(box.winner_team_id(), 0)) + 1
			for p in box.players:
				if p.seconds <= 0:
					continue
				if not lines.has(p.player_id):
					lines[p.player_id] = {"name": p.name, "team": "", "gp": 0, "pts": 0, "reb": 0, "ast": 0, "stl": 0, "blk": 0, "min": 0.0}
				var l: Dictionary = lines[p.player_id]
				l["team"] = box.abbreviations[0] if p.team_id == box.team_ids[0] else box.abbreviations[1]
				l["gp"] += 1
				l["pts"] += p.points
				l["reb"] += p.rebounds()
				l["ast"] += p.ast
				l["stl"] += p.stl
				l["blk"] += p.blk
				l["min"] += p.minutes()
				if p.points >= 50:
					fifty_games += 1
				if p.points > best_night["pts"]:
					best_night = {"pts": p.points, "name": p.name}
	var seconds := (Time.get_ticks_msec() - t0) / 1000.0
	print("=== One full season: %d games in %.1f s ===" % [games, seconds])
	var regulars: Array = []
	for id in lines:
		if lines[id]["gp"] >= 50:
			regulars.append(lines[id])
	var show := func(title: String, key: String, count: int):
		regulars.sort_custom(func(a, b): return float(a[key]) / a["gp"] > float(b[key]) / b["gp"])
		var parts: Array = []
		for i in mini(count, regulars.size()):
			parts.append("%s %.1f" % [regulars[i]["name"], float(regulars[i][key]) / regulars[i]["gp"]])
		print("%s: %s" % [title, " | ".join(parts)])
	show.call("Points per game leaders", "pts", 6)
	show.call("Rebounds per game leaders", "reb", 4)
	show.call("Assists per game leaders", "ast", 4)
	show.call("Steals per game leaders", "stl", 3)
	show.call("Blocks per game leaders", "blk", 3)
	var over_20 := 0
	var over_25 := 0
	var minutes_leader := 0.0
	for l in regulars:
		var ppg: float = float(l["pts"]) / l["gp"]
		if ppg >= 20.0:
			over_20 += 1
		if ppg >= 25.0:
			over_25 += 1
		minutes_leader = maxf(minutes_leader, float(l["min"]) / l["gp"])
	print("")
	print("Players averaging 20+ points: %d (real 2010s: about 20-28 of ~450)   25+: %d (real: about 6-10)" % [over_20, over_25])
	print("Highest minutes per game: %.1f (real: about 36-38)" % minutes_leader)
	print("Best single game: %d points (%s); 50-point games this season: %d (real: about 8-25)" % [best_night["pts"], best_night["name"], fifty_games])
	var win_list: Array = wins.values()
	win_list.sort()
	print("Wins: best team %d, worst team %d of %d games (real: best ~65, worst ~17-20 of 82)" % [win_list[-1], win_list[0], int(rules.season.games_per_team(league))])


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
