extends SceneTree
## Generates a customizable league and prints a readable report.
##
## Run (PowerShell, from the project folder):
##   ./tools/generate_league.ps1                      default league, seed 2026
##   ./tools/generate_league.ps1 sizes                which team counts and layouts are possible
##   ./tools/generate_league.ps1 seed=12345           same seed = same league
##   ./tools/generate_league.ps1 areas=europe teams=20 conferences=2 divisions=2
##   ./tools/generate_league.ps1 areas=north_america,europe teams=40 conferences=2 divisions=4
##   ./tools/generate_league.ps1 cities=london,paris,madrid,berlin,rome,milan conferences=1 divisions=1
##   ./tools/generate_league.ps1 teams=16 conferences=2 divisions=2 cap=hard playoffs=8 bracket=league qualification=seeding series=3,5,7
##   ./tools/generate_league.ps1 cities=london,paris,madrid,rome conferences=1 divisions=1 nicknames=london:Thames_Kings abbr=paris:PAR
##
## TEAMS:    seed, areas (north_america, south_america, europe, asia, middle_east,
##           oceania, africa, all), teams (4-64), cities (exact list), mode (weighted | largest),
##           nicknames (city:Name,...  use _ for spaces), abbr (city:ABC,...), name (league name)
## STRUCTURE: conferences, divisions (teams must divide evenly; try "sizes")
## SEASON:   games (target games per team), gdiv, gconf, gother (games per opponent; turns auto off)
## PLAYOFFS: playoffs (team count), qualification (division_leaders | seeding),
##           bracket (conference | league), series (e.g. 5,7,7,7)
## SALARY:   cap (soft | hard | none), salarycap (e.g. 140000000)
## OTHER:    roster, freeagents, homeshare (0-1)
## "Rating" is just the average of a player's 28 attributes, a rough yardstick
## for this report; the real overall formula comes with the simulation.


