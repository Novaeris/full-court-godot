extends FcTestCase
## League structure options, season rules, playoff formats, salary cap, matchup planning.

var data: FcGenerationData
var defs: FcDefinitionSet


func before_each() -> void:
	data = FcGenerationData.load_default()
	defs = FcDefinitionSet.load_default()


func _errors_contain(errors: Array[String], text: String) -> bool:
	for e in errors:
		if text in e:
			return true
	return false


func _league(conferences: int, divisions: int, teams: int) -> FcLeague:
	return FcLeague.make_even(1, "Test", conferences, divisions, teams)


func _cap(preset: String = "soft_cap_with_hard_limit") -> FcCapRules:
	return FcCapRules.from_preset(preset, 140000000, FcCapRules.load_presets())


# --- which sizes and layouts make sense -----------------------------------

func test_valid_structures_are_always_even() -> void:
	for n in range(2, 65):
		for s in FcLeagueStructure.valid_structures(n):
			assert_eq(s["conferences"] * s["divisions_per_conference"] * s["teams_per_division"], n, "%d teams" % n)
			assert_true(s["teams_per_division"] <= 8, "division size for %d" % n)
			assert_true(s["teams_per_division"] >= 3 or (s["conferences"] == 1 and s["divisions_per_conference"] == 1), "division size for %d" % n)


func test_which_team_counts_are_possible() -> void:
	var valid := FcLeagueStructure.valid_team_counts()
	for n in [4, 8, 12, 16, 20, 24, 30, 32, 36, 40, 48, 60, 64]:
		assert_true(valid.has(n), "%d should be possible" % n)
	for n in [11, 13, 17, 19, 22, 23, 26, 29, 31, 37, 41, 43, 47, 53, 59, 61]:
		assert_true(not valid.has(n), "%d cannot be split evenly" % n)
	assert_true(FcLeagueStructure.valid_structures(65).is_empty(), "above the creation maximum")
	assert_true(FcLeagueStructure.valid_structures(3).is_empty(), "too small to play a season")
	assert_true(FcLeagueStructure.valid_structures(1).is_empty())


func test_suggested_structure_is_natural() -> void:
	var thirty := FcLeagueStructure.suggest(30)
	assert_eq([thirty["conferences"], thirty["divisions_per_conference"], thirty["teams_per_division"]], [2, 3, 5])
	var sixty_four := FcLeagueStructure.suggest(64)
	assert_eq(sixty_four["conferences"] * sixty_four["divisions_per_conference"] * sixty_four["teams_per_division"], 64)
	assert_true(FcLeagueStructure.suggest(31).is_empty())
	assert_true(FcLeagueStructure.is_valid(30, 2, 3))
	assert_true(not FcLeagueStructure.is_valid(30, 2, 4))
	assert_true(FcLeagueStructure.nearest_valid_counts(31).has(30) and FcLeagueStructure.nearest_valid_counts(31).has(32))


func test_creation_rejects_uneven_or_oversized_leagues_with_suggestions() -> void:
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 31
	var errors := cfg.validate(data)
	assert_true(_errors_contain(errors, "cannot be split into even divisions"))
	assert_true(_errors_contain(errors, "30") and _errors_contain(errors, "32"), "suggests nearby sizes")
	cfg = FcGenerationConfig.load_default(data)
	cfg.team_count = 65
	assert_true(_errors_contain(cfg.validate(data), "at most 64 teams"))
	cfg = FcGenerationConfig.load_default(data)
	cfg.team_count = 36
	assert_true(_errors_contain(cfg.validate(data), "cannot be split into 2 conferences x 3 divisions") == false, "36 = 2x3x6 is fine")
	cfg.conference_count = 4
	cfg.divisions_per_conference = 4
	assert_true(_errors_contain(cfg.validate(data), "Options:"), "offers working layouts")


func test_expansion_headroom() -> void:
	assert_eq(FcLeagueStructure.MAX_TEAMS_AT_CREATION, 64)
	assert_eq(FcLeagueStructure.MAX_TEAMS_IN_SAVE, 64, "expansion stops at 64 (D-031)")
	assert_true(data.world["nicknames"].size() >= FcLeagueStructure.MAX_TEAMS_IN_SAVE, "enough names to expand")
	assert_true(data.world["cities"].size() >= FcLeagueStructure.MAX_TEAMS_IN_SAVE, "enough cities to expand")


