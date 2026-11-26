class_name FcFranchiseSnapshot
extends RefCounted
## Everything the franchise headquarters shows, read from the live game (D-077 M3): the record and standing, form, playoff position "if the
## season ended today" (the real playoff builder run on today's standings), team statistic ranks, team leaders, the last game's player of
## the game, the objectives with their progress, and the books. Read-only: it changes nothing, and every number comes from the simulation's
## own records (nothing is estimated or invented; a value that does not exist yet is left out).


## The snapshot of the controller's user team. Keys (some absent when there is nothing to show):
##   record {wins, losses, rank, games_left, streak}, conference {name, rank, size}, form [bool, ... newest last, up to 10], last_ten [w, l],
##   playoff {qualifies, seed, games_back (to the last place in, or from the first place out), places}, ranks {offense, defense, net}:
##   {rank, value, of}, leaders [{stat, label, player, value}], last_game {game_id, won, score, opponent, pog, pog_line}, objectives
##   [{text, status, progress}], money {payroll, cap, tax_line, cash, debt, last_profit, has_books}, staff {coach, gm, chemistry}.
static func build(c: FcGameController) -> Dictionary:
	var out := {}
	var w := c.state.world
	var user := c.state.user_team_id
	var season := c.season()
	var league: FcLeague = w.leagues.get_by_id(c.league_id)
	var standings := c.standings()
	out["record"] = c.user_record()
	var conf: FcConference = league.conference_of_team(user)
	if conf != null:
		var order := standings.conference_ranking(conf)
		out["conference"] = {"name": conf.name, "rank": order.find(user) + 1, "size": order.size()}
	var results: Array = standings.records[user]["results"]
	out["form"] = results.slice(maxi(0, results.size() - 10))
	out["last_ten"] = standings.last_ten(user)
	out["playoff"] = _playoff(c, league, standings, user)
	out["ranks"] = _ranks(league, standings, user)
	out["leaders"] = _leaders(c, season, user)
	var last := _last_game(c, season, user)
	if not last.is_empty():
		out["last_game"] = last
	var objectives: Array = []
	var now := {"wins": int(standings.records[user]["w"]), "games_left": int(out["record"]["games_left"]),
		"in_playoff_place": bool(out["playoff"].get("qualifies", false)), "young_minutes": _young_minutes(c, season, user)}
	for o in c.objectives():
		objectives.append({"text": o["text"], "status": o["status"], "progress": FcOwnerObjectives.progress_text(o, now) if o["status"] == FcOwnerObjectives.STATUS_OPEN else ""})
	out["objectives"] = objectives
	var rules := w.rules_of_league(c.league_id)
	var b := c.business()
	var rec := FcFinanceEngine.new(w).record_of(user, c.state.current_season - 1)
	out["money"] = {"payroll": w.payroll_of_team(user, c.contract_year()), "cap": rules.cap.salary_cap, "tax_line": rules.cap.luxury_tax_line,
		"cash": b.cash if b != null else 0, "debt": b.debt if b != null else 0, "has_books": rec != null, "last_profit": rec.profit() if rec != null else 0}
	var coach := w.staff_in_role(user, FcStaffRole.Id.HEAD_COACH)
	var gm := w.staff_in_role(user, FcStaffRole.Id.GENERAL_MANAGER)
	out["staff"] = {"coach": coach.identity.full_name() if coach != null else "", "gm": gm.identity.full_name() if gm != null else "",
		"chemistry": int(c.staff_chemistry()["score"]) if c.state.mode == FcGameState.MODE_OWNER else -1}
	return out


## Where the team would stand if the playoffs started today, from the league's own playoff builder and rules.
static func _playoff(c: FcGameController, league: FcLeague, standings: FcStandings, user: int) -> Dictionary:
	var rules := c.state.world.rules_of_league(c.league_id)
	if rules == null or standings.games_played(user) == 0:
		return {"qualifies": false, "games_back": 0.0, "places": 0}
	var po := FcPlayoffBuilder.build(league, standings, rules.playoffs)
	var mine: Dictionary = {}
	for q in po.qualifiers:
		if int(q["team"]) == user:
			mine = q
	# compare with the last team in (when inside) or the first team out (when outside), in the user's bracket
	var group: Array[int] = []
	var conf := league.conference_of_team(user)
	if rules.playoffs.bracket == "conference" and conf != null:
		group = standings.conference_ranking(conf)
	else:
		group = standings.league_ranking()
	var in_group: Array[int] = []
	for q in po.qualifiers:
		if group.has(int(q["team"])):
			in_group.append(int(q["team"]))
	var places := in_group.size()
	if not mine.is_empty():
		var first_out := -1
		for t in group:
			if not in_group.has(t):
				first_out = t
				break
		var cushion := standings.games_behind(user, first_out) if first_out != -1 else 0.0
		return {"qualifies": true, "seed": int(mine["seed"]), "games_back": cushion, "places": places}
	var last_in := -1
	for t in group:
		if in_group.has(t):
			last_in = t
	return {"qualifies": false, "games_back": standings.games_behind(last_in, user) if last_in != -1 else 0.0, "places": places}


