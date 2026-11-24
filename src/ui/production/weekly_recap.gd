class_name FcWeeklyRecap
extends RefCounted
## "Full Court Tonight" (Broadcast pass 2, M7, D-071): the weekly show about the whole league, built from the SAVED league data, never invented.
## It reads the season's compact results (every played game: day, teams, scores, overtimes), standings computed from them (FcStandings, before and
## after the week), the schedule of the days ahead, and the box scores the game kept (the games of the watched team: the season keeps full box
## scores only for those, so the player segments are built from them and SAY SO). Pure and deterministic; the template
## (data/broadcast/templates/full_court_tonight.json) picks and orders the segments, FcProductionPanel draws them.
##
## `input`: {games: Array[FcScheduledGame] (the season's, played or not), league: FcLeague, names {team id: name}, abbrs {team id: abbreviation},
##   week_start: int, week_end: int (day numbers, inclusive), box_entries: Array of {day: int, box: FcBoxScore} (the kept boxes), cutoff: int (teams per
##   conference in playoff position, 0 = unknown), date_text: Callable (day -> String, optional)}.
## Segments have the same shape as FcProductionPlan's. Only regular-season games count here (the standings and streaks are regular-season facts).

const WEEK_DAYS := 7
const MIN_GAMES_FOR_UPSET := 4
const UPSET_GAP := 0.2
const STREAK_MIN := 3
const LIST_MAX := 5
const BEST_COUNT := 3
const NO_BOXES_NOTE := "The game keeps full box scores only for the team you follow, so player segments use those games."
const PLAYER_NOTE := "Rated by points + rebounds + assists + steals + blocks."


static func build(input: Dictionary) -> Dictionary:
	var template := FcProductionTemplate.load_template("full_court_tonight")
	if not FcProductionTemplate.problems(template).is_empty():
		return {}
	var facts := _facts(input)
	var segments: Array[Dictionary] = []
	var total := 0.0
	for spec in FcProductionTemplate.segments(template):
		segments.append(_segment(str(spec["type"]), float(spec["seconds"]), input, facts))
		total += float(spec["seconds"])
	return {"template_id": "full_court_tonight", "title": str(template["title"]), "week_start": int(input["week_start"]), "week_end": int(input["week_end"]), "segments": segments, "total_seconds": total}


## The shared numbers every segment reads (computed once).
static func _facts(input: Dictionary) -> Dictionary:
	var games: Array = input["games"]
	var league: FcLeague = input["league"]
	var start := int(input["week_start"])
	var end := int(input["week_end"])
	var before_games: Array[FcScheduledGame] = []
	var after_games: Array[FcScheduledGame] = []
	var week: Array[FcScheduledGame] = []
	var upcoming: Array[FcScheduledGame] = []
	for g in games:
		var game := g as FcScheduledGame
		if game.series != 0:
			continue
		if game.played and game.day < start:
			before_games.append(game)
		if game.played and game.day <= end:
			after_games.append(game)
		if game.played and game.day >= start and game.day <= end:
			week.append(game)
		if not game.played and game.day > end and game.day <= end + WEEK_DAYS:
			upcoming.append(game)
	return {"before": FcStandings.compute(league, before_games), "after": FcStandings.compute(league, after_games), "week": week, "upcoming": upcoming}


static func _name(input: Dictionary, id: int) -> String:
	return str((input["names"] as Dictionary).get(id, "Team %d" % id))


static func _abbr(input: Dictionary, id: int) -> String:
	return str((input["abbrs"] as Dictionary).get(id, "T%d" % id))


static func _date(input: Dictionary, day: int) -> String:
	var f: Callable = input.get("date_text", Callable())
	return str(f.call(day)) if f.is_valid() else "Day %d" % (day + 1)


static func _seg(type: String, title: String, seconds: float, rows: Array, lines: Array, facts: Dictionary, source: String, available: bool = true, note: String = "") -> Dictionary:
	return {"type": type, "title": title, "seconds": seconds, "rows": rows, "lines": lines, "facts": facts, "source": source, "available": available, "note": note}


