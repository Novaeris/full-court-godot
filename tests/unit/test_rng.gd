extends FcTestCase


func test_same_seed_gives_same_sequence() -> void:
	var a := FcRng.new(12345)
	var b := FcRng.new(12345)
	for i in 100:
		assert_eq(a.range_int(0, 1000000), b.range_int(0, 1000000), "draw %d" % i)


func test_different_seed_gives_different_sequence() -> void:
	var a := FcRng.new(1)
	var b := FcRng.new(2)
	var same := 0
	for i in 50:
		if a.range_int(0, 1000000) == b.range_int(0, 1000000):
			same += 1
	assert_true(same < 5, "sequences from different seeds look identical")


func test_fork_is_deterministic_and_independent() -> void:
	var root := FcRng.new(99)
	var g1 := root.fork("game")
	var g2 := FcRng.new(99).fork("game")
	var d := root.fork("draft")
	assert_eq(g1.range_int(0, 1000000), g2.range_int(0, 1000000), "same label")
	assert_true(g1.get_seed() != d.get_seed(), "different labels need different seeds")


func test_state_save_and_restore() -> void:
	var a := FcRng.new(7)
	for i in 10:
		a.next_float()
	var saved := a.get_state()
	var expected := a.next_float()
	var b := FcRng.new(0)
	b.set_state(saved)
	assert_eq(b.next_float(), expected, "restored generator continues identically")


func test_state_survives_json_with_huge_seed() -> void:
	# Regression: 64-bit values lose precision if stored as JSON numbers.
	var a := FcRng.new(9223372036854775807)
	for i in 7:
		a.next_float()
	var through_json = JSON.parse_string(JSON.stringify(a.get_state()))
	var b := FcRng.new(0)
	b.set_state(through_json)
	assert_eq(b.get_seed(), 9223372036854775807, "seed preserved")
	for i in 20:
		assert_eq(b.range_int(0, 1000000000), a.range_int(0, 1000000000), "draw %d" % i)


func test_chance_matches_probability() -> void:
	var r := FcRng.new(2024)
	var hits := 0
	for i in 10000:
		if r.chance(0.3):
			hits += 1
	assert_between(hits / 10000.0, 0.27, 0.33, "30% chance")


func test_gaussian_mean() -> void:
	var r := FcRng.new(5)
	var sum := 0.0
	for i in 10000:
		sum += r.gaussian(50.0, 10.0)
	assert_between(sum / 10000.0, 49.0, 51.0, "gaussian mean")


func test_weighted_index_respects_weights() -> void:
	var r := FcRng.new(11)
	var counts := [0, 0, 0]
	for i in 10000:
		counts[r.weighted_index([1.0, 0.0, 3.0])] += 1
	assert_eq(counts[1], 0, "zero weight never chosen")
	assert_between(counts[2] / 10000.0, 0.72, 0.78, "weight 3 of 4")