# --- season rules: does "2-3 / 1-2 / 1-2" work? ---------------------------

func test_games_per_team_arithmetic() -> void:
	# 30 teams, 2 conferences x 3 divisions of 5: 4 division, 10 conference, 15 other-conference opponents
	var l := _league(2, 3, 30)
	var r := FcSeasonRules.new()
	r.games_per_division_opponent = 3
	r.games_per_conference_opponent = 2
	r.games_per_other_conference_opponent = 1
	assert_eq(r.games_for_team(l, 1), 4 * 3 + 10 * 2 + 15 * 1)
	assert_eq(r.games_per_team(l), 47)
	r.games_per_division_opponent = 2
	r.games_per_conference_opponent = 1
	assert_eq(r.games_per_team(l), 4 * 2 + 10 * 1 + 15 * 1, "minimum of the recommended ranges")
	r.games_per_division_opponent = 3
	r.games_per_conference_opponent = 2
	r.games_per_other_conference_opponent = 2
	assert_eq(r.games_per_team(l), 12 + 20 + 30, "maximum of the recommended ranges")


func test_recommended_ranges_give_season_lengths_by_league_size() -> void:
	var low := FcSeasonRules.new()
	low.games_per_division_opponent = 2
	low.games_per_conference_opponent = 1
	low.games_per_other_conference_opponent = 1
	var high := FcSeasonRules.new()
	high.games_per_division_opponent = 3
	high.games_per_conference_opponent = 2
	high.games_per_other_conference_opponent = 2
	var sixteen := _league(2, 2, 16)
	assert_eq([low.games_per_team(sixteen), high.games_per_team(sixteen)], [3 * 2 + 4 * 1 + 8 * 1, 3 * 3 + 4 * 2 + 8 * 2])
	var sixty_four := _league(2, 4, 64)
	assert_eq(low.games_per_team(sixty_four), 7 * 2 + 24 + 32)
	assert_eq(high.games_per_team(sixty_four), 7 * 3 + 24 * 2 + 32 * 2)
	assert_true(not high.validate(sixty_four).is_empty(), "133 games per team is rejected as too long")


func test_season_rule_bounds_and_advice() -> void:
	var l := _league(2, 3, 30)
	var r := FcSeasonRules.new()
	r.games_per_division_opponent = 9
	r.games_per_conference_opponent = 0
	assert_true(r.validate(l).size() >= 2)
	var good := FcSeasonRules.new()
	assert_eq(good.validate(l), [] as Array[String])
	good.games_per_division_opponent = 4
	assert_true(not good.advice(l).is_empty(), "4 is outside the recommended 2-3")


func test_suggest_season_for_many_sizes() -> void:
	for n in FcLeagueStructure.valid_team_counts():
		var s := FcLeagueStructure.suggest(n)
		var l := _league(s["conferences"], s["divisions_per_conference"], n)
		var rules := FcSeasonRules.suggest(l, 82)
		assert_eq(rules.validate(l), [] as Array[String], "%d teams" % n)
		var games := rules.games_per_team(l)
		assert_true(games >= 10 and games <= 120, "%d teams -> %d games" % [n, games])
		if l.conferences.size() == 1:
			assert_eq(rules.games_per_other_conference_opponent, 0, "no other conference")


func test_suggest_prefers_recommended_ranges_and_target() -> void:
	var sixty_four := _league(2, 4, 64)
	var r := FcSeasonRules.suggest(sixty_four, 80)
	assert_between(r.games_per_team(sixty_four), 70.0, 90.0, "64-team season")
	assert_eq(r.games_per_team(sixty_four) % 2, 0, "ends on an even number")
	var thirty := _league(2, 3, 30)
	var t := FcSeasonRules.suggest(thirty, 80)
	assert_eq(t.games_per_team(thirty), 80, "30 teams needs a wider division value to reach 80")
	var recommended_only := FcSeasonRules.suggest(thirty, 62)
	assert_true(recommended_only.advice(thirty).is_empty(), "a 62-game target is exactly 3/2/2, inside the recommended ranges")


# --- the matchup planner: proof that the rules can be played fairly --------

