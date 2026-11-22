extends SceneTree
## Evidence for the basketball authenticity audit (docs/audits/BASKETBALL_AUTHENTICITY_AUDIT.md). Generates several leagues with fixed seeds
## and measures identity and roster facts: jersey-number collisions of the hashed display number, rosters, names, team identity,
## colour contrast, physical plausibility by position, ages and handedness. Read-only: it changes nothing and prints counts.
##
## Run:  godot_console --headless --path . --script res://tools/audit_identity.gd -- [leagues=20] [seed=5000]

var _tally := {}


func _count(key: String, by: int = 1) -> void:
	_tally[key] = int(_tally.get(key, 0)) + by


func _initialize() -> void:
	var leagues := 20
	var seed_base := 5000
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.split("=", true, 1)
		if kv.size() == 2 and kv[0] == "leagues":
			leagues = int(kv[1])
		elif kv.size() == 2 and kv[0] == "seed":
			seed_base = int(kv[1])
	var gen := FcWorldGenerator.create_default()
	var by_position := {}   # position -> {"h": [..], "w": [..]}
	var on := FcDate.new(2026, 10, 20)
	var team_count := 0
	var roster_size_min := 999
	var roster_size_max := 0
	var worst_team_collisions := 0
	var all_ages: Array = []
	var lefties := 0
	var players_seen := 0
	for i in leagues:
		var w := gen.generate(seed_base + i)
		var problems := w.validate(0)
		_count("leagues")
		_count("league_validate_problems", problems.size())
		var abbreviations := {}
		var nicknames := {}
		var arena_names := {}
		var full_names := {}
		for t in w.teams.all():
			team_count += 1
			var team: FcTeam = t
			if abbreviations.has(team.identity.abbreviation):
				_count("duplicate_abbreviation")
			abbreviations[team.identity.abbreviation] = true
			var nick_key := "%s|%s" % [str(team.city_id), team.identity.nickname]
			if nicknames.has(nick_key):
				_count("duplicate_city_nickname")
			nicknames[nick_key] = true
			var arena: FcArena = w.arenas.get_by_id(team.arena_id)
			if arena != null:
				if arena_names.has(arena.name):
					_count("duplicate_arena_name")
				arena_names[arena.name] = true
			var cp := _contrast(team.branding.primary_color, team.branding.secondary_color)
			if cp < 3.0:
				_count("primary_vs_secondary_contrast_below_3")
			if cp < 1.5:
				_count("primary_vs_secondary_contrast_below_1_5")
			var size := team.roster.size()
			roster_size_min = mini(roster_size_min, size)
			roster_size_max = maxi(roster_size_max, size)
			var rules := w.rules_of_team(team.id)
			if rules != null and size < rules.roster_min:
				_count("roster_below_minimum")
			var numbers := {}
			var collisions := 0
			var position_present := {}
			for pid in team.roster.player_ids:
				var number := FcFranchiseHistory.jersey_for(int(pid))
				if numbers.has(number):
					collisions += 1
				numbers[number] = true
				var p: FcPlayer = w.players.get_by_id(pid)
				if p != null:
					position_present[p.primary_position] = true
			_count("team_collision_pairs", collisions)
			if collisions > 0:
				_count("teams_with_a_jersey_collision")
			worst_team_collisions = maxi(worst_team_collisions, collisions)
			for pos in [1, 2, 3, 4, 5]:
				if not position_present.has(pos):
					_count("team_missing_primary_position_%s" % FcPosition.abbreviation(pos))
		for p in w.players.all():
			var player: FcPlayer = p
			players_seen += 1
			var full := player.identity.full_name()
			if full_names.has(full):
				_count("duplicate_full_name_in_league")
			full_names[full] = true
			var pos: int = player.primary_position
			if not by_position.has(pos):
				by_position[pos] = {"h": [], "w": []}
			by_position[pos]["h"].append(player.physical.height_cm)
			by_position[pos]["w"].append(player.physical.weight_kg)
			var h := float(player.physical.height_cm)
			var kg := float(player.physical.weight_kg)
			var bmi := kg / pow(h / 100.0, 2.0)
			if bmi < 18.5:
				_count("bmi_below_18_5")
			if bmi > 32.0:
				_count("bmi_above_32")
			var reach := player.physical.wingspan_cm - player.physical.height_cm
			if reach < -2:
				_count("wingspan_shorter_than_height")
			if reach > 20:
				_count("wingspan_over_20_cm_longer_than_height")
			if pos == FcPosition.Id.C and player.physical.height_cm < 195:
				_count("center_under_195_cm")
			if pos == FcPosition.Id.PG and player.physical.height_cm > 205:
				_count("point_guard_over_205_cm")
			if player.secondary_position != FcPosition.Id.NONE and absi(player.secondary_position - pos) > 2:
				_count("secondary_position_two_or_more_steps_away")
			if player.secondary_position == pos:
				_count("secondary_equals_primary")
			var age := player.age_on(on)
			all_ages.append(age)
			if player.physical.handedness == FcPlayerPhysical.Handedness.LEFT:
				lefties += 1
			if player.identity.birth_date != null and not player.identity.birth_date.is_valid():
				_count("invalid_birth_date")
			if player.identity.country == "":
				_count("empty_country")
	print("=== identity audit: %d leagues from seed %d, %d teams, %d players ===" % [leagues, seed_base, team_count, players_seen])
	print("roster sizes %d to %d; world.validate problems across leagues: %d" % [roster_size_min, roster_size_max, int(_tally.get("league_validate_problems", 0))])
	print("jersey display number (hashed per player, FcFranchiseHistory.jersey_for): teams with at least one collision %d of %d (%.1f%%), colliding pairs in total %d, worst team %d" % [
		int(_tally.get("teams_with_a_jersey_collision", 0)), team_count, 100.0 * float(_tally.get("teams_with_a_jersey_collision", 0)) / maxf(1.0, team_count), int(_tally.get("team_collision_pairs", 0)), worst_team_collisions])
	all_ages.sort()
	print("ages on %s: min %d, median %d, max %d; left-handed %.1f%%" % ["2026-10-20", all_ages[0], all_ages[all_ages.size() / 2], all_ages[all_ages.size() - 1], 100.0 * lefties / maxf(1.0, players_seen)])
	for pos in [1, 2, 3, 4, 5]:
		if by_position.has(pos):
			var hs: Array = by_position[pos]["h"]
			var ws: Array = by_position[pos]["w"]
			hs.sort()
			ws.sort()
			print("  %-2s n=%5d height cm min %d median %d max %d | weight kg min %d median %d max %d" % [FcPosition.abbreviation(pos), hs.size(), hs[0], hs[hs.size() / 2], hs[hs.size() - 1], ws[0], ws[ws.size() / 2], ws[ws.size() - 1]])
	var keys: Array = _tally.keys()
	keys.sort()
	for k in keys:
		print("  %s = %d" % [k, _tally[k]])
	quit(0)


## WCAG contrast ratio of two "#RRGGBB" colours.
func _contrast(a: String, b: String) -> float:
	var la := _luminance(Color(a))
	var lb := _luminance(Color(b))
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _luminance(c: Color) -> float:
	var parts := [c.r, c.g, c.b]
	var lin: Array = []
	for v in parts:
		lin.append(v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]
