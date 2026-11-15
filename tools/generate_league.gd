extends SceneTree
## Generates a full fictional league and prints a readable report.
## Run:  ./tools/generate_league.ps1            (default seed 2026)
##       ./tools/generate_league.ps1 12345      (any seed: same seed = same league)
## "Rating" below is just the average of a player's 28 attributes, a rough
## yardstick for this report; the real overall formula comes with the simulation.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value: int = int(args[0]) if args.size() > 0 and args[0].is_valid_int() else 2026
	var gen := FcWorldGenerator.create_default()
	var problems := gen.validate()
	if not problems.is_empty():
		print("Generator data problems: ", problems)
		quit(1)
		return

	var t0 := Time.get_ticks_msec()
	var w := gen.generate(seed_value)
	var ms := Time.get_ticks_msec() - t0
	var season := gen.config.start_season
	var ref := FcDate.new(season, 7, 1)
	print("=== Full Court league, seed %d (generated in %d ms) ===" % [seed_value, ms])
	print("%d teams, %d players (%d free agents), %d staff" % [
		w.teams.count(), w.players.count(), w.players.count() - w.contracts.count(), w.staff.count()])
	var problems2 := w.validate()
	print("Integrity check: %s" % ("OK" if problems2.is_empty() else str(problems2)))

	print("")
	print("=== Teams ===")
	print("%-4s %-26s %-24s %7s %6s %7s %s" % ["Abbr", "Team", "Arena (capacity)", "Payroll", "AvgAge", "AvgRtg", "Head coach / GM"])
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
		var gm := w.staff_in_role(t.id, FcStaffRole.Id.GENERAL_MANAGER)
		print("%-4s %-26s %-24s %6.1fM %6.1f %7.1f %s / %s" % [
			t.identity.abbreviation, t.identity.display_name(city.name),
			"%s (%d)" % [arena.name, arena.capacity], payroll / 1000000.0,
			float(ages) / n, rating / n, hc.identity.full_name(), gm.identity.full_name()])

	print("")
	print("=== Ten best players by rating ===")
	var everyone: Array = w.players.all()
	everyone.sort_custom(func(a: FcPlayer, b: FcPlayer): return _rating(a, w.definitions) > _rating(b, w.definitions))
	for i in 10:
		var p: FcPlayer = everyone[i]
		var team := w.team_of_player(p.id)
		var contract := w.active_contract_of(p.id)
		print("%-22s %-2s age %2d  %d cm  rating %4.1f  potential %2d  $%5.1fM  %s  (%s)" % [
			p.identity.full_name(), FcPosition.abbreviation(p.primary_position), p.age_on(ref),
			p.physical.height_cm, _rating(p, w.definitions), p.development.potential,
			contract.salary_for(season) / 1000000.0, team.identity.abbreviation, p.identity.country])

	print("")
	print("=== By position (all rostered players) ===")
	print("%-4s %5s %8s %8s %8s %8s" % ["Pos", "Count", "Height", "Weight", "BallHdl", "Blocks"])
	for pos in [FcPosition.Id.PG, FcPosition.Id.SG, FcPosition.Id.SF, FcPosition.Id.PF, FcPosition.Id.C]:
		var count := 0
		var h := 0.0
		var wt := 0.0
		var bh := 0.0
		var bl := 0.0
		for p: FcPlayer in everyone:
			if p.primary_position == pos and w.team_of_player(p.id) != null:
				count += 1
				h += p.physical.height_cm
				wt += p.physical.weight_kg
				bh += p.attributes.get_value("ball_handling")
				bl += p.attributes.get_value("blocks")
		print("%-4s %5d %7.1f %7.1f %8.1f %8.1f" % [FcPosition.abbreviation(pos), count, h / count, wt / count, bh / count, bl / count])

	var first: FcTeam = w.teams.get_by_id(1)
	print("")
	print("=== Full roster of %s ===" % first.identity.display_name(w.cities.get_by_id(first.city_id).name))
	for pid in first.roster.player_ids:
		var p: FcPlayer = w.players.get_by_id(pid)
		var c := w.active_contract_of(pid)
		print("%-22s %-2s/%-2s age %2d  %d cm %3d kg  rating %4.1f  $%5.1fM thru %d" % [
			p.identity.full_name(), FcPosition.abbreviation(p.primary_position),
			FcPosition.abbreviation(p.secondary_position), p.age_on(ref), p.physical.height_cm,
			p.physical.weight_kg, _rating(p, w.definitions), c.salary_for(season) / 1000000.0, c.end_season()])
	quit(0)


func _rating(p: FcPlayer, defs: FcDefinitionSet) -> float:
	var total := 0
	for key in defs.attributes.keys():
		total += p.attributes.get_value(key)
	return float(total) / defs.attributes.size()