func test_matchup_plan_counts_and_home_away_fairness() -> void:
	for n in [4, 6, 8, 12, 16, 20, 24, 30, 36, 40, 48, 60, 64]:
		var s := FcLeagueStructure.suggest(n)
		var league := _league(s["conferences"], s["divisions_per_conference"], n)
		for gd in [2, 3]:
			for gc in [1, 2]:
				for go in [1, 2]:
					var r := FcSeasonRules.new()
					r.games_per_division_opponent = gd
					r.games_per_conference_opponent = gc
					r.games_per_other_conference_opponent = go if league.conferences.size() > 1 else 0
					var plan := FcMatchupPlanner.plan(league, r)
					assert_true(plan.max_home_away_gap() <= 1, "%d teams %d/%d/%d: gap %d" % [n, gd, gc, go, plan.max_home_away_gap()])
					var expected := r.games_per_team(league)
					var span := plan.games_per_team_range()
					assert_eq([span.x, span.y], [expected, expected], "%d teams games per team" % n)
					assert_eq(plan.total_games() * 2, expected * n, "each game counted once")


func test_matchup_plan_pair_details() -> void:
	var league := _league(2, 3, 30)
	var r := FcSeasonRules.new()
	r.games_per_division_opponent = 3
	r.games_per_conference_opponent = 2
	r.games_per_other_conference_opponent = 1
	var plan := FcMatchupPlanner.plan(league, r)
	assert_eq(plan.pairs.size(), 435, "30 teams make 435 pairs")
	for p in plan.pairs:
		assert_eq(int(p["a_home"]) + int(p["b_home"]), int(p["games"]))
		if int(p["games"]) % 2 == 0:
			assert_eq(p["a_home"], p["b_home"], "even series split evenly")
		else:
			assert_eq(absi(int(p["a_home"]) - int(p["b_home"])), 1)
	for t in league.all_team_ids():
		assert_eq(plan.games_of(t), 47)
		assert_true(absi(plan.home_games_of(t) - plan.away_games_of(t)) <= 1)


func test_matchup_plan_on_uneven_league_after_expansion() -> void:
	var league := _league(2, 2, 16)
	league.add_team(1, 100)
	var r := FcSeasonRules.new()
	var plan := FcMatchupPlanner.plan(league, r)
	assert_true(plan.max_home_away_gap() <= 1)
	assert_true(plan.games_of(100) > 0)
	var span := plan.games_per_team_range()
	assert_true(span.x != span.y, "uneven structure gives uneven schedules; expansion must rebalance")


# --- playoffs ---------------------------------------------------------------

func test_playoff_suggestion_is_valid_for_every_size() -> void:
	for n in FcLeagueStructure.valid_team_counts():
		var s := FcLeagueStructure.suggest(n)
		var l := _league(s["conferences"], s["divisions_per_conference"], n)
		var p := FcPlayoffRules.suggest(l)
		assert_eq(p.validate(l), [] as Array[String], "%d teams: %s" % [n, str(p.to_dict())])
		assert_true(p.team_count >= l.all_divisions().size(), "every division leader can qualify")
		assert_true(p.team_count <= n)


func test_playoff_round_math() -> void:
	var l := _league(2, 3, 30)
	var p := FcPlayoffRules.new()
	p.team_count = 16
	p.series_lengths = [5, 7, 7, 7] as Array[int]
	assert_eq(p.round_count(l), 4, "8 per conference: 3 rounds, then a final")
	assert_eq(p.bracket_size(l), 8)
	assert_eq(p.byes_per_bracket(l), 0)
	assert_eq(p.validate(l), [] as Array[String])
	p.bracket = "league"
	assert_eq(p.round_count(l), 4, "one bracket of 16")
	p.team_count = 12
	p.bracket = "conference"
	p.series_lengths = [3, 5, 7, 7] as Array[int]
	assert_eq(p.bracket_size(l), 6)
	assert_eq(p.byes_per_bracket(l), 2, "6 teams -> 2 byes in an 8-slot bracket")
	assert_eq(p.round_count(l), 4)
	p.team_count = 6
	assert_eq(p.round_count(l), 3, "3 per conference: 2 rounds, then a final")


