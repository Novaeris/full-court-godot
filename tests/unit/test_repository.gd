extends FcTestCase


func test_add_get_update_remove() -> void:
	var repo: FcRepository = FcMemoryRepository.new()
	var city := FcTestData.city(5)
	assert_eq(repo.add(city), OK)
	assert_eq(repo.add(city), ERR_ALREADY_EXISTS)
	assert_eq(repo.add(FcTestData.city(0)), ERR_INVALID_PARAMETER)
	assert_true(repo.has_id(5))
	assert_true(repo.get_by_id(5) == city)
	assert_true(repo.get_by_id(6) == null)
	var replacement := FcTestData.city(5)
	replacement.name = "Newtown"
	assert_eq(repo.update(replacement), OK)
	assert_eq(repo.get_by_id(5).name, "Newtown")
	assert_eq(repo.update(FcTestData.city(99)), ERR_DOES_NOT_EXIST)
	assert_eq(repo.remove(5), OK)
	assert_eq(repo.remove(5), ERR_DOES_NOT_EXIST)
	assert_eq(repo.count(), 0)


func test_ids_and_all_are_sorted() -> void:
	var repo: FcRepository = FcMemoryRepository.new()
	for i in [9, 2, 5]:
		repo.add(FcTestData.city(i))
	assert_eq(repo.ids(), [2, 5, 9] as Array[int])
	assert_eq(repo.all().map(func(c): return c.id), [2, 5, 9])
