extends SceneTree
## Plays several consecutive seasons (with the full offseason between them) and
## prints the league's history, then checks the league is still healthy.
##
## Run (PowerShell, from the project folder):
##   ./tools/play_seasons.ps1 seasons=5                       default 30-team league
##   ./tools/play_seasons.ps1 seasons=10 teams=16 conferences=2 divisions=2 seed=7
## Each season of a 30-team league takes about 15-20 seconds.


func _initialize() -> void:
	var gen := FcWorldGenerator.create_default()
	var cfg := gen.config
	var seasons := 5
	var seed_value := 2026
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"seasons": seasons = int(kv[1])
			"seed": seed_value = int(kv[1])
			"teams": cfg.team_count = int(kv[1])
			"conferences": cfg.conference_count = int(kv[1])
			"divisions": cfg.divisions_per_conference = int(kv[1])
			"era": cfg.sim_era = kv[1]
	var problems := gen.validate()
	if not problems.is_empty():
		print("Cannot build this league: " + "; ".join(problems))
		quit(1)
		return

	var world := gen.generate(seed_value)
	var ratings := FcPlayerRatings.load_default()
	var rng := FcRng.new(seed_value).fork("dynasty")
	var year := cfg.start_season
	var t0 := Time.get_ticks_msec()
	print("=== %d seasons of %s (%d teams), seed %d ===" % [seasons, world.leagues.get_by_id(1).name, world.teams.count(), seed_value])
	print("%-7s %-28s %-28s %-24s %-24s %s" % ["Season", "Champion", "Runner-up", "MVP", "Scoring leader", "Best record"])
	var titles := {}
	var health: Array = []
	for i in seasons:
		var engine := FcSeasonEngine.for_league(world, 1)
		var season := engine.start_season(1, year, FcDate.new(year, 10, 20), rng.fork("season%d" % i))
		engine.play_full_season(season, rng.fork("play%d" % i))
		titles[season.champion_id] = int(titles.get(season.champion_id, 0)) + 1
		var best: Array = season.final_standings[0]
		print("%-7s %-28s %-28s %-24s %-24s %s %d-%d" % [
			"%d-%02d" % [year, (year + 1) % 100], _team(world, season.champion_id), _team(world, season.runner_up_id),
			_player(world, season.awards.get("mvp", 0), season.stats), _player(world, season.awards.get("scoring_champion", 0), season.stats),
			_abbr(world, best[0]), best[1], best[2]])
		var report := FcOffseason.new(world).run(1, season, rng.fork("off%d" % i))
		year += 1
		var errors := world.validate(year)
		for message in errors.slice(0, 3):
			print("  integrity problem after the %d offseason: %s" % [year, message])
		health.append({"year": year, "errors": errors.size(), "report": report, "talent": _talent(world, ratings), "age": _age(world, year), "payroll": _payroll(world, year)})
	var seconds := (Time.get_ticks_msec() - t0) / 1000.0

	print("")
	print("=== League health after each offseason ===")
	print("%-6s %-10s %-9s %-8s %-8s %-8s %-8s %-9s %-9s %s" % ["Year", "Integrity", "Retired", "Drafted", "Re-sign", "Trades", "FA signs", "Top-8 rtg", "Avg age", "Avg payroll"])
	for h in health:
		print("%-6d %-10s %-9d %-8d %-8d %-8d %-8d %-9.1f %-9.1f $%.1fM" % [
			h["year"], "OK" if h["errors"] == 0 else "%d PROBLEMS" % h["errors"], h["report"]["retired"], h["report"]["drafted"],
			h["report"]["re_signed"], h["report"]["trades"], h["report"]["signed"], h["talent"], h["age"], h["payroll"] / 1e6])
	print("")
	var champs: Array = titles.keys()
	champs.sort_custom(func(a, b): return titles[a] > titles[b])
	var parts: Array = []
	for c in champs:
		parts.append("%s x%d" % [_abbr(world, c), titles[c]])
	print("Titles: " + ", ".join(parts))
	var retired := 0
	for p in world.players.all():
		if p.status == FcPlayer.Status.RETIRED:
			retired += 1
	print("Players in the database: %d (%d retired). Played in %.0f s." % [world.players.count(), retired, seconds])
	var records := FcRecords.new(world, 1)
	var hof := records.hall_of_fame(year + 1)
	print("Hall of Fame: %d members (best scores: %s)" % [hof.size(), ", ".join(hof.slice(0, 3).map(func(h): return "%s %.0f" % [world.player_name(h[1]), h[0]]))])
	var best := records.single_season_records("points", 1)
	if not best.is_empty():
		print("Best scoring season: %s, %d points in %d" % [world.player_name(best[0][1]), best[0][0], best[0][2]])
	var career_best := world.career_leaders("points", 1)
	if not career_best.is_empty():
		print("Top career scorer: %s, %d points (best Hall of Fame score so far among all players: %.0f)" % [world.player_name(career_best[0]), world.career_totals(career_best[0])["points"], records.score_of(career_best[0])])
	quit(0)


func _team(world: FcWorld, team_id: int) -> String:
	var t: FcTeam = world.teams.get_by_id(team_id)
	return t.identity.display_name(world.cities.get_by_id(t.city_id).name) if t != null else "-"


func _abbr(world: FcWorld, team_id: int) -> String:
	var t: FcTeam = world.teams.get_by_id(team_id)
	return t.identity.abbreviation if t != null else "-"


func _player(world: FcWorld, player_id: int, stats: FcSeasonStats) -> String:
	var l: Dictionary = stats.lines.get(player_id, {})
	return "-" if l.is_empty() else "%s (%s)" % [l["name"], _abbr(world, l["team"])]


func _talent(world: FcWorld, ratings: FcPlayerRatings) -> float:
	var total := 0.0
	var count := 0
	for t in world.teams.all():
		var values: Array = []
		for pid in t.roster.player_ids:
			values.append(ratings.overall(world.players.get_by_id(pid)))
		values.sort()
		values.reverse()
		for v in values.slice(0, 8):
			total += v
			count += 1
	return total / maxf(1.0, count)


func _age(world: FcWorld, year: int) -> float:
	var total := 0.0
	var count := 0
	for t in world.teams.all():
		for pid in t.roster.player_ids:
			total += world.players.get_by_id(pid).age_on(FcDate.new(year, 7, 1))
			count += 1
	return total / maxf(1.0, count)


func _payroll(world: FcWorld, year: int) -> float:
	var total := 0.0
	for t in world.teams.all():
		total += world.payroll_of_team(t.id, year)
	return total / maxf(1.0, world.teams.count())