func _initialize() -> void:
	var gen := FcWorldGenerator.create_default()
	var cfg := gen.config
	var seed_value := 2026
	for arg in OS.get_cmdline_user_args():
		if arg == "sizes":
			_print_sizes()
			quit(0)
			return
		var parts: PackedStringArray = arg.split("=", true, 1)
		if parts.size() != 2:
			print("Ignoring '%s' (expected option=value)" % arg)
			continue
		var value := parts[1]
		match parts[0]:
			"seed": seed_value = int(value)
			"areas": cfg.areas = [] as Array[String] if value == "all" else _list(value)
			"teams": cfg.team_count = int(value)
			"cities": cfg.city_keys = _list(value)
			"mode": cfg.selection_mode = value
			"conferences": cfg.conference_count = int(value)
			"divisions": cfg.divisions_per_conference = int(value)
			"name": cfg.league_name = value.replace("_", " ")
			"nicknames": cfg.team_nicknames = _pairs(value, true)
			"abbr": cfg.team_abbreviations = _pairs(value, false)
			"roster": cfg.roster_size = int(value)
			"freeagents": cfg.free_agent_count = int(value)
			"homeshare": cfg.home_country_share = float(value)
			"games": cfg.target_games = int(value)
			"gdiv": cfg.auto_season = false; cfg.games_per_division_opponent = int(value)
			"gconf": cfg.auto_season = false; cfg.games_per_conference_opponent = int(value)
			"gother": cfg.auto_season = false; cfg.games_per_other_conference_opponent = int(value)
			"playoffs": cfg.auto_playoffs = false; cfg.playoff_team_count = int(value)
			"qualification": cfg.auto_playoffs = false; cfg.playoff_qualification = value
			"bracket": cfg.auto_playoffs = false; cfg.playoff_bracket = value
			"series":
				cfg.auto_playoffs = false
				cfg.playoff_series = []
				for s in _list(value):
					cfg.playoff_series.append(int(s))
			"lottery": cfg.draft_lottery = value in ["on", "yes", "true", "1"]
			"cap": cfg.cap_preset = {"soft": "soft_cap_with_hard_limit", "hard": "hard_cap", "none": "no_cap"}.get(value, value)
			"salarycap": cfg.salary_cap = int(value)
			_: print("Unknown option '%s'" % parts[0])

	var problems := gen.validate()
	if not problems.is_empty():
		print("Cannot generate this league:")
		for p in problems:
			print("  - " + p)
		quit(1)
		return

	var t0 := Time.get_ticks_msec()
	var w := gen.generate(seed_value)
	var ms := Time.get_ticks_msec() - t0
	var season := cfg.start_season
	var ref := FcDate.new(season, 7, 1)
	var league: FcLeague = w.leagues.get_by_id(1)
	var rules: FcLeagueRules = w.rules_of_league(league.id)
	print("=== %s (seed %d, generated in %d ms) ===" % [league.name, seed_value, ms])
	print("%d teams, %d players (%d free agents), %d staff" % [
		w.teams.count(), w.players.count(), w.players.count() - w.contracts.count(), w.staff.count()])
	var problems2 := w.validate(season)
	print("Integrity check (incl. rules and payrolls): %s" % ("OK" if problems2.is_empty() else str(problems2)))

	print("")
	print("=== Structure ===")
	for conference in league.conferences:
		print("%s Conference" % conference.name)
		for division in conference.divisions:
			var names: Array = []
			for tid in division.team_ids:
				var t: FcTeam = w.teams.get_by_id(tid)
				names.append(w.cities.get_by_id(t.city_id).name)
			print("  %-14s (%d)  %s" % [division.name, names.size(), ", ".join(names)])

	_print_rules(w, league, rules, season)

	print("")
	print("=== Teams ===")
	print("%-4s %-30s %-15s %-28s %8s %6s %7s %s" % ["Abbr", "Team", "Country", "Arena (capacity)", "Payroll", "AvgAge", "AvgRtg", "Head coach"])
	for t in w.teams.all():
		var city: FcCity = w.cities.get_by_id(t.city_id)
		var arena: FcArena = w.arenas.get_by_id(t.arena_id)
		var ages := 0
		var rating := 0.0
		for pid in t.roster.player_ids:
			var p: FcPlayer = w.players.get_by_id(pid)
			ages += p.age_on(ref)
			rating += _rating(p, w.definitions)
		var n: int = t.roster.size()
		var hc := w.staff_in_role(t.id, FcStaffRole.Id.HEAD_COACH)
		print("%-4s %-30s %-15s %-28s %7.1fM %6.1f %7.1f %s" % [
			t.identity.abbreviation, t.identity.display_name(city.name), city.country,
			"%s (%d)" % [arena.name, arena.capacity], w.payroll_of_team(t.id, season) / 1000000.0,
			float(ages) / n, rating / n, hc.identity.full_name()])

	print("")
	print("=== Ten best players by rating ===")
	var everyone: Array = w.players.all()
	everyone.sort_custom(func(a: FcPlayer, b: FcPlayer): return _rating(a, w.definitions) > _rating(b, w.definitions))
	for i in mini(10, everyone.size()):
		var p: FcPlayer = everyone[i]
		var team := w.team_of_player(p.id)
		var contract := w.active_contract_of(p.id)
		var tag := "FA" if team == null else team.identity.abbreviation
		var pay := 0.0 if contract == null else contract.salary_for(season) / 1000000.0
		print("%-22s %-2s age %2d  %d cm  rating %4.1f  potential %2d  $%5.1fM  %-4s (%s)" % [
			p.identity.full_name(), FcPosition.abbreviation(p.primary_position), p.age_on(ref),
			p.physical.height_cm, _rating(p, w.definitions), p.development.potential,
			pay, tag, p.identity.country])

	print("")
	print("=== Where players come from (rostered) ===")
	var origins := {}
	for t in w.teams.all():
		for pid in t.roster.player_ids:
			var c: String = w.players.get_by_id(pid).identity.country
			origins[c] = int(origins.get(c, 0)) + 1
	var origin_list: Array = origins.keys()
	origin_list.sort_custom(func(a, b): return origins[a] > origins[b])
	var parts_out: Array = []
	for c in origin_list.slice(0, 12):
		parts_out.append("%s %d" % [c, origins[c]])
	print(", ".join(parts_out))
	quit(0)


