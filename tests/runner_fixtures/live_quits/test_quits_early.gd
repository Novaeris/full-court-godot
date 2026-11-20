extends FcTestCase
## FIXTURE (live runner): a test that ends the whole process while the run is in progress. The run did not finish, so the exit code
## must not be 0.

func test_calls_quit_then_waits() -> void:
	Engine.get_main_loop().quit(0)
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
