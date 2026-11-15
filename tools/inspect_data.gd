extends SceneTree
## Prints a human-readable tour of the data model using sample data.
## Run:  godot_console --headless --path . --script res://tools/inspect_data.gd
## (or ./tools/inspect_data.ps1)


func _initialize() -> void:
	var defs := FcDefinitionSet.load_default()
	print("=== Definitions loaded from data/definitions/ ===")
	for catalog in defs.all():
		print("%s: %d entries, categories: %s" % [catalog.kind, catalog.size(), ", ".join(catalog.categories())])

	var w := FcTestData.world()
	var p: FcPlayer = w.players.get_by_id(1)
	p.identity.first_name = "Marcus"
	p.identity.last_name = "Vale"
	p.attributes.set_value("three_point", 88)
	p.attributes.set_value("speed", 74)
	p.development.potential = 92

	print("")
	print("=== Sample player ===")
	print("%s, age %d on 2026-10-20, %s, %d cm / %d kg, potential %d" % [
		p.identity.full_name(), p.age_on(FcDate.new(2026, 10, 20)),
		FcPosition.abbreviation(p.primary_position), p.physical.height_cm,
		p.physical.weight_kg, p.development.potential])
	for key in defs.attributes.keys():
		if p.attributes.get_value(key) != defs.attributes.get_def(key).default_value:
			print("  %s = %d" % [defs.attributes.get_def(key).display_name, p.attributes.get_value(key)])

	var t: FcTeam = w.teams.get_by_id(1)
	var city: FcCity = w.cities.get_by_id(t.city_id)
	print("")
	print("=== Sample team ===")
	print("%s (%s), arena: %s (capacity %d), roster: %s" % [
		t.identity.display_name(city.name), t.identity.abbreviation,
		w.arenas.get_by_id(t.arena_id).name, w.arenas.get_by_id(t.arena_id).capacity,
		str(t.roster.player_ids)])

	var c := w.active_contract_of(p.id)
	print("")
	print("=== Sample contract ===")
	print("Player %d with team %d, seasons %d-%d, total value $%d, 2026 cap hit $%d" % [
		c.player_id, c.team_id, c.start_season(), c.end_season(), c.total_value(), c.cap_hit_for(2026)])

	print("")
	print("=== Sample staff (current jobs of the team) ===")
	for sc in w.staff_contracts_of_team(t.id):
		var member: FcStaffMember = w.staff.get_by_id(sc.staff_id)
		print("%s: %s, reputation %d, $%d in 2026" % [
			FcStaffRole.display_name(sc.role), member.identity.full_name(),
			member.reputation, sc.salary_for(2026)])

	print("")
	var problems := w.validate()
	print("World integrity check: %s" % ("OK, no problems" if problems.is_empty() else str(problems)))
	print("Saved snapshot size: %d characters of JSON" % JSON.stringify(w.to_dict()).length())
	quit(0)