## The team's league rank in points scored, points allowed (fewest is best) and margin, per game.
static func _ranks(league: FcLeague, standings: FcStandings, user: int) -> Dictionary:
	var teams := league.all_team_ids()
	var per := func(t: int, key: String) -> float:
		var gp := maxi(1, standings.games_played(t))
		return float(standings.records[t][key]) / gp
	var out := {}
	for spec in [["offense", "pf", true], ["defense", "pa", false]]:
		var ordered := teams.duplicate()
		ordered.sort_custom(func(a: int, b: int) -> bool: return per.call(a, spec[1]) > per.call(b, spec[1]) if spec[2] else per.call(a, spec[1]) < per.call(b, spec[1]))
		out[spec[0]] = {"rank": ordered.find(user) + 1, "value": per.call(user, spec[1]), "of": teams.size()}
	var by_net := teams.duplicate()
	by_net.sort_custom(func(a: int, b: int) -> bool: return standings.point_differential(a) / float(maxi(1, standings.games_played(a))) > standings.point_differential(b) / float(maxi(1, standings.games_played(b))))
	out["net"] = {"rank": by_net.find(user) + 1, "value": standings.point_differential(user) / float(maxi(1, standings.games_played(user))), "of": teams.size()}
	return out


## The team's leader in points, rebounds and assists per game this season (players still on the roster).
static func _leaders(c: FcGameController, season: FcSeason, user: int) -> Array:
	var out: Array = []
	var roster: Array = c.state.world.teams.get_by_id(user).roster.player_ids
	for spec in [["points", "Points"], ["rebounds", "Rebounds"], ["ast", "Assists"]]:
		var best := 0
		var best_value := -1.0
		for pid in roster:
			if season.stats.games_played(pid) <= 0:
				continue
			var v := season.stats.per_game(pid, spec[0])
			if v > best_value or (v == best_value and pid < best):
				best_value = v
				best = pid
		if best > 0:
			out.append({"stat": spec[0], "label": spec[1], "player": best, "value": best_value})
	return out


## The user team's most recent played game with its player of the game (from the game's stored result line).
static func _last_game(c: FcGameController, season: FcSeason, user: int) -> Dictionary:
	var last: FcScheduledGame = null
	for g in season.games:
		if g.played and g.involves(user) and (last == null or g.day >= last.day):
			last = g
	if last == null:
		return {}
	var won := last.winner_id() == user
	var mine := last.home_score if last.home_id == user else last.away_score
	var theirs := last.away_score if last.home_id == user else last.home_score
	var out := {"game_id": last.id, "won": won, "score": "%d-%d" % [mine, theirs], "opponent": last.away_id if last.home_id == user else last.home_id, "home": last.home_id == user}
	var pog := int(last.line.get("pog", 0))
	if pog > 0:
		out["pog"] = pog
		for row in last.line.get("top", []):
			if int(row[0]) == pog:
				out["pog_line"] = "%d pts, %d reb, %d ast" % [int(row[1]), int(row[2]), int(row[3])]
	return out


## The most minutes a game of a player aged 23 or younger on the team (the development objective's progress).
static func _young_minutes(c: FcGameController, season: FcSeason, user: int) -> float:
	var best := 0.0
	for pid in c.state.world.teams.get_by_id(user).roster.player_ids:
		var p: FcPlayer = c.state.world.players.get_by_id(pid)
		if p != null and p.age_on(FcDate.new(season.year, 7, 1)) <= 23 and season.stats.games_played(pid) > 0:
			best = maxf(best, season.stats.per_game(pid, "minutes"))
	return best