func test_playoff_validation() -> void:
	var l := _league(2, 3, 30)
	var p := FcPlayoffRules.new()
	p.team_count = 16
	p.series_lengths = [5, 7, 7] as Array[int]
	assert_true(_errors_contain(p.validate(l), "4 rounds but 3 series lengths"))
	p.series_lengths = [5, 7, 7, 4] as Array[int]
	assert_true(_errors_contain(p.validate(l), "best of 1, 3, 5 or 7"))
	p.team_count = 15
	p.series_lengths = [5, 7, 7, 7] as Array[int]
	assert_true(_errors_contain(p.validate(l), "split evenly across 2 conferences"))
	p.team_count = 4
	p.series_lengths = [7, 7] as Array[int]
	assert_true(_errors_contain(p.validate(l), "every division leader"), "6 divisions need 6+ spots")
	p.qualification = "seeding"
	assert_eq(p.validate(l), [] as Array[String], "seeding has no division guarantee")
	p.team_count = 40
	assert_true(_errors_contain(p.validate(l), "more than the league's"))
	p.qualification = "bogus"
	assert_true(not p.validate(l).is_empty())
	var single := FcPlayoffRules.new()
	single.team_count = 1
	assert_true(_errors_contain(single.validate(l), "at least 2"))


func test_college_style_seeding_with_one_bracket() -> void:
	var l := _league(2, 3, 30)
	var p := FcPlayoffRules.new()
	p.qualification = "seeding"
	p.bracket = "league"
	p.team_count = 8
	p.series_lengths = [1, 3, 5] as Array[int]
	assert_eq(p.validate(l), [] as Array[String])
	assert_eq(p.round_count(l), 3)
	var text := "\n".join(p.describe(l))
	assert_true("best records qualify" in text and "one bracket seeded 1-8" in text and "best of 1" in text, text)


func test_playoff_round_trip_and_describe() -> void:
	var l := _league(2, 3, 30)
	var p := FcPlayoffRules.suggest(l)
	assert_eq(FcPlayoffRules.from_dict(JSON.parse_string(JSON.stringify(p.to_dict()))).to_dict(), p.to_dict())
	assert_true("division leaders qualify automatically" in "\n".join(p.describe(l)))


# --- salary cap -------------------------------------------------------------

func test_presets_are_coherent() -> void:
	for name in ["soft_cap_with_hard_limit", "hard_cap", "no_cap"]:
		var cap := _cap(name)
		assert_true(cap != null, name)
		assert_eq(cap.validate(), [] as Array[String], name)
	assert_true(FcCapRules.from_preset("missing", 1000, FcCapRules.load_presets()) == null)
	var soft := _cap()
	assert_eq(soft.salary_cap, 140000000)
	assert_eq(soft.luxury_tax_line, 168000000)
	assert_eq(soft.hard_limit, 189000000)
	assert_eq(soft.max_player_salary, 42000000)
	assert_true(soft.min_player_salary > 1000000 and soft.min_player_salary < 1300000)
	assert_eq(_cap("hard_cap").effective_limit(), 140000000)
	assert_eq(_cap("no_cap").effective_limit(), 0)


func test_payroll_tiers_tax_and_space() -> void:
	var cap := _cap()
	assert_eq(cap.payroll_tier(100000000), "under_minimum")
	assert_eq(cap.payroll_tier(130000000), "under_cap")
	assert_eq(cap.payroll_tier(150000000), "over_cap")
	assert_eq(cap.payroll_tier(172000000), "over_tax")
	assert_eq(cap.payroll_tier(180000000), "over_restriction")
	assert_eq(cap.payroll_tier(190000000), "over_limit")
	assert_eq(cap.cap_space(130000000), 10000000)
	assert_eq(cap.cap_space(150000000), 0)
	assert_eq(cap.luxury_tax(160000000), 0)
	assert_eq(cap.luxury_tax(178000000), 15000000, "$10M over the line at 150%")
	assert_eq(cap.minimum_payroll_shortfall(100000000), 19000000)
	assert_eq(cap.minimum_payroll_shortfall(130000000), 0)