static func _segment(type: String, seconds: float, input: Dictionary, f: Dictionary) -> Dictionary:
	match type:
		"headlines":
			return _headlines(seconds, input, f)
		"game_of_the_week":
			return _game_of_the_week(seconds, input, f)
		"player_of_the_week", "best_performances":
			return _player_segments(type, seconds, input, f)
		"upsets":
			return _upsets(seconds, input, f)
		"streaks":
			return _streaks(seconds, input, f)
		"standings_race":
			return _standings(seconds, input, f)
		"marquee_matchups":
			return _marquee(seconds, input, f)
	return _seg(type, type, seconds, [], [], {}, FcPresentationEvent.DERIVED_FROM_RECORDED, false, "Unknown segment.")


# --- game of the week -----------------------------------------------------------------------------------------------------------------

## How exciting a finished game was, from its result only: a close finish, overtimes. Higher is better; ties go to the earlier day, then the lower home id.
static func excitement(g: FcScheduledGame) -> int:
	var margin := absi(g.home_score - g.away_score)
	var score := 50
	if margin <= 3:
		score += 30
	elif margin <= 6:
		score += 15
	score += 20 * g.overtimes
	score -= margin
	return score


static func best_game(week: Array) -> FcScheduledGame:
	var best: FcScheduledGame = null
	for g in week:
		var game := g as FcScheduledGame
		if best == null:
			best = game
			continue
		var a := excitement(game)
		var b := excitement(best)
		if a > b or (a == b and (game.day < best.day or (game.day == best.day and game.home_id < best.home_id))):
			best = game
	return best


static func _game_of_the_week(seconds: float, input: Dictionary, f: Dictionary) -> Dictionary:
	var g := best_game(f["week"])
	if g == null:
		return _seg("game_of_the_week", "Game of the week", seconds, [], [], {}, FcPresentationEvent.DERIVED_FROM_RECORDED, false, "No games were played this week.")
	var winner := g.winner_id()
	var loser := g.loser_id()
	var hi := maxi(g.home_score, g.away_score)
	var lo := mini(g.home_score, g.away_score)
	var ot := "" if g.overtimes == 0 else (" in overtime" if g.overtimes == 1 else " in %d overtimes" % g.overtimes)
	return _seg("game_of_the_week", "Game of the week", seconds, [],
		["%s beat %s %d-%d%s" % [_name(input, winner), _name(input, loser), hi, lo, ot], "%s, at %s" % [_date(input, g.day), _name(input, g.home_id)],
		"Picked for the closest finish and any overtime."],
		{"day": g.day, "home_id": g.home_id, "away_id": g.away_id, "home_score": g.home_score, "away_score": g.away_score, "overtimes": g.overtimes, "excitement": excitement(g)},
		FcPresentationEvent.DERIVED_FROM_RECORDED)


# --- players (from the kept box scores) ---------------------------------------------------------------------------------------------------

static func line_value(p: FcPlayerGameStats) -> int:
	return p.points + p.oreb + p.dreb + p.ast + p.stl + p.blk


static func _week_lines(input: Dictionary) -> Array:
	var out: Array = []
	var start := int(input["week_start"])
	var end := int(input["week_end"])
	for entry in input.get("box_entries", []):
		var day := int(entry["day"])
		if day < start or day > end or int(entry.get("series", 0)) != 0:
			continue
		var box: FcBoxScore = entry["box"]
		for p in box.players:
			var side := 0 if p.team_id == box.team_ids[0] else 1
			out.append({"day": day, "player": p, "side": side, "box": box, "value": line_value(p)})
	return out


