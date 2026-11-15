extends FcTestCase
## The extra salary rules: tax sharing, repeater tax, restriction line, rookie scale,
## cornerstone extension, cap holds, sign-and-trade, no-trade clauses; plus 80-game seasons.

var data: FcGenerationData
var defs: FcDefinitionSet


func before_each() -> void:
	data = FcGenerationData.load_default()
	defs = FcDefinitionSet.load_default()


func _cap(preset: String = "soft_cap_with_hard_limit") -> FcCapRules:
	return FcCapRules.from_preset(preset, 140000000, FcCapRules.load_presets())


func _errors_contain(errors: Array[String], text: String) -> bool:
	for e in errors:
		if text in e:
			return true
	return false


# --- 80-game seasons ---------------------------------------------------------

func test_standard_league_plays_exactly_80_games() -> void:
	var cfg := FcGenerationConfig.load_default(data)
	assert_eq(cfg.target_games, 80)
	var w := FcWorldGenerator.new(data, defs, cfg).generate(1)
	var league: FcLeague = w.leagues.get_by_id(1)
	var season := w.rules_of_league(1).season
	assert_eq(season.games_per_team(league), 80)
	assert_eq([season.games_per_division_opponent, season.games_per_conference_opponent, season.games_per_other_conference_opponent], [5, 3, 2])
	assert_eq(4 * 5 + 10 * 3 + 15 * 2, 80)
	var plan := FcMatchupPlanner.plan(league, season)
	assert_true(plan.max_home_away_gap() <= 1)
	assert_eq(plan.total_games(), 1200)
	for t in league.all_team_ids():
		assert_eq(plan.games_of(t), 80)


func test_every_valid_league_size_gets_an_even_season_near_80() -> void:
	for n in FcLeagueStructure.valid_team_counts():
		var s := FcLeagueStructure.suggest(n)
		var l := FcLeague.make_even(1, "T", s["conferences"], s["divisions_per_conference"], n)
		var rules := FcSeasonRules.suggest(l)
		var games := rules.games_per_team(l)
		assert_eq(games % 2, 0, "%d teams -> %d games must be even" % [n, games])
		assert_eq(rules.validate(l), [] as Array[String], "%d teams" % n)


func test_larger_leagues_land_close_to_80() -> void:
	for n in [24, 30, 32, 36, 40, 48, 60, 64]:
		var s := FcLeagueStructure.suggest(n)
		var l := FcLeague.make_even(1, "T", s["conferences"], s["divisions_per_conference"], n)
		var games := FcSeasonRules.suggest(l).games_per_team(l)
		assert_between(games, 66.0, 90.0, "%d teams -> %d games" % [n, games])


func test_leagues_too_small_for_80_get_the_longest_even_season_possible() -> void:
	for n in [12, 16, 20]:
		var s := FcLeagueStructure.suggest(n)
		var l := FcLeague.make_even(1, "T", s["conferences"], s["divisions_per_conference"], n)
		var chosen := FcSeasonRules.suggest(l).games_per_team(l)
		var best_even := 0
		for gd in range(1, 6):
			for gc in range(1, 4):
				for go in range(1, 4):
					var r := FcSeasonRules.new()
					r.games_per_division_opponent = gd
					r.games_per_conference_opponent = gc
					r.games_per_other_conference_opponent = go
					var g := r.games_per_team(l)
					if g % 2 == 0 and g > best_even:
						best_even = g
		assert_eq(chosen, best_even, "%d teams: longest even season" % n)


func test_small_leagues_are_short_but_even() -> void:
	var l := FcLeague.make_even(1, "T", 1, 1, 8)
	var r := FcSeasonRules.suggest(l)
	assert_eq(r.games_per_team(l) % 2, 0)
	assert_true(r.games_per_team(l) < 50, "an 8-team league cannot reach 80 games")
	assert_true(not r.advice(l).is_empty() or r.games_per_team(l) < 50)


# --- tax sharing and repeater tax -----------------------------------------------

