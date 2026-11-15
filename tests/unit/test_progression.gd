extends FcTestCase

var defs: FcDefinitionSet
var ratings: FcPlayerRatings
var progression: FcPlayerProgression


func before_each() -> void:
	defs = FcDefinitionSet.load_default()
	ratings = FcPlayerRatings.load_default()
	progression = FcPlayerProgression.new(defs, ratings)


func _player(level: int, potential: int, peak: int = 27) -> FcPlayer:
	var p := FcTestData.player(1, defs)
	for key in defs.attributes.keys():
		p.attributes.set_clamped(key, level)
	p.development.potential = potential
	p.development.peak_age = peak
	p.development.development_rate = 1.0
	p.development.volatility = 0.2
	return p


func _average_change(level: int, potential: int, age: int, coach: float = 50.0, runs: int = 60) -> float:
	var rng := FcRng.new(age * 100 + level)
	var total := 0.0
	for i in runs:
		var p := _player(level, potential)
		var r := progression.progress(p, age, coach, rng)
		total += r["after"] - r["before"]
	return total / runs


func test_young_players_grow_toward_potential() -> void:
	assert_true(_average_change(45, 75, 20) > 2.0, "a 20-year-old with room grows fast")
	assert_between(_average_change(45, 75, 20), 2.5, 5.0, "about (75 - 45) / 8 years left, a little more with the growth multipliers")
	assert_between(_average_change(60, 62, 22), -1.0, 1.5, "little room means little growth")


func test_old_players_decline() -> void:
	assert_true(_average_change(70, 70, 31) < -0.5, "30-somethings decline")
	assert_true(_average_change(70, 70, 36) < _average_change(70, 70, 31), "and decline faster when older")


func test_physical_attributes_decline_faster_than_mental() -> void:
	var rng := FcRng.new(9)
	var physical := 0.0
	var mental := 0.0
	for i in 60:
		var p := _player(70, 70)
		progression.progress(p, 34, 50.0, rng)
		for key in defs.attributes.keys_in_category("physical"):
			physical += p.attributes.get_value(key) - 70
		for key in defs.attributes.keys_in_category("mental"):
			mental += p.attributes.get_value(key) - 70
	physical /= 60.0 * defs.attributes.keys_in_category("physical").size()
	mental /= 60.0 * defs.attributes.keys_in_category("mental").size()
	assert_true(physical < mental - 1.0, "athletes lose athleticism before basketball IQ (%.1f vs %.1f)" % [physical, mental])


func test_development_rate_work_ethic_and_coaching_matter() -> void:
	var rng_a := FcRng.new(4)
	var rng_b := FcRng.new(4)
	var fast := 0.0
	var slow := 0.0
	for i in 80:
		var a := _player(45, 80)
		a.development.development_rate = 1.4
		var b := _player(45, 80)
		b.development.development_rate = 0.6
		fast += progression.progress(a, 21, 50.0, rng_a)["after"] - 45
		slow += progression.progress(b, 21, 50.0, rng_b)["after"] - 45
	assert_true(fast > slow * 1.4, "a high development rate grows faster")
	assert_true(_average_change(45, 80, 21, 90.0) > _average_change(45, 80, 21, 10.0) + 0.5, "a great developer coach helps")
	var rng := FcRng.new(6)
	var hard := _player(45, 80)
	var lazy := _player(45, 80)
	hard.attributes.set_clamped("work_ethic", 95)
	lazy.attributes.set_clamped("work_ethic", 5)
	var hard_gain := 0.0
	var lazy_gain := 0.0
	for i in 60:
		var h := _player(45, 80)
		h.attributes.set_clamped("work_ethic", 95)
		var l := _player(45, 80)
		l.attributes.set_clamped("work_ethic", 5)
		hard_gain += progression.progress(h, 21, 50.0, rng)["after"]
		lazy_gain += progression.progress(l, 21, 50.0, rng)["after"]
	assert_true(hard_gain > lazy_gain, "work ethic helps")


func test_progression_stays_in_range_and_keeps_data_valid() -> void:
	var rng := FcRng.new(2)
	for age in [19, 24, 28, 33, 38, 41]:
		for level in [8, 50, 97]:
			var p := _player(level, 90)
			for year in 5:
				progression.progress(p, age + year, 50.0, rng)
			assert_eq(p.validate(), [] as Array[String], "age %d level %d" % [age, level])
			for key in defs.attributes.keys():
				var v := p.attributes.get_value(key)
				assert_true(v >= 0 and v <= 100)
			assert_true(p.development.potential >= 0 and p.development.potential <= 100)


func test_potential_is_never_below_current_ability() -> void:
	var rng := FcRng.new(8)
	for i in 50:
		var p := _player(60, 55)
		var r := progression.progress(p, 26, 50.0, rng)
		assert_true(p.development.potential >= roundi(r["after"]) - 1)


func test_progression_is_reproducible() -> void:
	var a := _player(50, 80)
	var b := _player(50, 80)
	progression.progress(a, 22, 55.0, FcRng.new(3))
	progression.progress(b, 22, 55.0, FcRng.new(3))
	assert_eq(a.to_dict(), b.to_dict())


func test_retirement_chances_by_age() -> void:
	assert_eq(progression.retirement_chance(28, 70.0), 0.0)
	assert_eq(progression.retirement_chance(32, 30.0), 0.0, "nobody retires before the start age")
	assert_true(progression.retirement_chance(34, 60.0) > 0.0)
	assert_true(progression.retirement_chance(37, 60.0) > progression.retirement_chance(34, 60.0))
	assert_true(progression.retirement_chance(35, 35.0) > progression.retirement_chance(35, 70.0), "weak veterans retire sooner")
	assert_eq(progression.retirement_chance(42, 90.0), 1.0, "everyone retires eventually")
	var retired := 0
	var rng := FcRng.new(5)
	for i in 1000:
		if progression.should_retire(_player(60, 60), 36, rng):
			retired += 1
	assert_between(retired / 1000.0, 0.22, 0.38, "a 36-year-old retires about 3 years x 9% = 27% of the time")


func test_a_career_looks_like_a_career() -> void:
	# A 19-year-old prospect: should rise, peak around his peak age, then fall.
	var rng := FcRng.new(12)
	var peaks := []
	var at_19 := []
	var at_35 := []
	for run in 25:
		var p := _player(42, 78, 27)
		var best := 0.0
		for age in range(20, 37):
			var r := progression.progress(p, age, 50.0, rng)
			best = maxf(best, r["after"])
			if age == 20:
				at_19.append(r["before"])
			if age == 36:
				at_35.append(r["after"])
		peaks.append(best)
	var mean := func(values: Array) -> float:
		var t := 0.0
		for v in values:
			t += v
		return t / values.size()
	assert_true(mean.call(peaks) > mean.call(at_19) + 12.0, "he improves a lot")
	assert_true(mean.call(peaks) > mean.call(at_35) + 8.0, "and declines by his mid-30s")
