extends FcTestCase
## FIXTURE: a runtime script error in the middle of a test. The assertion after it never runs; the runner must still fail the test.

func test_aborts_with_a_script_error() -> void:
	assert_true(true, "this assertion passes")
	var nothing = null
	nothing.no_such_method()   # Invalid call on null: Godot aborts this function here
	assert_true(false, "never reached")


func test_fails_normally() -> void:
	assert_eq(1, 2, "an ordinary failed assertion")