func test_tax_is_shared_among_teams_under_the_cap() -> void:
	var cap := _cap()
	var result := cap.distribute_luxury_tax({1: 180000000, 2: 130000000, 3: 100000000, 4: 150000000, 5: 140000000})
	assert_eq(result["collected"], 18000000, "only team 1 is over the 168M line: 12M x 150%")
	assert_eq(result["payouts"].keys().size(), 3, "teams 2, 3 and 5 are at or under the cap")
	assert_eq(result["payouts"][2], 6000000)
	assert_eq(result["distributed"], 18000000)
	assert_eq(result["retained"], 0)
	assert_true(not result["payouts"].has(4), "over the cap but under the tax: no share")


func test_tax_distribution_rounding_and_settings() -> void:
	var cap := _cap()
	var result := cap.distribute_luxury_tax({1: 180000000, 2: 100000000, 3: 100000000, 4: 100000000})
	assert_eq(result["distributed"] + result["retained"], result["collected"], "no money disappears")
	assert_true(result["retained"] < 3, "at most a couple of dollars of rounding")
	cap.tax_distribution_percent = 50
	var half := cap.distribute_luxury_tax({1: 180000000, 2: 100000000})
	assert_eq(half["distributed"], 9000000)
	assert_eq(half["retained"], 9000000)
	var nobody := cap.distribute_luxury_tax({1: 180000000, 2: 150000000})
	assert_eq(nobody["distributed"], 0, "no team under the cap to receive it")
	assert_eq(nobody["retained"], nobody["collected"])
	assert_eq(_cap("hard_cap").distribute_luxury_tax({1: 100000000})["collected"], 0)


func test_repeater_tax() -> void:
	var cap := _cap()
	assert_eq(cap.tax_rate_for(0), 150)
	assert_eq(cap.tax_rate_for(2), 150)
	assert_eq(cap.tax_rate_for(3), 250)
	assert_eq(cap.luxury_tax(178000000), 15000000)
	assert_eq(cap.luxury_tax(178000000, 3), 25000000, "repeat taxpayer pays 250%")
	cap.repeater_tax_extra_percent = 0
	assert_eq(cap.luxury_tax(178000000, 4), 15000000, "switched off")
	var payouts := _cap().distribute_luxury_tax({1: 178000000, 2: 100000000}, {1: 3})
	assert_eq(payouts["collected"], 25000000)


# --- restriction line ---------------------------------------------------------------

func test_restriction_line_blocks_exceptions_and_loose_trades() -> void:
	var cap := _cap()
	assert_eq(cap.restriction_line, 177800000)
	assert_eq(cap.payroll_tier(172000000), "over_tax")
	assert_eq(cap.payroll_tier(180000000), "over_restriction")
	assert_eq(cap.payroll_tier(190000000), "over_limit")
	var mid := FcCapRules.SigningKind.MID_LEVEL
	assert_true(cap.check_signing(170000000, 12000000, mid).allowed, "below the line")
	var denied := cap.check_signing(178000000, 5000000, mid)
	assert_true(not denied.allowed and "restriction line" in denied.reason, denied.reason)
	assert_true(cap.check_signing(150000000, 20000000, FcCapRules.SigningKind.OWN_PLAYER).allowed)
	# trades: above the line a team may not take back more salary than it sends
	assert_true(cap.check_trade(160000000, 12000000, 10000000).allowed, "125% matching below the line")
	var strict := cap.check_trade(177000000, 12000000, 10000000)
	assert_true(not strict.allowed and "restriction line" in strict.reason, strict.reason)
	assert_true(cap.check_trade(177000000, 10000000, 10000000).allowed, "equal salaries are fine")


# --- rookie scale ----------------------------------------------------------------------

