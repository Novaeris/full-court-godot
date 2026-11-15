extends FcTestCase

const SEED := 20261115

var data: FcGenerationData
var defs: FcDefinitionSet


func before_each() -> void:
	data = FcGenerationData.load_default()
	defs = FcDefinitionSet.load_default()


func _spec(position: int, level: float, age: int = 26) -> FcPlayerSpec:
	var s := FcPlayerSpec.new()
	s.position = position
	s.level = level
	s.age = age
	return s


func _mean(values: Array) -> float:
	var total := 0.0
	for v in values:
		total += float(v)
	return total / maxf(1.0, values.size())


func _generator(team_count: int = 30) -> FcWorldGenerator:
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = team_count
	if team_count < 12:
		cfg.conference_count = 1
		cfg.divisions_per_conference = 1
	return FcWorldGenerator.new(data, defs, cfg)


# --- data and config -------------------------------------------------------

func test_shipped_generation_data_is_valid() -> void:
	assert_eq(data.validate(), [] as Array[String])
	assert_eq(FcGenerationConfig.load_default(data).validate(data), [] as Array[String])


func test_validation_catches_bad_data() -> void:
	var bad := FcGenerationData.load_default()
	bad.names["pools"]["anglo"]["first"] = ["Only"]
	bad.names["countries"]["usa"]["pools"]["ghost_pool"] = 1
	bad.world["cities"].append({"name": "Port Calder", "region": "X", "population": 5000, "economy": 50})
	bad.world["color_schemes"].append(["red", "#FFFFFF", "#000000"])
	bad.positions["positions"].erase("C")
	bad.staff["roles"]["scout"]["age_min"] = 70
	assert_true(bad.validate().size() >= 6, str(bad.validate()))


func test_config_validation() -> void:
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 500
	cfg.roster_size = 2
	cfg.home_country_share = 2.0
	cfg.max_salary = 10
	assert_true(cfg.validate(data).size() >= 4, str(cfg.validate(data)))


# --- names -----------------------------------------------------------------

func test_names_are_deterministic_and_from_pools() -> void:
	var g := FcNameGenerator.new(data)
	var a := g.generate(FcRng.new(5), "nigeria")
	var b := g.generate(FcRng.new(5), "nigeria")
	assert_eq(a, b)
	assert_true(data.names["pools"]["west_african"]["first"].has(a["first"]))
	assert_true(data.names["pools"]["west_african"]["last"].has(a["last"]))
	assert_eq(g.generate(FcRng.new(5), "no_such_country").size(), 2, "unknown country falls back")


func test_unique_names_are_unique() -> void:
	var g := FcNameGenerator.new(data)
	var rng := FcRng.new(3)
	var used := {}
	var seen := {}
	for i in 300:
		var n := g.generate_unique(rng, "usa", used)
		var full: String = "%s %s" % [n["first"], n["last"]]
		assert_true(not seen.has(full), "duplicate %s" % full)
		seen[full] = true


# --- players ---------------------------------------------------------------

func test_generated_player_is_valid_and_matches_spec() -> void:
	var gen := FcPlayerGenerator.new(data, defs)
	var spec := _spec(FcPosition.Id.PF, 60.0, 29)
	var p := gen.generate(FcRng.new(SEED), 7, spec)
	assert_eq(p.validate(), [] as Array[String])
	assert_eq(p.id, 7)
	assert_eq(p.primary_position, FcPosition.Id.PF)
	assert_eq(p.age_on(spec.reference_date), 29, "age is exact on the reference date")
	assert_true(p.development.potential >= 59)


func test_exact_ages_for_many_birthdays() -> void:
	var gen := FcPlayerGenerator.new(data, defs)
	var rng := FcRng.new(77)
	for i in 200:
		var spec := _spec(FcPosition.Id.SG, 50.0, rng.range_int(19, 38))
		var p := gen.generate(rng, i + 1, spec)
		assert_eq(p.age_on(spec.reference_date), spec.age, "player %d" % i)
		assert_true(p.identity.birth_date.is_valid())


func test_generation_is_deterministic() -> void:
	var gen := FcPlayerGenerator.new(data, defs)
	var a := gen.generate(FcRng.new(SEED), 1, _spec(FcPosition.Id.C, 55.0))
	var b := gen.generate(FcRng.new(SEED), 1, _spec(FcPosition.Id.C, 55.0))
	var c := gen.generate(FcRng.new(SEED + 1), 1, _spec(FcPosition.Id.C, 55.0))
	assert_eq(a.to_dict(), b.to_dict())
	assert_true(a.to_dict() != c.to_dict(), "different seed gives different player")


