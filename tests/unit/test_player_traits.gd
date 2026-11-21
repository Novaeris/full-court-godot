extends FcTestCase
## The extra face variation for the high-fidelity figure (FcPlayerTraits): deterministic, in range, varied, age-aware, and strictly additive
## (it must never change what FcPlayerVisual.resolve returns: that is pinned by test_player_identity_golden and by save compatibility).


func test_traits_are_deterministic_and_in_range() -> void:
	for i in 60:
		var key := "traits:%d" % i
		var a := FcPlayerTraits.of(key)
		assert_eq(a, FcPlayerTraits.of(key), "the same key gives the same traits")
		assert_true(int(a["age"]) >= 19 and int(a["age"]) <= 38, "the derived age is 19 to 38")
		assert_true(int(a["eye_shape"]) >= 0 and int(a["eye_shape"]) <= 2)
		assert_true(int(a["undertone"]) >= 0 and int(a["undertone"]) <= 4)
		assert_true(int(a["iris"]) >= 0 and int(a["iris"]) < FcPlayerTraits.IRIS_COLORS.size())
		assert_true(int(a["grey"]) >= 0 and int(a["grey"]) <= 3)
		for k in a:
			assert_true(a[k] is int, "%s is an integer (no raw floats)" % k)


func test_traits_are_varied() -> void:
	var seen := {}
	for i in 100:
		var t := FcPlayerTraits.of("var:%d" % i)
		seen["%d%d%d%d%d%d" % [t["eye_shape"], t["nose_w"], t["lips"], t["forehead"], t["cheek"], t["undertone"]]] = true
	assert_true(seen.size() >= 60, "100 keys give at least 60 different feature combinations, got %d" % seen.size())


func test_age_changes_only_the_age_marks() -> void:
	var young := FcPlayerTraits.of("age:1", 20)
	var old := FcPlayerTraits.of("age:1", 40)
	for k in young:
		if not (k in ["age", "grey", "lines"]):
			assert_eq(young[k], old[k], "%s is the same face at any age" % k)
	assert_true(int(old["lines"]) > int(young["lines"]), "an older face has more lines")
	assert_true(int(old["grey"]) >= int(young["grey"]), "an older head has at least as much grey")
	assert_eq(int(FcPlayerTraits.of("age:1", 99)["age"]), FcPlayerTraits.MAX_AGE, "age is clamped")


func test_adding_traits_does_not_change_the_resolved_identity() -> void:
	var subject := FcPlayerPresentation.subject("golden:7", "Golden", {}, 0)
	var before := FcPlayerVisual.resolve(subject)
	FcPlayerTraits.of("golden:7", 33)
	var after := FcPlayerVisual.resolve(subject)
	assert_eq(before["identity"]["proportions"], after["identity"]["proportions"])
	assert_eq(str(before["identity"]["skin"]), str(after["identity"]["skin"]))
	assert_true(not before.has("age"), "resolve() returns no age: it is not part of the identity")


func test_the_skin_stays_in_its_tone_family() -> void:
	for tone in FcPlayerVisual.SKIN_TONES:
		var base := Color(str(FcPlayerVisual.SKIN_TONES[tone]))
		for undertone in 5:
			var shown := FcPlayerTraits.skin(base, 1, undertone)
			assert_true(absf(shown.r - base.r) < 0.07 and absf(shown.g - base.g) < 0.04 and absf(shown.b - base.b) < 0.07, "%s undertone %d stays near its tone" % [tone, undertone])


func test_the_approved_figure_is_the_default() -> void:
	assert_true(FcPlayerFigure.hd_enabled, "the high-fidelity figure (D-059, approved) is the default")