func test_rookie_scale() -> void:
	var cap := _cap()
	assert_eq(cap.rookie_salary(1, 60), cap.rookie_scale_top)
	assert_eq(cap.rookie_salary(60, 60), cap.rookie_scale_bottom)
	var previous := cap.rookie_salary(1, 60)
	for pick in range(2, 61):
		var s := cap.rookie_salary(pick, 60)
		assert_true(s <= previous, "pick %d never earns more than the pick before" % pick)
		assert_true(s >= cap.min_player_salary and s <= cap.max_player_salary)
		previous = s
	assert_eq(cap.rookie_salary(1, 1), cap.rookie_scale_top, "one-pick draft")
	assert_eq(cap.rookie_salary(99, 30), cap.rookie_scale_bottom, "picks past the end clamp")
	assert_true(cap.rookie_salary(30, 60) > cap.rookie_salary(60, 60))
	assert_eq(cap.rookie_contract_years, 4)
	assert_eq(cap.rookie_guaranteed_years, 2)
	var bigger := FcCapRules.from_preset("soft_cap_with_hard_limit", 200000000, FcCapRules.load_presets())
	assert_eq(bigger.rookie_salary(1, 60), 16000000, "scales with the cap")


# --- cornerstone extension -----------------------------------------------------------

func test_cornerstone_extension_rules() -> void:
	var cap := _cap()
	assert_eq(cap.cornerstone_max_salary, 49000000)
	assert_true(cap.cornerstone_max_salary > cap.max_player_salary)
	assert_true(cap.check_cornerstone_extension(7, true, 0, 49000000).allowed)
	assert_true(not cap.check_cornerstone_extension(5, true, 0, 49000000).allowed, "tenure")
	assert_true(not cap.check_cornerstone_extension(7, false, 0, 49000000).allowed, "criterion")
	assert_true(not cap.check_cornerstone_extension(7, true, 1, 49000000).allowed, "one per team")
	assert_true(not cap.check_cornerstone_extension(7, true, 0, 50000000).allowed, "above the cornerstone maximum")
	assert_true(not _cap("hard_cap").check_cornerstone_extension(9, true, 0, 40000000).allowed, "disabled in other presets")


func test_cornerstone_contract_may_exceed_normal_maximum() -> void:
	var cap := _cap()
	var c := FcTestData.contract(1, 1, 1)
	c.years[0].salary = 47000000
	c.years[1].salary = 47000000
	assert_true(_errors_contain(cap.validate_contract(c), "outside"), "too high for a normal contract")
	c.is_cornerstone = true
	assert_eq(cap.validate_contract(c), [] as Array[String])
	c.years[1].salary = 50000000
	assert_true(not cap.validate_contract(c).is_empty(), "still capped at the cornerstone maximum")
	assert_true(_errors_contain(_cap("hard_cap").validate_contract(c), "no cornerstone"))


# --- cap holds, sign-and-trade, no-trade ----------------------------------------------

func test_cap_holds() -> void:
	var cap := _cap()
	assert_eq(cap.cap_hold_amount(10000000), 12000000)
	assert_eq(cap.cap_hold_amount(100000), cap.min_player_salary, "never below the minimum")
	assert_eq(cap.cap_hold_amount(40000000), cap.max_player_salary, "never above the maximum")
	cap.cap_holds_enabled = false
	assert_eq(cap.cap_hold_amount(10000000), 0)


func test_sign_and_trade() -> void:
	var cap := _cap()
	assert_true(cap.check_sign_and_trade(150000000).allowed)
	var denied := cap.check_sign_and_trade(180000000)
	assert_true(not denied.allowed and "sign-and-trade" in denied.reason, denied.reason)
	assert_true(not _cap("hard_cap").check_sign_and_trade(100000000).allowed, "banned by this preset")


func test_no_trade_clauses() -> void:
	var cap := _cap()
	assert_true(cap.can_grant_no_trade(8))
	assert_true(not cap.can_grant_no_trade(7))
	var c := FcTestData.contract(1, 1, 1)
	c.years[0].salary = 5000000
	c.years[1].salary = 5200000
	assert_true(not cap.trade_requires_consent(c))
	c.no_trade = true
	assert_true(cap.trade_requires_consent(c))
	assert_eq(cap.validate_contract(c), [] as Array[String])
	var strict := _cap("hard_cap")
	assert_true(not strict.trade_requires_consent(c), "clauses are not recognised in this league")
	assert_true(_errors_contain(strict.validate_contract(c), "no-trade"))
	assert_true(not strict.can_grant_no_trade(20))