func test_soft_cap_signing_rules() -> void:
	var cap := _cap()
	# cap space: only under the cap
	assert_true(cap.check_signing(120000000, 15000000, FcCapRules.SigningKind.CAP_SPACE).allowed)
	assert_true(not cap.check_signing(130000000, 15000000, FcCapRules.SigningKind.CAP_SPACE).allowed, "would pass the cap")
	# own players can be re-signed over the cap, but never past the hard limit
	assert_true(cap.check_signing(160000000, 20000000, FcCapRules.SigningKind.OWN_PLAYER).allowed)
	var blocked := cap.check_signing(175000000, 20000000, FcCapRules.SigningKind.OWN_PLAYER)
	assert_true(not blocked.allowed and "hard limit" in blocked.reason, blocked.reason)
	# mid-level exception: capped amount, still under the limit
	assert_true(cap.check_signing(150000000, 12000000, FcCapRules.SigningKind.MID_LEVEL).allowed)
	assert_true(not cap.check_signing(150000000, 13000000, FcCapRules.SigningKind.MID_LEVEL).allowed, "above the exception size")
	assert_true(not cap.check_signing(180000000, 12000000, FcCapRules.SigningKind.MID_LEVEL).allowed, "limit")
	# minimum contracts
	assert_true(cap.check_signing(150000000, cap.min_player_salary, FcCapRules.SigningKind.MINIMUM).allowed)
	assert_true(not cap.check_signing(150000000, cap.min_player_salary + 1000000, FcCapRules.SigningKind.MINIMUM).allowed)
	assert_true(not cap.check_signing(189000000, cap.min_player_salary, FcCapRules.SigningKind.MINIMUM).allowed, "even minimum deals cannot pass the hard limit")
	# salary bounds
	assert_true(not cap.check_signing(100000000, cap.max_player_salary + 10000, FcCapRules.SigningKind.CAP_SPACE).allowed)
	assert_true(not cap.check_signing(100000000, cap.min_player_salary - 10000, FcCapRules.SigningKind.CAP_SPACE).allowed)
	# rookies
	assert_true(cap.check_signing(150000000, 5000000, FcCapRules.SigningKind.ROOKIE).allowed)


func test_hard_cap_has_no_exceptions() -> void:
	var cap := _cap("hard_cap")
	assert_true(cap.check_signing(120000000, 15000000, FcCapRules.SigningKind.CAP_SPACE).allowed)
	assert_true(not cap.check_signing(130000000, 15000000, FcCapRules.SigningKind.CAP_SPACE).allowed)
	assert_true(not cap.check_signing(130000000, 15000000, FcCapRules.SigningKind.OWN_PLAYER).allowed)
	assert_true(not cap.check_signing(139000000, cap.min_player_salary, FcCapRules.SigningKind.MINIMUM).allowed)
	assert_true(not cap.check_signing(100000000, 5000000, FcCapRules.SigningKind.MID_LEVEL).allowed)
	assert_eq(cap.luxury_tax(150000000), 0)


func test_no_cap_league_only_limits_salaries() -> void:
	var cap := _cap("no_cap")
	assert_true(cap.check_signing(400000000, 30000000, FcCapRules.SigningKind.CAP_SPACE).allowed, "anyone can spend")
	assert_true(not cap.check_signing(400000000, cap.max_player_salary + 10000, FcCapRules.SigningKind.CAP_SPACE).allowed)
	assert_true(cap.luxury_tax(300000000) > 0, "but heavy spending is taxed")


func test_trade_rules() -> void:
	var cap := _cap()
	assert_true(cap.check_trade(130000000, 10000000, 0).allowed, "stays under the cap")
	assert_true(cap.check_trade(150000000, 10000000, 9000000).allowed, "over the cap but salaries match")
	assert_true(not cap.check_trade(150000000, 30000000, 10000000).allowed, "incoming is too large")
	assert_true(cap.check_trade(150000000, 5000000, 20000000).allowed, "shedding salary is fine")
	assert_true(not cap.check_trade(185000000, 20000000, 10000000).allowed, "hard limit")
	assert_true(cap.check_trade(195000000, 5000000, 10000000).allowed, "a team over the limit may reduce payroll")
	assert_true(not _cap("hard_cap").check_trade(139000000, 8000000, 5000000).allowed)
	assert_true(_cap("no_cap").check_trade(300000000, 90000000, 1000000).allowed)


func test_contract_rules() -> void:
	var cap := _cap()
	var c := FcTestData.contract(1, 1, 1)
	c.years.clear()
	c.years.append(FcContractYear.new(2026, 10000000))
	c.years.append(FcContractYear.new(2027, 10800000))
	assert_eq(cap.validate_contract(c), [] as Array[String])
	c.years[1].salary = 12000000
	assert_true(_errors_contain(cap.validate_contract(c), "raise"))
	c.years[1].salary = 10500000
	c.years.append(FcContractYear.new(2028, 10500000))
	c.years.append(FcContractYear.new(2029, 10500000))
	c.years.append(FcContractYear.new(2030, 10500000))
	c.years.append(FcContractYear.new(2031, 10500000))
	assert_true(_errors_contain(cap.validate_contract(c), "at most 5 years"))
	var rich := FcTestData.contract(2, 1, 1)
	rich.years[0].salary = 60000000
	rich.years[1].salary = 60000000
	assert_true(_errors_contain(cap.validate_contract(rich), "outside"))


