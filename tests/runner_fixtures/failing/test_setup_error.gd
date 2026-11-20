extends FcTestCase
## FIXTURE: an error in before_each (setup). The test body then runs on bad state; the run must still be reported as failed.

var thing: Node


func before_each() -> void:
	var nothing = null
	nothing.setup_that_fails()


func test_body_passes_by_itself() -> void:
	assert_true(true)
