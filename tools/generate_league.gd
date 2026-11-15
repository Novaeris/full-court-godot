extends SceneTree
## Generates a customizable league and prints a readable report.
##
## Run (PowerShell, from the project folder):
##   ./tools/generate_league.ps1                      default league, seed 2026
##   ./tools/generate_league.ps1 seed=12345           same seed = same league
##   ./tools/generate_league.ps1 areas=europe teams=20 conferences=2 divisions=2
##   ./tools/generate_league.ps1 areas=north_america,europe teams=36
##   ./tools/generate_league.ps1 areas=all teams=24 mode=largest
##   ./tools/generate_league.ps1 cities=london,paris,madrid,berlin,rome,milan conferences=1 divisions=1
##   ./tools/generate_league.ps1 name=Euro_Hoops roster=13 freeagents=40
## Options: seed, areas (north_america, south_america, europe, asia, oceania,
## africa, all), teams, cities (exact list), mode (weighted | largest),
## conferences, divisions, name (use _ for spaces), roster, freeagents.
## "Rating" is just the average of a player's 28 attributes, a rough yardstick
## for this report; the real overall formula comes with the simulation.


func _initialize() -> void:
	var gen := FcWorldGenerator.create_default()
	var cfg := gen.config
	var seed_value := 2026
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=", true, 1)
		if parts.size() != 2:
			print("Ignoring '%s' (expected option=value)" % arg)
			continue
		var value := parts[1]
		match parts[0]:
			"seed": seed_value = int(value)
			"areas":
				cfg.areas = [] as Array[String] if value == "all" else _list(value)
			"teams": cfg.team_count = int(value)
			"cities": cfg.city_keys = _list(value)
			"mode": cfg.selection_mode = value
			"conferences": cfg.conference_count = int(value)
			"divisions": cfg.divisions_per_conference = int(value)
			"name": cfg.league_name = value.replace("_", " ")
			"roster": cfg.roster_size = int(value)
			"freeagents": cfg.free_agent_count = int(value)
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
	print("=== %s (seed %d, generated in %d ms) ===" % [league.name, seed_value, ms])
	print("%d teams, %d players (%d free agents), %d staff" % [
		w.teams.count(), w.players.count(), w.players.count() - w.contracts.count(), w.staff.count()])
	var problems2 := w.validate()
	print("Integrity check: %s" % ("OK" if problems2.is_empty() else str(problems2)))

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

	print("")
	print("=== Teams ===")
	print("%-4s %-30s %-15s %-28s %7s %6s %7s %s" % ["Abbr", "Team", "Country", "Arena (capacity)", "Payroll", "AvgAge", "AvgRtg", "Head coach"])
	for t in w.teams.all():
		var city: FcCity = w.cities.get_by_id(t.city_id)
		var arena: FcArena = w.arenas.get_by_id(t.arena_id)
		var payroll := 0
		var ages := 0
		var rating := 0.0
		for pid in t.roster.player_ids:
			var p: FcPlayer = w.players.get_by_id(pid)
			payroll += w.active_contract_of(pid).salary_for(season)
			ages += p.age_on(ref)
			rating += _rating(p, w.definitions)
		var n: int = t.roster.size()
		var hc := w.staff_in_role(t.id, FcStaffRole.Id.HEAD_COACH)
		print("%-4s %-30s %-15s %-28s %6.1fM %6.1f %7.1f %s" % [
			t.identity.abbreviation, t.identity.display_name(city.name), city.country,
			"%s (%d)" % [arena.name, arena.capacity], payroll / 1000000.0,
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

	var first: FcTeam = w.teams.get_by_id(1)
	print("")
	print("=== Full roster of %s ===" % first.identity.display_name(w.cities.get_by_id(first.city_id).name))
	for pid in first.roster.player_ids:
		var p: FcPlayer = w.players.get_by_id(pid)
		var c := w.active_contract_of(pid)
		print("%-22s %-2s/%-2s age %2d  %d cm %3d kg  rating %4.1f  $%5.1fM thru %d  %s" % [
			p.identity.full_name(), FcPosition.abbreviation(p.primary_position),
			FcPosition.abbreviation(p.secondary_position), p.age_on(ref), p.physical.height_cm,
			p.physical.weight_kg, _rating(p, w.definitions), c.salary_for(season) / 1000000.0,
			c.end_season(), p.identity.country])
	quit(0)


func _list(text: String) -> Array[String]:
	var out: Array[String] = []
	for part in text.split(","):
		if not part.strip_edges().is_empty():
			out.append(part.strip_edges())
	return out


func _rating(p: FcPlayer, defs: FcDefinitionSet) -> float:
	var total := 0
	for key in defs.attributes.keys():
		total += p.attributes.get_value(key)
	return float(total) / defs.attributes.size()