static func _player_segments(type: String, seconds: float, input: Dictionary, f: Dictionary) -> Dictionary:
	var lines := _week_lines(input)
	var title := "Player of the week" if type == "player_of_the_week" else "Best performances"
	if lines.is_empty():
		return _seg(type, title, seconds, [], [], {}, FcPresentationEvent.SIM_RECORDED, false, NO_BOXES_NOTE)
	if type == "player_of_the_week":
		var totals := {}
		var info := {}
		for l in lines:
			var p: FcPlayerGameStats = l["player"]
			totals[p.player_id] = int(totals.get(p.player_id, 0)) + int(l["value"])
			if not info.has(p.player_id):
				info[p.player_id] = {"name": FcPlayByPlay.short_name(p.name), "team": int(p.team_id), "points": 0, "rebounds": 0, "assists": 0, "games": 0}
			var d: Dictionary = info[p.player_id]
			d["points"] = int(d["points"]) + p.points
			d["rebounds"] = int(d["rebounds"]) + p.oreb + p.dreb
			d["assists"] = int(d["assists"]) + p.ast
			d["games"] = int(d["games"]) + 1
		var best_id := -1
		for pid in totals:
			if best_id < 0 or int(totals[pid]) > int(totals[best_id]) or (int(totals[pid]) == int(totals[best_id]) and int(pid) < best_id):
				best_id = int(pid)
		var d2: Dictionary = info[best_id]
		var line := "%d PTS, %d REB, %d AST in %d game%s" % [int(d2["points"]), int(d2["rebounds"]), int(d2["assists"]), int(d2["games"]), "" if int(d2["games"]) == 1 else "s"]
		return _seg(type, title, seconds, [[str(d2["name"]), _abbr(input, int(d2["team"])), line]], [PLAYER_NOTE, NO_BOXES_NOTE],
			{"player_id": best_id, "total": int(totals[best_id]), "points": int(d2["points"]), "rebounds": int(d2["rebounds"]), "assists": int(d2["assists"]), "games": int(d2["games"])},
			FcPresentationEvent.DERIVED_FROM_RECORDED)
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["value"]) != int(b["value"]):
			return int(a["value"]) > int(b["value"])
		if int(a["day"]) != int(b["day"]):
			return int(a["day"]) < int(b["day"])
		return (a["player"] as FcPlayerGameStats).player_id < (b["player"] as FcPlayerGameStats).player_id)
	var rows: Array = []
	var facts: Array = []
	for l in lines.slice(0, BEST_COUNT):
		var p: FcPlayerGameStats = l["player"]
		var box: FcBoxScore = l["box"]
		var other := box.team_ids[1 - int(l["side"])]
		rows.append([FcPlayByPlay.short_name(p.name), _abbr(input, int(p.team_id)), "%d PTS, %d REB, %d AST" % [p.points, p.oreb + p.dreb, p.ast], "vs %s" % _abbr(input, int(other)), _date(input, int(l["day"]))])
		facts.append({"player_id": p.player_id, "points": p.points, "rebounds": p.oreb + p.dreb, "assists": p.ast, "day": int(l["day"]), "value": int(l["value"])})
	return _seg(type, title, seconds, rows, [PLAYER_NOTE, NO_BOXES_NOTE], {"lines": facts}, FcPresentationEvent.DERIVED_FROM_RECORDED)


# --- upsets, streaks, standings, marquee ----------------------------------------------------------------------------------------------------

static func upsets_of(input: Dictionary, f: Dictionary) -> Array[Dictionary]:
	var before: FcStandings = f["before"]
	var out: Array[Dictionary] = []
	for g in f["week"]:
		var game := g as FcScheduledGame
		var w := game.winner_id()
		var l := game.loser_id()
		if not before.records.has(w) or not before.records.has(l):
			continue
		if before.games_played(w) < MIN_GAMES_FOR_UPSET or before.games_played(l) < MIN_GAMES_FOR_UPSET:
			continue
		var gap := before.win_pct(l) - before.win_pct(w)
		if gap >= UPSET_GAP:
			out.append({"game": game, "gap": gap, "winner": w, "loser": l})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["gap"]), float(b["gap"])):
			return float(a["gap"]) > float(b["gap"])
		return (a["game"] as FcScheduledGame).day < (b["game"] as FcScheduledGame).day)
	return out