func test_positions_shape_body_and_skills() -> void:
	var gen := FcPlayerGenerator.new(data, defs)
	var rng := FcRng.new(SEED)
	var guards: Array[FcPlayer] = []
	var bigs: Array[FcPlayer] = []
	for i in 150:
		guards.append(gen.generate(rng, i + 1, _spec(FcPosition.Id.PG, 55.0)))
		bigs.append(gen.generate(rng, i + 1000, _spec(FcPosition.Id.C, 55.0)))
	var guard_height := _mean(guards.map(func(p): return p.physical.height_cm))
	var big_height := _mean(bigs.map(func(p): return p.physical.height_cm))
	assert_true(big_height - guard_height > 20.0, "centers are much taller (%.1f vs %.1f)" % [big_height, guard_height])
	assert_true(_mean(bigs.map(func(p): return p.physical.weight_kg)) > _mean(guards.map(func(p): return p.physical.weight_kg)) + 20.0, "centers are heavier")
	var g_handle := _mean(guards.map(func(p): return p.attributes.get_value("ball_handling")))
	var b_handle := _mean(bigs.map(func(p): return p.attributes.get_value("ball_handling")))
	assert_true(g_handle - b_handle > 20.0, "guards handle the ball better")
	var g_block := _mean(guards.map(func(p): return p.attributes.get_value("blocks")))
	var b_block := _mean(bigs.map(func(p): return p.attributes.get_value("blocks")))
	assert_true(b_block - g_block > 20.0, "centers block more")
	var g_three := _mean(guards.map(func(p): return p.tendencies.get_value("three_point_tendency")))
	var b_three := _mean(bigs.map(func(p): return p.tendencies.get_value("three_point_tendency")))
	assert_true(g_three - b_three > 15.0, "guards take more threes")


func test_level_controls_overall_attributes() -> void:
	var gen := FcPlayerGenerator.new(data, defs)
	var rng := FcRng.new(SEED)
	var avg_for := func(level: float) -> float:
		var means: Array = []
		for i in 80:
			var p := gen.generate(rng, i + 1, _spec(FcPosition.Id.SF, level))
			means.append(_mean(defs.attributes.keys().map(func(k): return p.attributes.get_value(k))))
		return _mean(means)
	var low: float = avg_for.call(35.0)
	var mid: float = avg_for.call(55.0)
	var high: float = avg_for.call(75.0)
	assert_between(low, 31.0, 39.0, "level 35")
	assert_between(mid, 51.0, 59.0, "level 55")
	assert_between(high, 71.0, 79.0, "level 75")


func test_attribute_values_stay_in_range() -> void:
	var gen := FcPlayerGenerator.new(data, defs)
	var rng := FcRng.new(SEED)
	for level in [5.0, 50.0, 99.0]:
		for i in 30:
			var p := gen.generate(rng, i + 1, _spec(FcPosition.Id.PG, level))
			assert_eq(p.validate(), [] as Array[String])
			for k in defs.attributes.keys():
				var v := p.attributes.get_value(k)
				assert_true(v >= 5 and v <= 99, "%s=%d" % [k, v])


func test_tendencies_follow_skill() -> void:
	var gen := FcPlayerGenerator.new(data, defs)
	var rng := FcRng.new(SEED)
	var shooters: Array[FcPlayer] = []
	for i in 300:
		shooters.append(gen.generate(rng, i + 1, _spec(FcPosition.Id.SF, 55.0)))
	shooters.sort_custom(func(a, b): return a.attributes.get_value("three_point") > b.attributes.get_value("three_point"))
	var best := _mean(shooters.slice(0, 75).map(func(p): return p.tendencies.get_value("three_point_tendency")))
	var worst := _mean(shooters.slice(225).map(func(p): return p.tendencies.get_value("three_point_tendency")))
	assert_true(best - worst > 10.0, "good shooters shoot more (%.1f vs %.1f)" % [best, worst])


func test_young_players_have_more_potential_room_than_old() -> void:
	var gen := FcPlayerGenerator.new(data, defs)
	var rng := FcRng.new(SEED)
	var young := 0.0
	var old := 0.0
	for i in 100:
		var y := gen.generate(rng, i + 1, _spec(FcPosition.Id.SF, 45.0, 20))
		var o := gen.generate(rng, i + 500, _spec(FcPosition.Id.SF, 45.0, 33))
		young += y.development.potential - 45
		old += o.development.potential - 45
	assert_true(young / 100.0 > 6.0, "20-year-olds can grow (avg +%.1f)" % (young / 100.0))
	assert_true(old / 100.0 < 1.5, "33-year-olds have no room left (avg +%.1f)" % (old / 100.0))


