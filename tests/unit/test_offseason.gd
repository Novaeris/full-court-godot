extends FcTestCase
## Offseason: aging, retirement, expiry, re-signing, the draft, free agency, legal rosters,
## and several seasons in a row staying healthy.

static var _run: Dictionary = {}


func _build_world(seed_value: int = 88) -> FcWorld:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.roster_min = 13
	cfg.free_agent_count = 20
	cfg.assistant_coaches = 1
	cfg.scouts = 0
	return FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg).generate(seed_value)


func _top_rating(world: FcWorld, ratings: FcPlayerRatings) -> float:
	var total := 0.0
	var count := 0
	for t in world.teams.all():
		var overalls: Array = []
		for pid in t.roster.player_ids:
			overalls.append(ratings.overall(world.players.get_by_id(pid)))
		overalls.sort()
		overalls.reverse()
		for v in overalls.slice(0, 8):
			total += v
			count += 1
	return total / count


## Plays 3 full seasons with an offseason after each (about 15 s), once, shared by the tests.
func _simulated() -> Dictionary:
	if not _run.is_empty():
		return _run
	var world := _build_world()
	var ratings := FcPlayerRatings.load_default()
	var rng := FcRng.new(21)
	var seasons: Array[FcSeason] = []
	var reports: Array = []
	var problems: Array = []
	var start_talent := _top_rating(world, ratings)
	var year := 2026
	for i in 3:
		var engine := FcSeasonEngine.for_league(world, 1)
		var season := engine.start_season(1, year, FcDate.new(year, 10, 20), rng.fork("season%d" % i))
		engine.play_full_season(season, rng.fork("play%d" % i))
		seasons.append(season)
		var report := FcOffseason.new(world).run(1, season, rng.fork("off%d" % i))
		reports.append(report)
		problems.append(world.validate(year + 1))
		year += 1
	_run = {"world": world, "seasons": seasons, "reports": reports, "problems": problems,
		"start_talent": start_talent, "end_talent": _top_rating(world, ratings), "year": year}
	return _run


func test_world_stays_valid_through_several_seasons() -> void:
	var r := _simulated()
	for i in r["problems"].size():
		assert_eq(r["problems"][i], [] as Array[String], "after offseason %d" % (i + 1))


func test_rosters_are_always_legal() -> void:
	var r := _simulated()
	var world: FcWorld = r["world"]
	var rules := world.rules_of_league(1)
	for t in world.teams.all():
		assert_between(t.roster.size(), rules.roster_min, rules.roster_max, "team %d roster size" % t.id)
		for pid in t.roster.player_ids:
			var p: FcPlayer = world.players.get_by_id(pid)
			assert_true(p.status == FcPlayer.Status.ACTIVE, "only active players are on rosters")
			var c := world.active_contract_of(pid)
			assert_true(c != null and c.team_id == t.id, "every rostered player has a contract with his team")
			assert_true(c.is_in_force_in(r["year"]), "and it covers the new season")
		assert_true(world.payroll_of_team(t.id, r["year"]) <= rules.cap.effective_limit(), "payroll within the hard limit")
		assert_true(world.staff_in_role(t.id, FcStaffRole.Id.HEAD_COACH) != null, "staff untouched")


func test_players_age_retire_and_the_league_stays_young_enough() -> void:
	var r := _simulated()
	var world: FcWorld = r["world"]
	var retired := 0
	for p in world.players.all():
		if p.status == FcPlayer.Status.RETIRED:
			retired += 1
			assert_true(p.retired_season >= 2026 and p.retired_season <= 2028)
			assert_true(world.team_of_player(p.id) == null, "retired players are on no roster")
			assert_true(world.active_contract_of(p.id) == null, "and have no active contract")
	assert_true(retired > 0, "some players retired in three years (%d)" % retired)
	var ages := 0.0
	var n := 0
	for t in world.teams.all():
		for pid in t.roster.player_ids:
			ages += world.players.get_by_id(pid).age_on(FcDate.new(r["year"], 7, 1))
			n += 1
	assert_between(ages / n, 23.5, 30.0, "average roster age")