# --- validation, presets, saves --------------------------------------------------------

func test_extra_rule_validation() -> void:
	var cap := _cap()
	cap.restriction_line = 150000000
	cap.rookie_scale_top = 500000
	cap.rookie_guaranteed_years = 9
	cap.cornerstone_max_salary = 30000000
	cap.tax_distribution_percent = 150
	cap.cap_hold_percent = 400
	var errors := cap.validate()
	assert_true(_errors_contain(errors, "restriction line"))
	assert_true(_errors_contain(errors, "rookie scale"))
	assert_true(_errors_contain(errors, "guaranteed rookie years"))
	assert_true(_errors_contain(errors, "cornerstone maximum must be above"))
	assert_true(_errors_contain(errors, "tax distribution"))
	assert_true(_errors_contain(errors, "cap hold"))
	cap = _cap()
	cap.cornerstone_max_salary = 200000000
	assert_true(_errors_contain(cap.validate(), "cannot exceed"))


func test_all_presets_validate_with_extras() -> void:
	for name in ["soft_cap_with_hard_limit", "hard_cap", "no_cap"]:
		assert_eq(_cap(name).validate(), [] as Array[String], name)
	var hard := _cap("hard_cap")
	assert_eq([hard.restriction_line, hard.tax_distribution_percent, hard.cornerstone_enabled], [0, 0, false])
	var none := _cap("no_cap")
	assert_true(none.tax_distribution_percent > 0 and not none.cornerstone_enabled)


func test_extras_round_trip_and_old_saves_switch_extras_off() -> void:
	var cap := _cap()
	assert_eq(FcCapRules.from_dict(JSON.parse_string(JSON.stringify(cap.to_dict()))).to_dict(), cap.to_dict())
	var old := cap.to_dict()
	for key in ["tax_distribution_percent", "repeater_tax_extra_percent", "restriction_line", "cornerstone_enabled", "cap_holds_enabled", "no_trade_clauses_allowed", "rookie_scale_top"]:
		old.erase(key)
	var loaded := FcCapRules.from_dict(old)
	assert_eq([loaded.tax_distribution_percent, loaded.repeater_tax_extra_percent, loaded.restriction_line], [0, 0, 0])
	assert_true(not loaded.cornerstone_enabled and not loaded.cap_holds_enabled and not loaded.no_trade_clauses_allowed)
	assert_eq(loaded.luxury_tax(178000000, 4), 15000000, "an old league keeps its old tax behavior")
	assert_eq(loaded.validate(), [] as Array[String], "an old rule set is still consistent")


func test_contract_flags_round_trip_and_default_off() -> void:
	var c := FcTestData.contract(1, 1, 1)
	c.is_cornerstone = true
	c.no_trade = true
	var copy := FcContract.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	assert_true(copy.is_cornerstone and copy.no_trade)
	var old := FcTestData.contract(2, 1, 1).to_dict()
	old.erase("is_cornerstone")
	old.erase("no_trade")
	var loaded := FcContract.from_dict(old)
	assert_true(not loaded.is_cornerstone and not loaded.no_trade)


func test_generated_leagues_carry_the_extra_rules() -> void:
	var cfg := FcGenerationConfig.load_default(data)
	var w := FcWorldGenerator.new(data, defs, cfg).generate(6)
	assert_eq(w.validate(cfg.start_season), [] as Array[String])
	var cap := w.rules_of_league(1).cap
	assert_true(cap.cornerstone_enabled and cap.restriction_line > 0 and cap.tax_distribution_percent == 100)
	var payrolls := {}
	for t in w.teams.all():
		payrolls[t.id] = w.payroll_of_team(t.id, cfg.start_season)
	var result := cap.distribute_luxury_tax(payrolls)
	assert_eq(result["distributed"] + result["retained"], result["collected"])