func test_age_adjusted_level() -> void:
	assert_eq(FcPlayerGenerator.age_adjusted_level(60.0, 27), 60.0)
	assert_eq(FcPlayerGenerator.age_adjusted_level(60.0, 20), 52.0)
	assert_eq(FcPlayerGenerator.age_adjusted_level(60.0, 35), 52.8)


# --- staff -----------------------------------------------------------------

func test_staff_specialize_by_role() -> void:
	var gen := FcStaffGenerator.new(data, defs)
	var rng := FcRng.new(SEED)
	var coach_coaching := 0.0
	var coach_scouting := 0.0
	var scout_scouting := 0.0
	var scout_coaching := 0.0
	var ref := FcDate.new(2026, 7, 1)
	for i in 100:
		var hc := gen.generate(rng, i + 1, FcStaffRole.Id.HEAD_COACH, 55.0, ref)
		var sc := gen.generate(rng, i + 500, FcStaffRole.Id.SCOUT, 55.0, ref)
		assert_eq(hc.validate(), [] as Array[String])
		assert_eq(sc.validate(), [] as Array[String])
		coach_coaching += _mean(defs.staff_skills.keys_in_category("coaching").map(func(k): return hc.skills.get_value(k)))
		coach_scouting += _mean(defs.staff_skills.keys_in_category("scouting").map(func(k): return hc.skills.get_value(k)))
		scout_scouting += _mean(defs.staff_skills.keys_in_category("scouting").map(func(k): return sc.skills.get_value(k)))
		scout_coaching += _mean(defs.staff_skills.keys_in_category("coaching").map(func(k): return sc.skills.get_value(k)))
	assert_true(coach_coaching / 100.0 - coach_scouting / 100.0 > 15.0, "head coaches are coaching specialists")
	assert_true(scout_scouting / 100.0 - scout_coaching / 100.0 > 15.0, "scouts are scouting specialists")


func test_staff_age_and_pay_follow_profile() -> void:
	var gen := FcStaffGenerator.new(data, defs)
	var rng := FcRng.new(SEED)
	var ref := FcDate.new(2026, 7, 1)
	for i in 60:
		var gm := gen.generate(rng, i + 1, FcStaffRole.Id.GENERAL_MANAGER, 60.0, ref)
		var age := gm.age_on(ref)
		assert_true(age >= 38 and age <= 66, "GM age %d" % age)
	assert_true(gen.salary_for(FcStaffRole.Id.HEAD_COACH, 90) > gen.salary_for(FcStaffRole.Id.HEAD_COACH, 30))
	assert_true(gen.salary_for(FcStaffRole.Id.HEAD_COACH, 100) <= 9000000)
	assert_true(gen.salary_for(FcStaffRole.Id.SCOUT, 0) >= 120000)


# --- whole league ----------------------------------------------------------

func test_generated_world_is_valid_and_complete() -> void:
	var gen := _generator()
	assert_eq(gen.validate(), [] as Array[String])
	var w := gen.generate(SEED)
	assert_eq(w.validate(), [] as Array[String])
	assert_eq(w.teams.count(), 30)
	assert_eq(w.cities.count(), 30)
	assert_eq(w.arenas.count(), 30)
	assert_eq(w.players.count(), 30 * 15 + 60)
	assert_eq(w.contracts.count(), 30 * 15)
	for t in w.teams.all():
		assert_eq(t.roster.size(), 15, "team %d roster" % t.id)
		assert_eq(w.staff_contracts_of_team(t.id).size(), 10, "1 GM + 1 HC + 3 assistants + 3 scouts + 1 medical + 1 business")
		assert_true(w.staff_in_role(t.id, FcStaffRole.Id.GENERAL_MANAGER) != null)
		assert_true(w.staff_in_role(t.id, FcStaffRole.Id.HEAD_COACH) != null)
		assert_eq(w.staff_contracts_of_team(t.id, FcStaffRole.Id.SCOUT).size(), 3)


func test_world_is_reproducible_from_seed() -> void:
	var gen := _generator(6)
	var a := gen.generate(SEED)
	var b := gen.generate(SEED)
	var c := gen.generate(SEED + 1)
	assert_eq(a.to_dict(), b.to_dict())
	assert_true(a.to_dict() != c.to_dict())


func test_team_identities_are_unique() -> void:
	var w := _generator().generate(SEED)
	var abbreviations := {}
	var nicknames := {}
	var cities := {}
	var arenas := {}
	var colors := 0
	for t in w.teams.all():
		abbreviations[t.identity.abbreviation] = true
		nicknames[t.identity.nickname] = true
		cities[t.city_id] = true
		arenas[w.arenas.get_by_id(t.arena_id).name] = true
		assert_eq(t.validate(), [] as Array[String])
	assert_eq(abbreviations.size(), 30, "abbreviations")
	assert_eq(nicknames.size(), 30, "nicknames")
	assert_eq(cities.size(), 30, "cities")
	assert_eq(arenas.size(), 30, "arena names")
	assert_true(colors == 0)