func test_league_talent_stays_stable() -> void:
	var r := _simulated()
	assert_between(r["end_talent"], r["start_talent"] - 7.0, r["start_talent"] + 7.0, "top-8 ratings drift (%.1f -> %.1f)" % [r["start_talent"], r["end_talent"]])


func test_reports_show_activity() -> void:
	var r := _simulated()
	for report in r["reports"]:
		assert_true(report["progressed"] > 50)
		assert_true(report["expired"] > 0, "contracts expire every year")
		assert_true(report["drafted"] == 16, "2 rounds x 8 teams")
		assert_true(report["signed"] + report["re_signed"] > 0)


func test_draft_order_and_rookie_contracts() -> void:
	var r := _simulated()
	var world: FcWorld = r["world"]
	var rules := world.rules_of_league(1)
	var season: FcSeason = r["seasons"][0]
	assert_eq(season.draft.size(), 16)
	var missed: Array[int] = []
	for row in season.final_standings:   # best record first; the season is archived by now
		if not season.playoffs.qualified(row[0]):
			missed.append(row[0])
	assert_true(season.draft[0][2] in missed.slice(maxi(0, missed.size() - rules.draft.lottery_teams)), "the first pick goes to one of the lottery teams (the worst non-playoff teams)")
	assert_eq(season.draft[0][1], 1)
	assert_eq(season.draft[8][0], 2, "second round starts after eight picks")
	var previous_salary := INF
	for row in season.draft.slice(0, 8):
		var pid: int = row[3]
		if world.active_contract_of(pid) == null and world.team_of_player(pid) == null:
			continue
		var p: FcPlayer = world.players.get_by_id(pid)
		assert_true(p.status != FcPlayer.Status.PROSPECT, "drafted prospects become players")
		var found := false
		for c in world.contracts.all():
			if c.player_id == pid and c.years[0].season == 2027:
				found = true
				assert_true(c.years[0].salary <= previous_salary, "rookie scale falls with the pick")
				previous_salary = c.years[0].salary
				assert_eq(c.years.size(), rules.cap.rookie_contract_years)
				assert_eq(c.years[rules.cap.rookie_guaranteed_years].option_type, FcContractYear.OptionType.TEAM)
		assert_true(found, "a rookie contract exists")


func test_every_drafted_player_is_a_young_prospect() -> void:
	var r := _simulated()
	var world: FcWorld = r["world"]
	var season: FcSeason = r["seasons"][0]
	for row in season.draft:
		var p: FcPlayer = world.players.get_by_id(row[3])
		var age := p.age_on(FcDate.new(2027, 7, 1))
		assert_between(age, 19.0, 23.0, "draftee age")
		assert_true(p.development.potential >= 40, "draftees have upside")


func test_market_values_and_salaries() -> void:
	var defs := FcDefinitionSet.load_default()
	var market := FcPlayerMarket.new(FcPlayerRatings.load_default())
	var cap := FcCapRules.from_preset("soft_cap_with_hard_limit", 140000000, FcCapRules.load_presets())
	var star := FcTestData.player(1, defs)
	var role := FcTestData.player(2, defs)
	for key in defs.attributes.keys():
		star.attributes.set_clamped(key, 80)
		role.attributes.set_clamped(key, 45)
	assert_true(market.value(star, 27) > market.value(role, 27))
	assert_true(market.asking_salary(star, 27, cap) > market.asking_salary(role, 27, cap) * 3)
	assert_true(market.asking_salary(star, 27, cap) <= cap.max_player_salary)
	assert_true(market.asking_salary(role, 27, cap) >= cap.min_player_salary)
	assert_true(market.value(star, 36) < market.value(star, 29), "age reduces value")
	role.development.potential = 80
	assert_true(market.value(role, 21) > market.value(role, 29), "a young high-potential player is worth more than an old equal")
	assert_eq(market.desired_years(21, cap), 5)
	assert_true(market.desired_years(35, cap) < market.desired_years(25, cap))
	var contract := FcPlayerMarket.make_contract(1, 1, 1, 2027, 4, 10000000, cap, FcDate.new(2027, 7, 1))
	assert_eq(cap.validate_contract(contract), [] as Array[String])
	assert_eq(contract.length(), 4)


