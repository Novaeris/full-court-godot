extends FcTestCase


func test_ids_start_at_one_and_increase() -> void:
	var g := FcIdGenerator.new()
	assert_eq(g.next_id("player"), 1)
	assert_eq(g.next_id("player"), 2)


func test_kinds_are_independent() -> void:
	var g := FcIdGenerator.new()
	g.next_id("player")
	g.next_id("player")
	assert_eq(g.next_id("team"), 1)
	assert_eq(g.issued_count("player"), 2)


func test_round_trip_through_save_data() -> void:
	var g := FcIdGenerator.new()
	g.next_id("player")
	g.next_id("player")
	var loaded := FcIdGenerator.new()
	loaded.from_dict(g.to_dict())
	assert_eq(loaded.next_id("player"), 3, "no ID reuse after load")