static func _upsets(seconds: float, input: Dictionary, f: Dictionary) -> Dictionary:
	var list := upsets_of(input, f)
	if list.is_empty():
		return _seg("upsets", "Upsets", seconds, [], ["No upsets this week."], {"upsets": []}, FcPresentationEvent.DERIVED_FROM_RECORDED)
	var before: FcStandings = f["before"]
	var rows: Array = []
	var facts: Array = []
	for u in list.slice(0, LIST_MAX):
		var g: FcScheduledGame = u["game"]
		var w := int(u["winner"])
		var l := int(u["loser"])
		rows.append([_name(input, w), "beat", _name(input, l), "%d-%d" % [maxi(g.home_score, g.away_score), mini(g.home_score, g.away_score)], "was %d-%d vs %d-%d" % [before.records[w]["w"], before.records[w]["l"], before.records[l]["w"], before.records[l]["l"]]])
		facts.append({"winner": w, "loser": l, "gap": float(u["gap"]), "day": g.day})
	return _seg("upsets", "Upsets", seconds, rows, ["An upset: a team with a record at least .200 worse beat the better one (at least %d games each before)." % MIN_GAMES_FOR_UPSET], {"upsets": facts}, FcPresentationEvent.DERIVED_FROM_RECORDED)


static func streak_rows(input: Dictionary, f: Dictionary) -> Array[Dictionary]:
	var after: FcStandings = f["after"]
	var out: Array[Dictionary] = []
	for id in after.records:
		var s := int(after.records[id]["streak"])
		if absi(s) >= STREAK_MIN:
			out.append({"team": int(id), "streak": s})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if absi(int(a["streak"])) != absi(int(b["streak"])):
			return absi(int(a["streak"])) > absi(int(b["streak"]))
		return int(a["team"]) < int(b["team"]))
	return out


static func _streaks(seconds: float, input: Dictionary, f: Dictionary) -> Dictionary:
	var list := streak_rows(input, f)
	var after: FcStandings = f["after"]
	if list.is_empty():
		return _seg("streaks", "Streaks", seconds, [], ["No team is on a streak of %d or more." % STREAK_MIN], {"streaks": []}, FcPresentationEvent.DERIVED_FROM_RECORDED)
	var rows: Array = []
	for s in list.slice(0, LIST_MAX * 2):
		var id := int(s["team"])
		rows.append([_name(input, id), after.streak_text(id), "%d-%d" % [after.records[id]["w"], after.records[id]["l"]]])
	return _seg("streaks", "Streaks", seconds, rows, [], {"streaks": list}, FcPresentationEvent.DERIVED_FROM_RECORDED)


static func _standings(seconds: float, input: Dictionary, f: Dictionary) -> Dictionary:
	var league: FcLeague = input["league"]
	var after: FcStandings = f["after"]
	var cutoff := int(input.get("cutoff", 0))
	var rows: Array = []
	var facts: Array = []
	for conference in league.conferences:
		rows.append(["%s Conference" % conference.name, "W-L", "GB", ""])
		var order := after.conference_ranking(conference)
		for i in order.size():
			var id := order[i]
			var r: Dictionary = after.records[id]
			var mark := ""
			if cutoff > 0:
				if i == cutoff - 1:
					mark = "last in"
				elif i == cutoff:
					mark = "first out"
				elif i < cutoff:
					mark = "in"
				else:
					mark = "out"
			rows.append(["%d. %s" % [i + 1, _name(input, id)], "%d-%d" % [r["w"], r["l"]], "%.1f" % after.games_behind(order[0], id), mark])
			facts.append({"team": id, "rank": i + 1, "w": int(r["w"]), "l": int(r["l"])})
	var note := "In playoff position: the top %d of each conference." % cutoff if cutoff > 0 else "Standings after the week's games."
	return _seg("standings_race", "Standings and the playoff race", seconds, rows, [note], {"standings": facts, "cutoff": cutoff}, FcPresentationEvent.DERIVED_FROM_RECORDED)


