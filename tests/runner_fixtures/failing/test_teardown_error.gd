extends FcTestCase
## FIXTURE: an error in after_each (teardown) after a passing test.

func after_each() -> void:
	var nothing = null
	nothing.teardown_that_fails()


func test_body_passes_by_itself() -> void:
	assert_true(true)
