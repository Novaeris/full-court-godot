extends FcTestCase
## FIXTURE: a test file with no test_ methods (a typo in a method name would look like this).

func tset_misspelled_test() -> void:
	assert_true(false)
