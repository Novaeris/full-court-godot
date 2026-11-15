extends SceneTree
## Plays one complete season of a generated league and prints the story:
## standings, playoff results, champion, awards and league leaders.
##
## Run (PowerShell, from the project folder):
##   ./tools/play_season.ps1                     the default 30-team league (about 15 seconds)
##   ./tools/play_season.ps1 seed=7 teams=16 conferences=2 divisions=2
##   ./tools/play_season.ps1 playoffs=8 bracket=league qualification=seeding series=3,5,7
##   ./tools/play_season.ps1 era=late_2010s
## Options: seed, teams, conferences, divisions, era, playoffs, bracket,
## qualification, series, areas (comma list, or "all"), games (target length).


func _initialize() -> void:
	var gen := FcWorldGenerator.create_default()
	var cfg := gen.config
	var seed_value := 2026
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"seed": seed_value = int(kv[1])
			"teams": cfg.team_count = int(kv[1])
			"conferences": cfg.conference_count = int(kv[1])
			"divisions": cfg.divisions_per_conference = int(kv[1])
			"era": cfg.sim_era = kv[1]
			"games": cfg.target_games = int(kv[1])
			"areas": cfg.areas = [] as Array[String] if kv[1] == "all" else _list(kv[1])
			"playoffs": cfg.auto_playoffs = false; cfg.playoff_team_count = int(kv[1])
			"bracket": cfg.auto_playoffs = false; cfg.playoff_bracket = kv[1]
			"qualification": cfg.auto_playoffs = false; cfg.playoff_qualification = kv[1]
			"series":
				cfg.auto_playoffs = false
				cfg.playoff_series = []
				for s in _list(kv[1]):
					cfg.playoff_series.append(int(s))
	var problems := gen.validate()
	if not problems.is_empty():
		print("Cannot build this league: " + "; ".join(problems))
		quit(1)
		return

	var world := gen.generate(seed_value)
	var league: FcLeague = world.leagues.get_by_id(1)
	var rules := world.rules_of_league(1)
	var engine := FcSeasonEngine.for_league(world, 1)
	var rng := FcRng.new(seed_value).fork("season")
	var season := engine.start_season(1, cfg.start_season, FcDate.new(cfg.start_season, 10, 20), rng)
	var t0 := Time.get_ticks_msec()
	engine.play_regular_season(season, rng)
	var standings := engine.standings_of(season)
	print("=== %s %d-%d season: %d games each, %d days (%s to %s), era %s ===" % [
		league.name, season.year, (season.year + 1) % 100, rules.season.games_per_team(league), season.total_days(),
		season.start_date.to_iso(), season.date_of_day(season.total_days() - 1).to_iso(), rules.sim_era])

	for conference in league.conferences:
		print("")
		print("%s Conference" % conference.name)
		print("  %-30s %3s %3s  %5s %5s %5s %6s %5s %s" % ["Team", "W", "L", "Pct", "GB", "Home", "Away", "L10", "Strk"])
		var order := standings.conference_ranking(conference)
		var leader: int = order[0]
		for t in order:
			var r: Dictionary = standings.records[t]
			var l10 := standings.last_ten(t)
			print("  %-30s %3d %3d  %.3f %5.1f %2d-%-2d %2d-%-2d %d-%d %s" % [
				_name(world, t), r["w"], r["l"], standings.win_pct(t), standings.games_behind(leader, t),
				r["home_w"], r["home_l"], r["away_w"], r["away_l"], l10[0], l10[1], standings.streak_text(t)])

	engine.play_playoffs(season, rng)
	var seconds := (Time.get_ticks_msec() - t0) / 1000.0
	print("")
	print("=== Playoffs ===")
	for line in rules.playoffs.describe(league):
		print("  " + line)
	var po := season.playoffs
	for round_number in range(1, po.rounds + 1):
		print("Round %d" % round_number)
		for s in po.series_in_round(round_number):
			if s.is_bye:
				print("  (%d) %s: bye" % [s.seed_a if s.team_a > 0 else s.seed_b, _name(world, s.winner_id)])
			elif s.winner_id > 0:
				var loser := s.team_b if s.winner_id == s.team_a else s.team_a
				var w_wins := s.wins_a if s.winner_id == s.team_a else s.wins_b
				var l_wins := s.wins_b if s.winner_id == s.team_a else s.wins_a
				print("  %s def. %s  %d-%d" % [_name(world, s.winner_id), _name(world, loser), w_wins, l_wins])
	print("")
	print("CHAMPION: %s   (runner-up: %s)" % [_name(world, season.champion_id), _name(world, season.runner_up_id)])

	print("")
	print("=== Awards ===")
	var aw := season.awards
	print("MVP: %s | Finals MVP: %s" % [_player(world, aw.get("mvp", 0), season.stats), _player(world, aw.get("finals_mvp", 0), season.playoff_stats)])
	print("Scoring champion: %s (%.1f ppg) | Rebounds: %s (%.1f) | Assists: %s (%.1f)" % [
		_player(world, aw["scoring_champion"], season.stats), season.stats.per_game(aw["scoring_champion"], "points"),
		_player(world, aw["rebounding_champion"], season.stats), season.stats.per_game(aw["rebounding_champion"], "rebounds"),
		_player(world, aw["assists_leader"], season.stats), season.stats.per_game(aw["assists_leader"], "ast")])
	for key in ["all_league_first", "all_league_second", "all_league_third"]:
		var names: Array = []
		for pid in aw.get(key, []):
			names.append(_player(world, pid, season.stats))
		print("%s: %s" % [key.replace("_", " ").capitalize(), ", ".join(names)])
	print("")
	print("Season played in %.1f s." % seconds)
	quit(0)


func _name(world: FcWorld, team_id: int) -> String:
	var t: FcTeam = world.teams.get_by_id(team_id)
	return t.identity.display_name(world.cities.get_by_id(t.city_id).name) if t != null else "-"


func _player(world: FcWorld, player_id: int, stats: FcSeasonStats) -> String:
	var l: Dictionary = stats.lines.get(player_id, {})
	if l.is_empty():
		return "-"
	var t: FcTeam = world.teams.get_by_id(l["team"])
	return "%s (%s)" % [l["name"], t.identity.abbreviation if t != null else "?"]


func _list(text: String) -> Array[String]:
	var out: Array[String] = []
	for part in text.split(","):
		if not part.strip_edges().is_empty():
			out.append(part.strip_edges())
	return out