static func marquee_games(input: Dictionary, f: Dictionary) -> Array[Dictionary]:
	var after: FcStandings = f["after"]
	var out: Array[Dictionary] = []
	for g in f["upcoming"]:
		var game := g as FcScheduledGame
		if not after.records.has(game.home_id) or not after.records.has(game.away_id):
			continue
		var combined := after.win_pct(game.home_id) + after.win_pct(game.away_id)
		out.append({"game": game, "combined": combined})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["combined"]), float(b["combined"])):
			return float(a["combined"]) > float(b["combined"])
		var ga: FcScheduledGame = a["game"]
		var gb: FcScheduledGame = b["game"]
		return ga.day < gb.day if ga.day != gb.day else ga.home_id < gb.home_id)
	return out


static func _marquee(seconds: float, input: Dictionary, f: Dictionary) -> Dictionary:
	var list := marquee_games(input, f)
	if list.is_empty():
		return _seg("marquee_matchups", "Marquee matchups", seconds, [], [], {}, FcPresentationEvent.DERIVED_FROM_RECORDED, false, "No games are scheduled in the next %d days." % WEEK_DAYS)
	var after: FcStandings = f["after"]
	var rows: Array = []
	var facts: Array = []
	for m in list.slice(0, LIST_MAX):
		var g: FcScheduledGame = m["game"]
		rows.append([_date(input, g.day), "%s at %s" % [_name(input, g.away_id), _name(input, g.home_id)], "%d-%d and %d-%d" % [after.records[g.away_id]["w"], after.records[g.away_id]["l"], after.records[g.home_id]["w"], after.records[g.home_id]["l"]]])
		facts.append({"day": g.day, "home_id": g.home_id, "away_id": g.away_id, "combined": float(m["combined"])})
	return _seg("marquee_matchups", "Marquee matchups", seconds, rows, ["The games ahead between the best records."], {"games": facts}, FcPresentationEvent.DERIVED_FROM_RECORDED)


# --- headlines -------------------------------------------------------------------------------------------------------------------------------

static func _headlines(seconds: float, input: Dictionary, f: Dictionary) -> Dictionary:
	var lines: Array = []
	var facts: Array = []
	var g := best_game(f["week"])
	if g != null:
		lines.append("%s %d, %s %d: the game of the week" % [_name(input, g.winner_id()), maxi(g.home_score, g.away_score), _name(input, g.loser_id()), mini(g.home_score, g.away_score)])
		facts.append("game_of_the_week")
	var ups := upsets_of(input, f)
	if not ups.is_empty():
		lines.append("Upset: %s beat %s" % [_name(input, int(ups[0]["winner"])), _name(input, int(ups[0]["loser"]))])
		facts.append("upset")
	var streaks := streak_rows(input, f)
	if not streaks.is_empty():
		var s: Dictionary = streaks[0]
		lines.append("%s %s: %d straight %s" % [_name(input, int(s["team"])), "win" if int(s["streak"]) > 0 else "lose", absi(int(s["streak"])), "wins" if int(s["streak"]) > 0 else "losses"])
		facts.append("streak")
	var after: FcStandings = f["after"]
	var league: FcLeague = input["league"]
	var top := after.league_ranking()
	if not top.is_empty() and after.games_played(top[0]) > 0:
		lines.append("%s lead the league at %d-%d" % [_name(input, top[0]), after.records[top[0]]["w"], after.records[top[0]]["l"]])
		facts.append("leader")
	if lines.is_empty():
		lines.append("A quiet week: no games were played.")
	return _seg("headlines", "This week's headlines", seconds, [], lines, {"kinds": facts, "games": (f["week"] as Array).size(), "teams": league.team_count()}, FcPresentationEvent.DERIVED_FROM_RECORDED)