func _print_rules(w: FcWorld, league: FcLeague, rules: FcLeagueRules, season: int) -> void:
	var plan := FcMatchupPlanner.plan(league, rules.season)
	var first_team: int = league.all_team_ids()[0]
	var division := league.division_of_team(first_team)
	var conference := league.conference_of_team(first_team)
	var conference_teams := 0
	for d in conference.divisions:
		conference_teams += d.team_ids.size()
	var division_opponents := division.team_ids.size() - 1
	var conference_opponents := conference_teams - division.team_ids.size()
	var other_opponents := league.team_count() - conference_teams
	print("")
	print("=== Season rules ===")
	print("Each team plays %d games:" % rules.season.games_per_team(league))
	print("  %d division opponents    x %d = %d" % [division_opponents, rules.season.games_per_division_opponent, division_opponents * rules.season.games_per_division_opponent])
	print("  %d conference opponents  x %d = %d" % [conference_opponents, rules.season.games_per_conference_opponent, conference_opponents * rules.season.games_per_conference_opponent])
	print("  %d other-conference opp. x %d = %d" % [other_opponents, rules.season.games_per_other_conference_opponent, other_opponents * rules.season.games_per_other_conference_opponent])
	print("Whole league: %d games. Home/away balance: every team within %d game%s of an even split." % [
		plan.total_games(), plan.max_home_away_gap(), "" if plan.max_home_away_gap() == 1 else "s"])
	for note in rules.season.advice(league):
		print("  note: " + note)

	print("")
	print("=== Playoffs ===")
	for line in rules.playoffs.describe(league):
		print("  " + line)

	var cap := rules.cap
	print("")
	print("=== Salary rules (%s) ===" % {"soft": "soft cap with hard limit", "hard": "hard cap", "none": "no cap"}[cap.cap_type])
	print("  Salary cap $%.1fM | tax line $%.1fM (rate %d%%) | hard limit $%s | minimum payroll $%.1fM" % [
		cap.salary_cap / 1e6, cap.luxury_tax_line / 1e6, cap.luxury_tax_rate_percent,
		"none" if cap.effective_limit() == 0 else "%.1fM" % (cap.effective_limit() / 1e6), cap.minimum_payroll / 1e6])
	print("  Player salary $%.2fM - $%.1fM | contracts up to %d years, raises up to %d%%" % [
		cap.min_player_salary / 1e6, cap.max_player_salary / 1e6, cap.max_contract_years, cap.max_annual_raise_percent])
	print("  Over the cap a team may: re-sign own players %s, mid-level exception $%.1fM, minimum contracts %s" % [
		"yes" if cap.own_player_exception else "no", cap.mid_level_exception / 1e6, "yes" if cap.minimum_contract_exception else "no"])
	if cap.cap_type == "soft" or cap.cap_type == "none":
		print("  Tax: repeat taxpayers (%d of the last 4 seasons) pay +%d%%; %d%% of the tax is shared equally among teams at or under the cap%s" % [
			cap.repeater_years_required, cap.repeater_tax_extra_percent, cap.tax_distribution_percent,
			"" if cap.restriction_line == 0 else "; above $%.1fM exceptions are unavailable and trades must match salaries" % (cap.restriction_line / 1e6)])
	print("  Rookie scale: first pick $%.1fM down to $%.2fM, %d-year contracts (%d guaranteed)" % [
		cap.rookie_scale_top / 1e6, cap.rookie_scale_bottom / 1e6, cap.rookie_contract_years, cap.rookie_guaranteed_years])
	if cap.cornerstone_enabled:
		print("  Cornerstone extension: one per team, up to $%.1fM, after %d seasons with the team" % [cap.cornerstone_max_salary / 1e6, cap.cornerstone_min_seasons_with_team])
	print("  Cap holds %s | sign-and-trade %s | no-trade clauses %s" % [
		"on (%d%% of last salary)" % cap.cap_hold_percent if cap.cap_holds_enabled else "off",
		"allowed" if cap.sign_and_trade_allowed else "banned",
		"after %d seasons with a team" % cap.no_trade_min_seasons_with_team if cap.no_trade_clauses_allowed else "off"])
	var payrolls: Array = []
	var over_cap := 0
	var taxed := 0
	var tax_total := 0
	for t in w.teams.all():
		var p := w.payroll_of_team(t.id, season)
		payrolls.append(p)
		if p > cap.salary_cap:
			over_cap += 1
		if cap.luxury_tax(p) > 0:
			taxed += 1
			tax_total += cap.luxury_tax(p)
	payrolls.sort()
	print("  Payrolls: lowest $%.1fM, median $%.1fM, highest $%.1fM | %d teams over the cap, %d paying tax ($%.1fM total)" % [
		payrolls[0] / 1e6, payrolls[floori(payrolls.size() / 2.0)] / 1e6, payrolls[payrolls.size() - 1] / 1e6, over_cap, taxed, tax_total / 1e6])


func _print_sizes() -> void:
	print("=== Possible league sizes (4-%d teams) ===" % FcLeagueStructure.MAX_TEAMS_AT_CREATION)
	print("Divisions must be equal, with 3-8 teams each (4-8 team leagues may be one division).")
	print("")
	print("%-6s %s" % ["Teams", "Layouts (conferences x divisions x teams per division)"])
	for n in range(FcLeagueStructure.MIN_TEAMS, FcLeagueStructure.MAX_TEAMS_AT_CREATION + 1):
		var options := FcLeagueStructure.valid_structures(n)
		if options.is_empty():
			print("%-6d not possible" % n)
			continue
		var parts: Array = []
		for s in options.slice(0, 4):
			parts.append("%dx%dx%d" % [s["conferences"], s["divisions_per_conference"], s["teams_per_division"]])
		print("%-6d %s" % [n, "  ".join(parts)])


func _list(text: String) -> Array[String]:
	var out: Array[String] = []
	for part in text.split(","):
		if not part.strip_edges().is_empty():
			out.append(part.strip_edges())
	return out


## "london:Thames_Kings,paris:Parisians" -> {"london": "Thames Kings", ...}
func _pairs(text: String, underscores_to_spaces: bool) -> Dictionary:
	var out := {}
	for item in _list(text):
		var kv := item.split(":", true, 1)
		if kv.size() == 2:
			out[kv[0]] = kv[1].replace("_", " ") if underscores_to_spaces else kv[1]
	return out


func _rating(p: FcPlayer, defs: FcDefinitionSet) -> float:
	var total := 0
	for key in defs.attributes.keys():
		total += p.attributes.get_value(key)
	return float(total) / defs.attributes.size()