func test_cap_validation_catches_nonsense() -> void:
	var cap := _cap()
	cap.hard_limit = 100000000
	cap.luxury_tax_line = 120000000
	cap.max_player_salary = 200000000
	cap.minimum_payroll = 150000000
	cap.max_contract_years = 20
	cap.cap_type = "soft"
	assert_true(cap.validate().size() >= 4, str(cap.validate()))
	cap.cap_type = "weird"
	assert_true(not cap.validate().is_empty())
	var hard := _cap("hard_cap")
	hard.luxury_tax_line = 150000000
	assert_true(_errors_contain(hard.validate(), "hard cap has no luxury tax"))


# --- full rules entity, world integrity, generated leagues ------------------

func test_rules_round_trip() -> void:
	var l := _league(2, 3, 30)
	var r := FcLeagueRules.new(5)
	r.league_id = 1
	r.cap = _cap()
	r.season = FcSeasonRules.suggest(l)
	r.playoffs = FcPlayoffRules.suggest(l)
	assert_eq(r.validate(l), [] as Array[String])
	var copy := FcLeagueRules.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	assert_eq(copy.to_dict(), r.to_dict())
	r.roster_min = 20
	assert_true(not r.validate(l).is_empty(), "min above max")


func test_generated_league_follows_its_rules() -> void:
	var cfg := FcGenerationConfig.load_default(data)
	var w := FcWorldGenerator.new(data, defs, cfg).generate(77)
	assert_eq(w.validate(cfg.start_season), [] as Array[String])
	var rules := w.rules_of_league(1)
	assert_true(rules != null)
	var limit := rules.cap.effective_limit()
	var over_tax := 0
	var over_cap := 0
	for t in w.teams.all():
		var payroll := w.payroll_of_team(t.id, cfg.start_season)
		assert_true(payroll <= limit, "team %d payroll %d" % [t.id, payroll])
		assert_true(payroll >= rules.cap.minimum_payroll * 0.97, "team %d is not below the minimum" % t.id)
		if payroll > rules.cap.luxury_tax_line:
			over_tax += 1
		if payroll > rules.cap.salary_cap:
			over_cap += 1
		assert_true(t.roster.size() <= rules.roster_max)
		assert_eq(w.rules_of_team(t.id).league_id, 1)
	assert_true(over_cap > 0 and over_cap < 30, "some teams are over the cap, some under (%d)" % over_cap)
	assert_true(over_tax < 15, "tax payers are the minority (%d)" % over_tax)
	for c in w.contracts.all():
		assert_eq(rules.cap.validate_contract(c), [] as Array[String])


func test_world_flags_rule_violations() -> void:
	var cfg := FcGenerationConfig.load_default(data)
	var w := FcWorldGenerator.new(data, defs, cfg).generate(78)
	var rules := w.rules_of_league(1)
	var team: FcTeam = w.teams.get_by_id(1)
	var contract := w.active_contract_of(team.roster.player_ids[0])
	contract.years[0].salary = rules.cap.max_player_salary + 5000000
	contract.years[0].guaranteed = contract.years[0].salary
	assert_true(_errors_contain(w.validate(cfg.start_season), "breaks league rules"))
	contract.years[0].salary = rules.cap.max_player_salary
	contract.years[0].guaranteed = contract.years[0].salary
	for pid in team.roster.player_ids:
		var c := w.active_contract_of(pid)
		for y in c.years:
			y.salary = rules.cap.max_player_salary
			y.guaranteed = y.salary
	assert_true(_errors_contain(w.validate(cfg.start_season), "exceeds the league limit"))
	assert_true(not _errors_contain(w.validate(), "exceeds the league limit"), "payroll check needs a season")


func test_each_cap_preset_generates_a_valid_league() -> void:
	for preset in ["soft_cap_with_hard_limit", "hard_cap", "no_cap"]:
		var cfg := FcGenerationConfig.load_default(data)
		cfg.cap_preset = preset
		cfg.team_count = 16
		cfg.conference_count = 2
		cfg.divisions_per_conference = 2
		assert_eq(cfg.validate(data), [] as Array[String], preset)
		var w := FcWorldGenerator.new(data, defs, cfg).generate(5)
		assert_eq(w.validate(cfg.start_season), [] as Array[String], preset)
		var cap := w.rules_of_league(1).cap
		assert_eq(cap.cap_type, {"soft_cap_with_hard_limit": "soft", "hard_cap": "hard", "no_cap": "none"}[preset])


