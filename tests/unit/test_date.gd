extends FcTestCase


func test_valid_and_invalid_dates() -> void:
	assert_true(FcDate.new(2024, 2, 29).is_valid(), "leap day 2024")
	assert_true(not FcDate.new(2023, 2, 29).is_valid(), "no leap day 2023")
	assert_true(not FcDate.new(1900, 2, 29).is_valid(), "1900 not leap")
	assert_true(FcDate.new(2000, 2, 29).is_valid(), "2000 is leap")
	assert_true(not FcDate.new(2024, 13, 1).is_valid(), "month 13")
	assert_true(not FcDate.new(2024, 4, 31).is_valid(), "april 31")
	assert_true(not FcDate.new(2024, 1, 0).is_valid(), "day 0")


func test_iso_round_trip_and_bad_text() -> void:
	var d := FcDate.from_iso("2003-09-05")
	assert_true(d != null)
	assert_eq(d.to_iso(), "2003-09-05")
	assert_true(FcDate.from_iso("2003-9") == null, "too few parts")
	assert_true(FcDate.from_iso("abcd-01-01") == null, "not numbers")
	assert_true(FcDate.from_iso("2003-02-30") == null, "impossible day")
	assert_true(FcDate.from_iso("") == null, "empty")


func test_comparison() -> void:
	var a := FcDate.new(2020, 1, 1)
	var b := FcDate.new(2020, 1, 2)
	assert_true(a.is_before(b))
	assert_true(not b.is_before(a))
	assert_true(a.equals(FcDate.new(2020, 1, 1)))
	assert_eq(b.compare_to(a), 1)


func test_years_until_counts_whole_years() -> void:
	var born := FcDate.new(2000, 6, 15)
	assert_eq(born.years_until(FcDate.new(2026, 6, 14)), 25, "day before birthday")
	assert_eq(born.years_until(FcDate.new(2026, 6, 15)), 26, "on birthday")
	assert_eq(born.years_until(FcDate.new(2026, 12, 31)), 26, "later in year")
