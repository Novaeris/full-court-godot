extends FcTestCase
## FIXTURE: a normal passing test (proves the runner still exits 0 for a healthy folder).

func test_one() -> void:
	assert_eq(2 + 2, 4)


func test_two() -> void:
	assert_true(not false)