func test_cap_size_is_configurable() -> void:
	var cfg := FcGenerationConfig.load_default(data)
	cfg.salary_cap = 100000000
	cfg.team_count = 12
	cfg.conference_count = 2
	cfg.divisions_per_conference = 2
	var w := FcWorldGenerator.new(data, defs, cfg).generate(9)
	assert_eq(w.validate(cfg.start_season), [] as Array[String])
	assert_eq(w.rules_of_league(1).cap.salary_cap, 100000000)
	assert_eq(w.rules_of_league(1).cap.max_player_salary, 30000000)


func test_season_and_playoff_choices_flow_into_the_league() -> void:
	var cfg := FcGenerationConfig.load_default(data)
	cfg.auto_season = false
	cfg.games_per_division_opponent = 2
	cfg.games_per_conference_opponent = 1
	cfg.games_per_other_conference_opponent = 1
	cfg.auto_playoffs = false
	cfg.playoff_qualification = "seeding"
	cfg.playoff_bracket = "league"
	cfg.playoff_team_count = 8
	cfg.playoff_series = [3, 5, 7] as Array[int]
	assert_eq(cfg.validate(data), [] as Array[String])
	var w := FcWorldGenerator.new(data, defs, cfg).generate(3)
	var r := w.rules_of_league(1)
	assert_eq(r.season.games_per_team(w.leagues.get_by_id(1)), 4 * 2 + 10 + 15)
	assert_eq(r.playoffs.qualification, "seeding")
	assert_eq(r.playoffs.team_count, 8)
	assert_eq(r.playoffs.series_lengths, [3, 5, 7] as Array[int])
	cfg.playoff_series = [3, 5] as Array[int]
	assert_true(_errors_contain(cfg.validate(data), "3 rounds but 2 series lengths"))


func test_rules_survive_save_and_load() -> void:
	var cfg := FcGenerationConfig.load_default(data)
	cfg.team_count = 12
	cfg.conference_count = 2
	cfg.divisions_per_conference = 2
	var state := FcWorldGenerator.new(data, defs, cfg).new_game_state(11)
	var manager := FcSaveManager.new("user://test_saves_rules")
	assert_true(manager.save("rules_test", state).is_ok())
	var loaded := manager.load_slot("rules_test", defs)
	assert_true(loaded.is_ok(), loaded.message)
	assert_eq(loaded.warnings, [] as Array[String])
	assert_eq(loaded.state.to_dict(), state.to_dict())
	assert_eq(loaded.state.world.rules_of_league(1).cap.salary_cap, 140000000)
	manager.delete_slot("rules_test")
	DirAccess.remove_absolute("user://test_saves_rules")


# --- naming, nationality, sensitive places ----------------------------------

func test_users_choose_names_and_the_generator_fills_the_rest() -> void:
	var cfg := FcGenerationConfig.load_default(data)
	cfg.city_keys = ["london", "paris", "madrid", "rome"] as Array[String]
	cfg.conference_count = 1
	cfg.divisions_per_conference = 1
	cfg.team_nicknames = {"london": "The Royal Monarchs of the River Thames"}
	cfg.team_abbreviations = {"paris": "PAR", "rome": "ROM"}
	assert_true(_errors_contain(cfg.validate(data), "longer than"), "names have a length limit")
	cfg.team_nicknames = {"london": "Thames Kings", "madrid": "Matadors"}
	assert_eq(cfg.validate(data), [] as Array[String])
	var w := FcWorldGenerator.new(data, defs, cfg).generate(1)
	assert_eq(w.teams.get_by_id(1).identity.nickname, "Thames Kings")
	assert_eq(w.teams.get_by_id(3).identity.nickname, "Matadors")
	assert_true(w.teams.get_by_id(2).identity.nickname != "", "generated name for Paris")
	assert_eq(w.teams.get_by_id(2).identity.abbreviation, "PAR")
	assert_eq(w.teams.get_by_id(4).identity.abbreviation, "ROM")
	assert_true(w.teams.get_by_id(1).identity.abbreviation.length() >= 2, "generated abbreviation")


