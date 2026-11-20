extends FcTestCase
## FIXTURE (live runner): a script error AFTER an await. The assertion after it never runs; the runner must still fail the test.

func test_error_after_waiting() -> void:
	await Engine.get_main_loop().process_frame
	assert_true(true)
	var nothing = null
	nothing.broken_after_await()
	assert_true(false, "never reached")