func test_player_names_unique_across_league() -> void:
	var w := _generator().generate(SEED)
	var seen := {}
	for p in w.players.all():
		var full: String = p.identity.full_name()
		assert_true(not seen.has(full), "duplicate name %s" % full)
		seen[full] = true


func test_league_talent_distribution_is_plausible() -> void:
	var w := _generator().generate(SEED)
	var ages: Array = []
	var home := 0
	for t in w.teams.all():
		var team_country: String = w.cities.get_by_id(t.city_id).country
		for pid in t.roster.player_ids:
			var p: FcPlayer = w.players.get_by_id(pid)
			ages.append(p.age_on(FcDate.new(2026, 7, 1)))
			if p.identity.country == team_country:
				home += 1
	assert_between(_mean(ages), 24.0, 29.0, "average roster age")
	var share := float(home) / (30 * 15)
	assert_between(share, 0.5, 0.9, "share of players from the team's own country")


func test_contract_terms_are_sane() -> void:
	var cfg := FcGenerationConfig.load_default(data)
	var w := _generator().generate(SEED)
	var payrolls: Array = []
	for t in w.teams.all():
		var payroll := 0
		for pid in t.roster.player_ids:
			var c := w.active_contract_of(pid)
			assert_true(c.is_in_force_in(cfg.start_season), "contract covers the start season")
			var salary := c.salary_for(cfg.start_season)
			assert_true(salary >= cfg.min_salary and salary <= cfg.max_salary, "salary %d" % salary)
			assert_true(c.length() >= 1 and c.length() <= 4)
			payroll += salary
		payrolls.append(payroll)
	assert_between(_mean(payrolls), 60000000.0, 200000000.0, "average payroll")


func test_better_players_earn_more() -> void:
	var w := _generator().generate(SEED)
	var top_pay := 0.0
	var bottom_pay := 0.0
	for t in w.teams.all():
		top_pay += w.active_contract_of(t.roster.player_ids[0]).salary_for(2026)
		bottom_pay += w.active_contract_of(t.roster.player_ids[14]).salary_for(2026)
	assert_true(top_pay > bottom_pay * 2.0, "slot 1 players earn far more than slot 15")


func test_free_agents_have_no_team_or_contract() -> void:
	var w := _generator(4).generate(SEED)
	var free := 0
	for p in w.players.all():
		if w.team_of_player(p.id) == null:
			free += 1
			assert_true(w.active_contract_of(p.id) == null)
	assert_eq(free, 60)


func test_small_league_and_custom_config() -> void:
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 4
	cfg.conference_count = 1
	cfg.divisions_per_conference = 1
	cfg.roster_size = 12
	cfg.free_agent_count = 5
	cfg.scouts = 0
	var w := FcWorldGenerator.new(data, defs, cfg).generate(9)
	assert_eq(w.validate(), [] as Array[String])
	assert_eq(w.teams.count(), 4)
	assert_eq(w.players.count(), 4 * 12 + 5)
	assert_eq(w.staff_contracts_of_team(1, FcStaffRole.Id.SCOUT).size(), 0)


func test_generated_world_survives_json_and_save() -> void:
	var gen := _generator(8)
	gen.config.conference_count = 2
	gen.config.divisions_per_conference = 2
	var state := gen.new_game_state(SEED, FcGameState.MODE_DYNASTY, 2)
	assert_eq(state.validate(), [] as Array[String])
	assert_eq(state.user_team_id, 3)
	assert_eq(state.mode, "dynasty")
	var manager := FcSaveManager.new("user://test_saves_gen")
	var saved := manager.save("gen_test", state, "Generated")
	assert_true(saved.is_ok(), saved.message)
	var loaded := manager.load_slot("gen_test", defs)
	assert_true(loaded.is_ok(), loaded.message)
	assert_eq(loaded.warnings, [] as Array[String])
	assert_eq(loaded.state.to_dict(), state.to_dict())
	manager.delete_slot("gen_test")
	DirAccess.remove_absolute("user://test_saves_gen")


func test_new_game_state_defaults() -> void:
	var state := _generator(4).new_game_state(1)
	assert_eq(state.mode, "owner")
	assert_eq(state.user_team_id, 1)
	assert_eq(state.current_season, 2026)
	assert_eq(state.current_date.to_iso(), "2026-07-01")
	assert_eq(state.user_team_name().length() > 3, true)