func test_team_name_validation() -> void:
	var cfg := FcGenerationConfig.load_default(data)
	cfg.city_keys = ["london", "paris", "madrid", "rome"] as Array[String]
	cfg.conference_count = 1
	cfg.divisions_per_conference = 1
	cfg.team_nicknames = {"london": "Rebels", "paris": "rebels", "madrid": "  "}
	var errors := cfg.validate(data)
	assert_true(_errors_contain(errors, "used by two teams"))
	assert_true(_errors_contain(errors, "is empty"))
	cfg.team_nicknames = {}
	cfg.team_abbreviations = {"london": "lon", "paris": "PAR", "rome": "PAR"}
	errors = cfg.validate(data)
	assert_true(_errors_contain(errors, "2-4 capital letters"))
	assert_true(_errors_contain(errors, "used by two teams"))


func test_name_generator_button() -> void:
	var g := FcNameGenerator.new(data)
	var rng := FcRng.new(8)
	var taken := {}
	var seen := {}
	for i in 100:
		var nick := g.random_team_nickname(rng, taken)
		assert_true(nick != "" and not seen.has(nick), "unique %s" % nick)
		seen[nick] = true
	assert_eq(g.random_team_nickname(rng, taken), "", "pool exhausted")


func test_default_nationality_is_65_percent_local() -> void:
	var cfg := FcGenerationConfig.load_default(data)
	assert_eq(cfg.home_country_share, 0.65)
	cfg.team_count = 30
	var w := FcWorldGenerator.new(data, defs, cfg).generate(2)
	var local := 0
	var total := 0
	for t in w.teams.all():
		var country: String = w.cities.get_by_id(t.city_id).country
		for pid in t.roster.player_ids:
			total += 1
			if w.players.get_by_id(pid).identity.country == country:
				local += 1
	assert_between(float(local) / total, 0.62, 0.82, "65% plus chance matches from the global pool")


func test_politically_sensitive_places_use_self_identified_names() -> void:
	var by_key := {}
	for c in data.world["cities"]:
		by_key[c["key"]] = c
	var names := FcNameGenerator.new(data)
	var expected := {
		"moscow": "Russia", "saint_petersburg": "Russia", "kyiv": "Ukraine", "minsk": "Belarus",
		"tel_aviv": "Israel", "tehran": "Iran", "riyadh": "Saudi Arabia", "doha": "Qatar",
		"taipei": "Taiwan", "hong_kong": "Hong Kong", "pristina": "Kosovo", "istanbul": "Türkiye",
		"san_juan": "Puerto Rico", "sarajevo": "Bosnia and Herzegovina", "abidjan": "Côte d'Ivoire",
		"kinshasa": "Democratic Republic of the Congo", "prague": "Czechia", "dubai": "United Arab Emirates",
	}
	for key in expected:
		assert_true(by_key.has(key), "%s is available" % key)
		assert_eq(names.country_name(by_key[key]["country"]), expected[key], key)
	assert_eq(by_key["dubai"]["area"], "middle_east")
	assert_true(data.world["areas"].has("middle_east"))
	var rng := FcRng.new(1)
	for pool_country in ["russia", "israel", "iran", "georgia", "ukraine"]:
		var n := names.generate(rng, pool_country)
		assert_true(n["first"] != "" and n["last"] != "", pool_country)


func test_choosing_the_middle_east_and_russia() -> void:
	var cfg := FcGenerationConfig.load_default(data)
	cfg.areas = ["middle_east"] as Array[String]
	cfg.team_count = 5
	cfg.conference_count = 1
	cfg.divisions_per_conference = 1
	assert_eq(cfg.validate(data), [] as Array[String])
	var w := FcWorldGenerator.new(data, defs, cfg).generate(4)
	var countries := {}
	for c in w.cities.all():
		assert_eq(c.area, "middle_east")
		countries[c.country] = true
	assert_true(countries.has("Israel") or countries.has("Iran") or countries.has("Qatar"))
	cfg = FcGenerationConfig.load_default(data)
	cfg.city_keys = ["moscow", "saint_petersburg", "kyiv", "minsk"] as Array[String]
	cfg.conference_count = 1
	cfg.divisions_per_conference = 1
	var w2 := FcWorldGenerator.new(data, defs, cfg).generate(4)
	assert_eq(w2.validate(), [] as Array[String])
	assert_eq(w2.cities.get_by_id(1).country, "Russia")
