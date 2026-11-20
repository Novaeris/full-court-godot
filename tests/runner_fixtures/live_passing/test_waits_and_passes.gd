extends FcTestCase
## FIXTURE (live runner): a healthy awaiting test.

func test_waits() -> void:
	await Engine.get_main_loop().process_frame
	assert_true(true)