func test_offseason_is_reproducible() -> void:
	var a := _build_world(5)
	var b := _build_world(5)
	var sa := FcSeasonEngine.for_league(a, 1)
	var sb := FcSeasonEngine.for_league(b, 1)
	var season_a := sa.start_season(1, 2026, FcDate.new(2026, 10, 20), FcRng.new(1))
	var season_b := sb.start_season(1, 2026, FcDate.new(2026, 10, 20), FcRng.new(1))
	sa.play_full_season(season_a, FcRng.new(2))
	sb.play_full_season(season_b, FcRng.new(2))
	FcOffseason.new(a).run(1, season_a, FcRng.new(3))
	FcOffseason.new(b).run(1, season_b, FcRng.new(3))
	assert_eq(a.to_dict(), b.to_dict())


func test_hard_cap_leagues_survive_an_offseason() -> void:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 15
	cfg.cap_preset = "hard_cap"
	var world := FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg).generate(31)
	var engine := FcSeasonEngine.for_league(world, 1)
	var rng := FcRng.new(8)
	var season := engine.start_season(1, 2026, FcDate.new(2026, 10, 20), rng)
	engine.play_full_season(season, rng)
	FcOffseason.new(world).run(1, season, rng)
	assert_eq(world.validate(2027), [] as Array[String])
	var rules := world.rules_of_league(1)
	for t in world.teams.all():
		assert_true(world.payroll_of_team(t.id, 2027) <= rules.cap.salary_cap, "a hard cap is never exceeded")


func test_every_team_keeps_its_staff_through_the_years() -> void:
	var r := _simulated()
	var world: FcWorld = r["world"]
	for t in world.teams.all():
		assert_true(world.staff_in_role(t.id, FcStaffRole.Id.GENERAL_MANAGER) != null, "team %d has a GM" % t.id)
		assert_true(world.staff_in_role(t.id, FcStaffRole.Id.HEAD_COACH) != null, "team %d has a head coach" % t.id)
		assert_eq(world.staff_contracts_of_team(t.id, FcStaffRole.Id.ASSISTANT_COACH).size(), 1, "the assistant coach slot is kept")
		for sc in world.staff_contracts_of_team(t.id):
			assert_true(sc.is_in_force_in(r["year"]), "staff contracts cover the new season")
	for report in r["reports"]:
		assert_true(report["staff_hired"] >= 0 and report.has("staff_renewed"))
	assert_true((r["reports"] as Array).any(func(rep): return rep["staff_renewed"] + rep["staff_hired"] > 0), "some staff contracts were renewed or refilled")


func test_scouts_reduce_draft_noise() -> void:
	var data := FcGenerationData.load_default()
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 8
	cfg.conference_count = 2
	cfg.divisions_per_conference = 1
	cfg.roster_size = 13
	cfg.free_agent_count = 5
	cfg.scouts = 2
	var world := FcWorldGenerator.new(data, FcDefinitionSet.load_default(), cfg).generate(90)
	var off := FcOffseason.new(world)
	var scouts := world.staff_contracts_of_team(1, FcStaffRole.Id.SCOUT)
	assert_eq(scouts.size(), 2)
	for sc in scouts:
		world.staff.get_by_id(sc.staff_id).skills.set_clamped("scouting_accuracy", 0)
	var untrained := off.draft_noise(1)
	for sc in scouts:
		world.staff.get_by_id(sc.staff_id).skills.set_clamped("scouting_accuracy", 100)
	var trained := off.draft_noise(1)
	assert_true(trained < untrained, "great scouts sharpen the view (%f < %f)" % [trained, untrained])
	assert_true(untrained - trained <= FcOffseason.SCOUT_NOISE_MAX + 0.001)
	assert_true(trained >= 0.5)
