extends FcTestCase


func _multi_year() -> FcContract:
	var c := FcTestData.contract(1, 10, 20)
	c.years.clear()
	c.years.append(FcContractYear.new(2026, 5000000))
	c.years.append(FcContractYear.new(2027, 6000000, 3000000))
	c.years.append(FcContractYear.new(2028, 7000000))
	c.bonuses.append(FcContractBonus.new(FcContractBonus.Kind.SIGNING, 2026, 1000000))
	return c


func test_basic_contract_queries() -> void:
	var c := _multi_year()
	assert_eq(c.validate(), [] as Array[String])
	assert_eq(c.start_season(), 2026)
	assert_eq(c.end_season(), 2028)
	assert_eq(c.length(), 3)
	assert_eq(c.salary_for(2027), 6000000)
	assert_eq(c.salary_for(2030), 0, "outside contract")
	assert_eq(c.total_value(), 19000000, "salaries plus bonus")
	assert_eq(c.total_guaranteed(), 5000000 + 3000000 + 7000000 + 1000000)


func test_cap_hit_includes_bonus_only_in_its_season() -> void:
	var c := _multi_year()
	assert_eq(c.cap_hit_for(2026), 6000000)
	assert_eq(c.cap_hit_for(2027), 6000000)
	c.bonuses[0].counts_against_cap = false
	assert_eq(c.cap_hit_for(2026), 5000000)
	assert_eq(c.cap_hit_for(2035), 0)


func test_status_controls_in_force() -> void:
	var c := _multi_year()
	assert_true(c.is_in_force_in(2027))
	assert_true(not c.is_in_force_in(2031))
	c.status = FcContract.Status.TERMINATED
	assert_true(not c.is_in_force_in(2027))


func test_declined_option_year_is_removed_from_deal() -> void:
	var c := _multi_year()
	c.years[2].option_type = FcContractYear.OptionType.TEAM
	assert_eq(c.length(), 3, "undecided option still counts")
	c.years[2].option_status = FcContractYear.OptionStatus.DECLINED
	assert_eq(c.length(), 2)
	assert_eq(c.end_season(), 2027)
	assert_eq(c.salary_for(2028), 0)
	assert_eq(c.total_value(), 12000000)
	c.years[2].option_status = FcContractYear.OptionStatus.EXERCISED
	assert_eq(c.salary_for(2028), 7000000)


func test_validation_catches_bad_contracts() -> void:
	var c := FcContract.new(0)
	assert_true(c.validate().size() >= 4, "no id, player, team or years")

	var gap := _multi_year()
	gap.years[2].season = 2030
	assert_true(not gap.validate().is_empty(), "non-consecutive seasons")

	var neg := _multi_year()
	neg.years[0].salary = -1
	assert_true(not neg.validate().is_empty(), "negative salary")

	var over := _multi_year()
	over.years[0].guaranteed = over.years[0].salary + 1
	assert_true(not over.validate().is_empty(), "guaranteed above salary")

	var stray_status := _multi_year()
	stray_status.years[0].option_status = FcContractYear.OptionStatus.EXERCISED
	assert_true(not stray_status.validate().is_empty(), "option status without an option")

	var bonus := _multi_year()
	bonus.bonuses[0].season = 2040
	assert_true(not bonus.validate().is_empty(), "bonus outside contract")

	var bad_date := _multi_year()
	bad_date.signed_on = FcDate.new(2026, 2, 31)
	assert_true(not bad_date.validate().is_empty(), "invalid signing date")


func test_round_trip() -> void:
	var c := _multi_year()
	c.years[1].option_type = FcContractYear.OptionType.PLAYER
	c.years[1].option_status = FcContractYear.OptionStatus.EXERCISED
	c.signed_on = FcDate.new(2026, 7, 6)
	var copy := FcContract.from_dict(c.to_dict())
	assert_eq(copy.to_dict(), c.to_dict())
	assert_eq(copy.total_value(), c.total_value())


func test_default_guarantee_is_full_salary() -> void:
	assert_eq(FcContractYear.new(2026, 900).guaranteed, 900)
	assert_eq(FcContractYear.new(2026, 900, 0).guaranteed, 0)
